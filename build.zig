const std = @import("std");
const src = @import("src/build/sources.zig");

const Options = @import("src/build/Options.zig");
pub const InstallLink = @import("src/build/InstallLink.zig");

const Build = std.Build;
const StringList = std.ArrayList([]const u8);

inline fn endsWith(haystack: []const u8, needles: []const []const u8) bool {
	return for (needles) |needle| {
		if (std.mem.endsWith(u8, haystack, needle)) {
			break true;
		}
	} else false;
}

fn installFiles(
	b: *Build,
	dep: *Build.Dependency,
	install: *Build.Step.InstallArtifact,
	src_path: []const u8,
	dest_path: []const u8,
	exts: []const []const u8,
) !void {
	// Using `getPath3` outside of the make phase. Normally, this would be bad,
	// but it's from a dependency, so the files are there at graph construction time.
	const io = b.graph.io;
	var dir = try dep.path(src_path).getPath3(b, null)
		.openDir(io, "", .{ .iterate = true });
	defer dir.close(io);
	var iter = dir.iterate();
	while (try iter.next(io)) |f| {
		if (f.kind != .file or !endsWith(f.name, exts)) {
			continue;
		}
		const path = b.fmt("{s}/{s}", .{ src_path, f.name });
		const path2 = b.fmt("{s}/{s}", .{ dest_path, path });
		install.step.dependOn(&b.addInstallFile(dep.path(path), path2).step);
	}
}

pub fn extension(
	b: *Build,
	target: Build.ResolvedTarget,
) []const u8 {
	const os = target.result.os.tag;
	const arch = target.result.cpu.arch;
	return b.fmt(".{s}_{s}", .{
		if      (os.isDarwin())  "d"
		else if (os == .windows) "m"
		else                     "l"
		,
		if      (arch == .x86_64)  "amd64"
		else if (arch == .x86)     "i386"
		else if (arch.isArm())     "arm"
		else if (arch.isAARCH64()) "arm64"
		else if (arch.isPowerPC()) "ppc"
		else                       @tagName(arch)
	});
}

pub fn build(b: *Build) !void {
	const target = b.standardTargetOptions(.{});
	const optimize = b.standardOptimizeOption(.{});

	const upstream = b.dependency("pd", .{
		.target = target,
		.optimize = optimize,
	});
	const root = upstream.path(".");
	const os = target.result.os.tag;
	const opt: Options = .init(b, os);
	const mem = b.allocator;

	//---------------------------------------------------------------------------
	// Zig extern module
	const zig_mod = b.addModule("pd", .{
		.target = target,
		.optimize = optimize,
		.root_source_file = b.path("src/pd.zig"),
		.imports = &.{.{ .name = "options", .module = blk: {
			const o = b.addOptions();
			o.addOption(u8, "float_size", opt.float_size);
			break :blk o.createModule();
		}}},
	});

	//---------------------------------------------------------------------------
	// Library
	const lib = try @import("src/build/lib.zig").addLibrary(b, .{
		.opt = opt,
		.dep = upstream,
		.target = target,
		.optimize = optimize,
	});
	b.installArtifact(lib);

	const zig_lib_mod = b.addModule("libpd", .{
		.target = target,
		.optimize = optimize,
		.root_source_file = b.path("src/libpd.zig"),
		.imports = &.{.{ .name = "pd", .module = zig_mod }},
	});
	zig_lib_mod.linkLibrary(lib);

	//---------------------------------------------------------------------------
	// Executable
	const exe = try @import("src/build/exe.zig").addExecutable(b, .{
		.opt = opt,
		.dep = upstream,
		.target = target,
		.optimize = optimize,
	});
	const install_exe = b.addInstallArtifact(exe, .{});

	const pd_path: Build.LazyPath = .{ .cwd_relative = b.getInstallPath(.bin, "pd") };
	const exe_symlink: *InstallLink = .add(b, pd_path, "lib/pd/bin/pd");
	exe_symlink.step.dependOn(&install_exe.step);

	const step_install = b.step("exe", "Build the executable");
	step_install.dependOn(&exe_symlink.step);

	const run = b.addRunArtifact(exe);
	run.step.dependOn(&exe_symlink.step);
	const step_run = b.step("run", "Build and run the executable");
	step_run.dependOn(&run.step);
	if (b.args) |args| {
		run.addArgs(args);
	}

	//---------------------------------------------------------------------------
	// Watchdog
	const mod_args: Build.Module.CreateOptions = .{
		.target = target,
		.optimize = optimize,
		.link_libc = true,
	};

	var flags: StringList = .{};
	defer flags.deinit(mem);
	if (optimize != .Debug) {
		try flags.appendSlice(mem, &.{
			"-ffast-math",
			"-funroll-loops",
			"-fomit-frame-pointer",
			"-Wno-error=date-time",
		});
	}
	if (os == .linux or os == .freebsd) {
		try flags.appendSlice(mem, &.{
			"-Wno-int-to-pointer-cast",
			"-Wno-pointer-to-int-cast",
		});
	}

	if (opt.watchdog) {
		exe.root_module.addCMacro("PD_WATCHDOG", "1");
		const watchdog = b.addExecutable(.{
			.name = "pd-watchdog",
			.root_module = b.createModule(mod_args),
		});
		watchdog.root_module.addCSourceFiles(.{
			.root = root,
			.files = &src.watchdog,
			.flags = flags.items,
		});
		install_exe.step.dependOn(&b.addInstallArtifact(watchdog, .{
			.dest_dir = .{ .override = .{ .custom = "lib/pd/bin" } },
		}).step);
	}

	//---------------------------------------------------------------------------
	// Send & Receive
	{
		const send = b.addExecutable(.{
			.name = "pdsend",
			.root_module = b.createModule(mod_args),
		});
		send.root_module.addCSourceFiles(.{
			.root = root,
			.files = &src.send,
			.flags = flags.items
		});
		install_exe.step.dependOn(&b.addInstallArtifact(send, .{}).step);

		const receive = b.addExecutable(.{
			.name = "pdreceive",
			.root_module = b.createModule(mod_args),
		});
		receive.root_module.addCSourceFiles(.{
			.root = root,
			.files = &src.receive,
			.flags = flags.items
		});
		install_exe.step.dependOn(&b.addInstallArtifact(receive, .{}).step);
	}

	//---------------------------------------------------------------------------
	// Tcl
	{
		try installFiles(b, upstream, install_exe, "tcl", "lib/pd",
			&.{ ".tcl", ".txt", ".gif" });

		const pd_gui = b.addConfigHeader(.{
			.style = .{ .autoconf_at = upstream.path("tcl/pd-gui.in") },
		}, .{
			.prefix = b.install_prefix,
			.exec_prefix = "${prefix}",
			.libdir = "${exec_prefix}/lib",
			.PACKAGE = "pd",
		});

		const tail = b.addSystemCommand(&.{ "tail", "-n", "+2" });
		tail.setStdIn(.{ .lazy_path = pd_gui.getOutputFile() });

		const chmod = b.addSystemCommand(&.{ "chmod", "+x" });
		const out = tail.captureStdOut(.{});
		chmod.addFileArg(out);
		chmod.step.dependOn(&tail.step);

		const install_pdgui = b.addInstallBinFile(out, "pd-gui");
		install_pdgui.step.dependOn(&chmod.step);
		install_exe.step.dependOn(&install_pdgui.step);
	}

	//---------------------------------------------------------------------------
	// Extra
	{
		const ext = extension(b, target);
		for (&src.extra) |x| {
			const mod = b.createModule(mod_args);
			mod.addCMacro("PD", "1");
			mod.addIncludePath(upstream.path("src"));
			mod.addCSourceFiles(.{
				.root = root,
				.files = &.{ x },
				.flags = flags.items
			});

			const end = x.len - 2;
			const dir = std.fs.path.dirname(x).?;
			const dll = b.addLibrary(.{
				.name = x[dir.len + 1..end],
				.linkage = .dynamic,
				.root_module = mod,
			});

			const install_dll = b.addInstallFile(dll.getEmittedBin(),
				b.fmt("lib/pd/{s}{s}", .{ x[0..end], ext }));
			install_dll.step.dependOn(&dll.step);
			install_exe.step.dependOn(&install_dll.step);
			try installFiles(b, upstream, install_exe, dir, "lib/pd",
				&.{ ".pd", ".txt" });
		}
		try installFiles(b, upstream, install_exe, "extra", "lib/pd",
			&.{ ".pd", ".txt" });

		// Zig extern examples
		for (&src.zig_extra) |x| {
			const path = b.fmt("extra/{s}/{s}", .{ x, x });
			const dll = b.addLibrary(.{
				.name = x,
				.linkage = .dynamic,
				.root_module = b.createModule(.{
					.target = target,
					.optimize = optimize,
					.link_libc = true,
					.root_source_file = b.path(b.fmt("{s}.zig", .{ path })),
					.imports = &.{.{ .name = "pd", .module = zig_mod }},
				}),
			});
			const install_dll = b.addInstallFile(dll.getEmittedBin(),
				b.fmt("lib/pd/{s}{s}", .{ path, ext }));
			install_dll.step.dependOn(&dll.step);
			install_exe.step.dependOn(&install_dll.step);

			const help = b.fmt("{s}-help.pd", .{ path });
			const help2 = b.fmt("lib/pd/{s}", .{ help });
			install_exe.step.dependOn(&b.addInstallFile(b.path(help), help2).step);
		}
	}

	//---------------------------------------------------------------------------
	// Docs
	install_exe.step.dependOn(&b.addInstallDirectory(.{
		.exclude_extensions = &.{ "Makefile", ".am", ".in" },
		.source_dir = upstream.path("doc"),
		.install_subdir = "lib/pd/doc",
		.install_dir = .prefix,
	}).step);

	//---------------------------------------------------------------------------
	// Resources
	if (os == .linux) {
		install_exe.step.dependOn(&b.addInstallFile(
			upstream.path("linux/org.puredata.pd-gui.desktop"),
			"share/applications/org.puredata.pd-gui.desktop",
		).step);
		install_exe.step.dependOn(&b.addInstallFile(
			upstream.path("linux/org.puredata.pd-gui.metainfo.xml"),
			"share/metainfo/org.puredata.pd-gui.metainfo.xml",
		).step);

		// Icons
		install_exe.step.dependOn(&b.addInstallFile(
			upstream.path("linux/icons/48x48/puredata.png"),
			"share/icons/hicolor/48x48/apps/puredata.png",
		).step);
		install_exe.step.dependOn(&b.addInstallFile(
			upstream.path("linux/icons/512x512/puredata.png"),
			"share/icons/hicolor/512x512/apps/puredata.png",
		).step);
		install_exe.step.dependOn(&b.addInstallFile(
			upstream.path("linux/icons/puredata.svg"),
			"share/icons/hicolor/scalable/apps/puredata.svg",
		).step);

		try installFiles(b, upstream, install_exe, "font", "share/pd",
			&.{ ".ttf", ".txt", "LICENSE" });
		try installFiles(b, upstream, install_exe, ".", "share/pd",
			&.{ "LICENSE.txt", "README.txt" });
	}
}
