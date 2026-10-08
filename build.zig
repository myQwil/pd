const std = @import("std");
const Translator = @import("translate_c").Translator;
const srcs = @import("src/build/sources.zig");

const Options = @import("src/build/Options.zig");

const Build = std.Build;
const StringList = std.ArrayList([]const u8);

inline fn installDir(
	b: *Build,
	dep: *Build.Dependency,
	install: *Build.Step.InstallArtifact,
	dest: []const u8,
	src: []const u8,
	exts: []const []const u8,
) void {
	install.step.dependOn(&b.addInstallDirectory(.{
		.include_extensions = exts,
		.source_dir = dep.path(src),
		.install_subdir = dest ++ "/" ++ src,
		.install_dir = .prefix,
	}).step);
}

inline fn installFile(
	b: *Build,
	dep: *Build.Dependency,
	install: *Build.Step.InstallArtifact,
	dest: []const u8,
	src: []const u8,
) void {
	const name = comptime std.fs.path.basenamePosix(src);
	install.step.dependOn(&b.addInstallFile(dep.path(src), dest ++ "/" ++ name).step);
}

pub fn extension(
	b: *Build,
	target: Build.ResolvedTarget,
	float_size: u8,
) []const u8 {
	const os = target.result.os.tag;
	const arch = target.result.cpu.arch;
	return b.fmt(".{s}-{s}-{d}{s}", .{
		if      (os.isDarwin())  "darwin"
		else if (os == .windows) "windows"
		else                     "linux"
		,
		if      (arch == .x86_64)  "amd64"
		else if (arch == .x86)     "i386"
		else if (arch.isArm())     "arm"
		else if (arch.isAARCH64()) "arm64"
		else if (arch.isPowerPC()) "ppc"
		else                       @tagName(arch)
		,
		float_size,
		if (os.isDarwin()) ".so" else target.result.dynamicLibSuffix(),
	});
}

pub fn build(b: *Build) !void {
	const target = b.standardTargetOptions(.{});
	const optimize = b.standardOptimizeOption(.{});

	const upstream = b.dependency("pd", .{});
	const root = upstream.path(".");
	const os = target.result.os.tag;
	const opt: Options = .init(b, os);
	const mem = b.allocator;

	// C translation
	const c: Translator = .init(b.dependency("translate_c", .{}), .{
		.c_source_file = b.path("src/build/pd_all.h"),
		.target = target,
		.optimize = optimize,
	});
	c.addIncludePath(upstream.path("src"));
	c.defineCMacro("PD_FLOATSIZE", b.fmt("{}", .{ opt.float_size }));

	// Zig extern module
	const zig_mod = b.addModule("pd", .{
		.target = target,
		.optimize = optimize,
		.root_source_file = b.path("src/pd.zig"),
		.imports = &.{
			.{ .name = "options", .module = blk: {
				const o = b.addOptions();
				o.addOption(bool, "multi", opt.lib.multi);
				break :blk o.createModule();
			}},
			.{ .name = "c", .module = c.mod },
		},
	});

	{ // Library
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
			.imports = &.{
				.{ .name = "pd", .module = zig_mod },
				.{ .name = "c", .module = c.mod },
			},
		});
		zig_lib_mod.linkLibrary(lib);
	}

	// Executable
	const exe = try @import("src/build/exe.zig").addExecutable(b, .{
		.opt = opt,
		.dep = upstream,
		.target = target,
		.optimize = optimize,
	});
	const install_exe = b.addInstallArtifact(exe, .{});

	{ // Build & Run Steps
		const step_exe = b.step("exe", "Build the executable");
		step_exe.dependOn(&install_exe.step);

		const run = b.addRunArtifact(exe);
		run.step.dependOn(&install_exe.step);
		run.addPassthruArgs();
		const step_run = b.step("run", "Build and run the executable");
		step_run.dependOn(&run.step);
	}

	{ // Symlink
		const symlink = b.addRunArtifact(b.addExecutable(.{
			.name = "symlink",
			.root_module = b.createModule(.{
				.root_source_file = b.path("src/build/symlink.zig"),
				.target = b.graph.host,
			}),
		}));
		symlink.addDirectoryArg2(b.graph.path(.install_lib, "pd/bin"), .{});
		symlink.addFileArg2(b.graph.path(.install_bin, exe.name), .{});
		install_exe.step.dependOn(&symlink.step);
	}

	const mod_args: Build.Module.CreateOptions = .{
		.target = target,
		.optimize = optimize,
		.link_libc = true,
	};

	var flags: StringList = .empty;
	defer flags.deinit(mem);
	if (optimize != .debug) {
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

	if (opt.watchdog) { // Watchdog
		exe.root_module.addCMacro("PD_WATCHDOG", "1");
		const watchdog = b.addExecutable(.{
			.name = "pd-watchdog",
			.root_module = b.createModule(mod_args),
		});
		watchdog.root_module.addCSourceFiles(.{
			.root = root,
			.files = srcs.watchdog,
			.flags = flags.items,
		});
		install_exe.step.dependOn(&b.addInstallArtifact(watchdog, .{
			.dest_dir = .{ .override = .{ .custom = "lib/pd/bin" } },
		}).step);
	}

	{ // Send & Receive
		const send = b.addExecutable(.{
			.name = "pdsend",
			.root_module = b.createModule(mod_args),
		});
		send.root_module.addCSourceFiles(.{
			.root = root,
			.files = srcs.send,
			.flags = flags.items
		});
		install_exe.step.dependOn(&b.addInstallArtifact(send, .{}).step);

		const receive = b.addExecutable(.{
			.name = "pdreceive",
			.root_module = b.createModule(mod_args),
		});
		receive.root_module.addCSourceFiles(.{
			.root = root,
			.files = srcs.receive,
			.flags = flags.items
		});
		install_exe.step.dependOn(&b.addInstallArtifact(receive, .{}).step);
	}

	{ // Tcl
		installDir(b, upstream, install_exe, "lib/pd", "tcl", &.{ ".tcl", ".txt", ".gif" });
		const gui = b.addRunArtifact(b.addExecutable(.{
			.name = "guiconf",
			.root_module = b.createModule(.{
				.root_source_file = b.path("src/build/guiconf.zig"),
				.target = b.graph.host,
			}),
		}));
		if (opt.prefix.len > 0) {
			gui.addArg(opt.prefix);
		} else {
			gui.addDirectoryArg2(b.graph.path(.install_prefix, ""),
				.{ .make_absolute = true });
		}
		const gui_stdout = gui.captureStdOut(.{});

		const chmod = b.addSystemCommand(&.{ "chmod", "+x" });
		chmod.addFileArg2(gui_stdout, .{});
		const install_pdgui = b.addInstallBinFile(gui_stdout, "pd-gui");
		install_pdgui.step.dependOn(&chmod.step);
		install_exe.step.dependOn(&install_pdgui.step);
	}

	{ // Extra
		const ext = extension(b, target, opt.float_size);
		for (srcs.extra) |x| {
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
			const lib = b.addLibrary(.{
				.name = x[dir.len + 1..end],
				.linkage = .dynamic,
				.root_module = mod,
			});

			const install_lib = b.addInstallFile(lib.getEmittedBin(),
				b.fmt("lib/pd/{s}{s}", .{ x[0..end], ext }));
			install_lib.step.dependOn(&lib.step);
			install_exe.step.dependOn(&install_lib.step);
		}
		installDir(b, upstream, install_exe, "lib/pd", "extra", &.{ ".pd", ".txt" });

		// Zig extern examples
		for (srcs.zig_extra) |x| {
			const path = b.fmt("extra/{s}/{s}", .{ x, x });
			const lib = b.addLibrary(.{
				.name = x,
				.linkage = .dynamic,
				.root_module = b.createModule(.{
					.target = target,
					.optimize = optimize,
					.root_source_file = b.path(b.fmt("{s}.zig", .{ path })),
					.imports = &.{.{ .name = "pd", .module = zig_mod }},
				}),
			});
			const install_lib = b.addInstallFile(lib.getEmittedBin(),
				b.fmt("lib/pd/{s}{s}", .{ path, ext }));
			install_lib.step.dependOn(&lib.step);
			install_exe.step.dependOn(&install_lib.step);
		}
		install_exe.step.dependOn(&b.addInstallDirectory(.{
			.include_extensions = &.{ ".pd", ".txt" },
			.source_dir = b.path("extra"),
			.install_subdir = "lib/pd/extra",
			.install_dir = .prefix,
		}).step);
	}

	// Docs
	install_exe.step.dependOn(&b.addInstallDirectory(.{
		.exclude_extensions = &.{ "Makefile", ".am", ".in" },
		.source_dir = upstream.path("doc"),
		.install_subdir = "lib/pd/doc",
		.install_dir = .prefix,
	}).step);

	// Resources
	if (os == .linux) {
		installFile(b, upstream, install_exe, "share/applications",
			"linux/info.puredata.Pd.desktop");
		installFile(b, upstream, install_exe, "share/metainfo",
			"linux/info.puredata.Pd.metainfo.xml");

		// Icons
		installFile(b, upstream, install_exe, "share/icons/hicolor/48x48/apps",
			"linux/icons/48x48/puredata.png");
		installFile(b, upstream, install_exe, "share/icons/hicolor/512x512/apps",
			"linux/icons/512x512/puredata.png");
		installFile(b, upstream, install_exe, "share/icons/hicolor/scalable/apps",
			"linux/icons/puredata.svg");

		// Fonts, License, Readme
		installDir(b, upstream, install_exe, "share/pd", "font",
			&.{ ".ttf", ".txt", "LICENSE" });
		installFile(b, upstream, install_exe, "share/pd", "LICENSE.txt");
		installFile(b, upstream, install_exe, "share/pd", "README.txt");
	}
}
