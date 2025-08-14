const std = @import("std");
const LinkMode = std.builtin.LinkMode;
const StringList = std.ArrayList([]const u8);

const Options = struct {
	lib: Lib = .{},
	float_size: u8 = 32,
	locales: bool = true,
	watchdog: bool = true,
	fftw: bool = false,
	portaudio: PortIO = .{},
	portmidi: PortIO = .{},
	oss: bool = true,
	alsa: bool = true,
	jack: bool = false,
	mmio: bool = false,
	asio: bool = false,
	wasapi: bool = false,

	const Lib = struct {
		linkage: LinkMode = .static,
		utils: bool = true,
		extra: bool = true,
		multi: bool = false,
		setlocale: bool = true,
	};

	const PortIO = struct {
		enabled: bool = true,
		local: bool = false,
	};

	fn init(
		b: *std.Build,
		os: std.Target.Os.Tag,
	) Options {
		const default: Options = .{};
		var opt: Options = .{
			.lib = .{
				.linkage = b.option(LinkMode, "linkage",
					"Library linking method"
				) orelse default.lib.linkage,

				.utils = b.option(bool, "utils",
					"Lib: Enable utilities"
				) orelse default.lib.utils,

				.extra = b.option(bool, "extra",
					"Lib: Include extra objects"
				) orelse default.lib.extra,

				.multi = b.option(bool, "multi",
					"Lib: Compile with multiple instance support"
				) orelse default.lib.multi,

				.setlocale = b.option(bool, "setlocale",
					"Lib: Set LC_NUMERIC automatically with setlocale()"
				) orelse default.lib.setlocale,
			},

			.float_size = b.option(u8, "float_size",
				"Size of a floating-point number"
			) orelse default.float_size,

			.locales = b.option(bool, "locales",
				"Compile localizations (requires gettext)"
			) orelse default.locales,

			.watchdog = b.option(bool, "watchdog",
				"Build watchdog"
			) orelse default.watchdog,

			.fftw = b.option(bool, "fftw",
				"Use FFTW package"
			) orelse default.fftw,

			.portaudio = .{
				.enabled = b.option(bool, "portaudio",
					"Use portaudio"
				) orelse default.portaudio.enabled,

				.local = b.option(bool, "local_portaudio",
					"Use local portaudio"
				) orelse default.portaudio.local,
			},

			.portmidi = .{
				.enabled = b.option(bool, "portmidi",
					"Use portmidi"
				) orelse default.portmidi.enabled,

				.local = b.option(bool, "local_portmidi",
					"Use local portmidi"
				) orelse default.portmidi.local,
			},

			.oss = b.option(bool, "oss",
				"Use OSS driver"
			) orelse default.oss,

			.alsa = b.option(bool, "alsa",
				"Use ALSA audio driver"
			) orelse default.alsa,

			.jack = b.option(bool, "jack",
				"Use JACK audio server"
			) orelse default.jack,
		};

		if (os == .windows) {
			opt.mmio = b.option(bool, "mmio",
				"Use MMIO driver"
			) orelse true;

			opt.asio = b.option(bool, "asio",
				"Use ASIO audio driver"
			) orelse true;

			opt.wasapi = b.option(bool, "wasapi",
				"Use WASAPI backend"
			) orelse true;
		}

		return opt;
	}
};

fn baseModule(
	b: *std.Build,
	opt: Options,
	dep: *std.Build.Dependency,
	target: std.Build.ResolvedTarget,
	optimize: std.builtin.OptimizeMode,
) *std.Build.Module {
	const mod = b.createModule(.{
		.target = target,
		.optimize = optimize,
		.link_libc = true,
	});
	mod.addIncludePath(dep.path("src"));

	mod.addCMacro("PD", "1");
	mod.addCMacro("PD_INTERNAL", "1");
	mod.addCMacro("HAVE_UNISTD_H", "1");
	mod.addCMacro("PD_FLOATSIZE", b.fmt("{}", .{ opt.float_size }));

	const os = target.result.os.tag;
	switch (os) {
		.windows => {
			mod.addCMacro("WINVER", "0x502");
			mod.addCMacro("WIN32", "1");
			mod.addCMacro("_WIN32", "1");
			mod.linkSystemLibrary("ws2_32", .{});
			mod.linkSystemLibrary("kernel32", .{});
		},
		.macos => {
			mod.addCMacro("HAVE_ALLOCA_H", "1");
			mod.addCMacro("HAVE_MACHINE_ENDIAN_H", "1");
			mod.addCMacro("_DARWIN_C_SOURCE", "1");
			mod.addCMacro("_DARWIN_UNLIMITED_SELECT", "1");
			mod.addCMacro("FD_SETSIZE", "10240");
			mod.addCMacro("HAVE_LIBDL", "1");
			mod.linkSystemLibrary("dl", .{});
		},
		.emscripten, .wasi => {
			const sysroot = b.sysroot
				orelse @panic("Pass '--sysroot \"$EMSDK/upstream/emscripten\"'");
			const cache_include = std.fs.path.join(b.allocator, &.{
				sysroot, "cache", "sysroot", "include",
			}) catch @panic("Out of memory");

			var dir = std.fs.openDirAbsolute(cache_include, std.fs.Dir.OpenOptions{
				.access_sub_paths = true,
				.no_follow = true,
			}) catch @panic("No emscripten cache. Generate it!");
			dir.close();
			mod.addSystemIncludePath(.{ .cwd_relative = cache_include });
		},
		.linux, .freebsd => {
			mod.addCMacro("HAVE_ENDIAN_H", "1");
			if (os == .linux) {
				mod.addCMacro("HAVE_ALLOCA_H", "1");
				mod.addCMacro("HAVE_LIBDL", "1");
				mod.linkSystemLibrary("dl", .{});
			}
		},
		else => {},
	}

	if (opt.fftw) {
		mod.linkSystemLibrary("fftw3f", .{});
	}
	return mod;
}

fn baseFiles(
	b: *std.Build,
	opt: Options,
) !StringList {
	var files: StringList = .init(b.allocator);
	try files.appendSlice(&src.core);
	try files.appendSlice(if (opt.fftw) &src.fftw else &src.fftsg);
	return files;
}

fn baseFlags(
	b: *std.Build,
	os: std.Target.Os.Tag,
	optimize: std.builtin.OptimizeMode,
) !StringList {
	var flags: StringList = .init(b.allocator);
	try flags.append("-fno-sanitize=undefined");
	if (optimize != .Debug) {
		try flags.appendSlice(&.{
			"-ffast-math",
			"-funroll-loops",
			"-fomit-frame-pointer",
			"-Wno-error=date-time",
		});
	}
	if (os == .linux or os == .freebsd) {
		try flags.appendSlice(&.{
			"-Wno-int-to-pointer-cast",
			"-Wno-pointer-to-int-cast",
		});
	}
	return flags;
}

inline fn endsWith(haystack: []const u8, needles: []const []const u8) bool {
	return for (needles) |needle| {
		if (std.mem.endsWith(u8, haystack, needle)) {
			break true;
		}
	} else false;
}

fn installFileType(
	b: *std.Build,
	dep: *std.Build.Dependency,
	install: *std.Build.Step.InstallArtifact,
	sub_path: []const u8,
	ext: []const u8,
) !void {
	var dir = try dep.path(sub_path).getPath3(b, null).openDir("", .{ .iterate = true });
	defer dir.close();
	var iter = dir.iterate();
	while (try iter.next()) |f| {
		if (f.kind != .file or !endsWith(f.name, &.{ ext, ".txt" })) {
			continue;
		}
		const path = b.fmt("{s}/{s}", .{ sub_path, f.name });
		const path2 = b.fmt("lib/pd/{s}", .{ path });
		install.step.dependOn(&b.addInstallFile(dep.path(path), path2).step);
	}
}

pub fn extension(
	b: *std.Build,
	target: std.Build.ResolvedTarget,
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

pub fn build(b: *std.Build) !void {
	const target = b.standardTargetOptions(.{});
	const optimize = b.standardOptimizeOption(.{});

	const upstream = b.dependency("pd", .{
		.target = target,
		.optimize = optimize,
	});
	const root = upstream.path(".");
	const os = target.result.os.tag;
	const opt: Options = .init(b, os);
	var flags = try baseFlags(b, os, optimize);
	defer flags.deinit();

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
	{
		const mod = baseModule(b, opt, upstream, target, optimize);
		if (os != .emscripten and os != .wasi and opt.lib.linkage == .dynamic) {
			mod.linkSystemLibrary("pthread", .{});
			mod.linkSystemLibrary("m", .{});
		}

		var files = try baseFiles(b, opt);
		defer files.deinit();

		try files.appendSlice(&src.lib);
		try files.appendSlice(&src.dummy);
		mod.addCMacro("USEAPI_DUMMY", "1");
		if (opt.lib.extra) {
			try files.appendSlice(&src.extra);
			mod.addCMacro("LIBPD_EXTRA", "1");
		}
		if (opt.lib.utils) {
			try files.appendSlice(&src.util);
		}

		if (opt.lib.multi) {
			mod.addCMacro("PDINSTANCE", "1");
			mod.addCMacro("PDTHREADS", "1");
		}
		if (!opt.lib.setlocale) {
			mod.addCMacro("LIBPD_NO_NUMERIC", "1");
		}

		mod.addCSourceFiles(.{
			.root = root,
			.files = files.items,
			.flags = flags.items,
		});

		const lib = b.addLibrary(.{
			.name = "pd",
			.linkage = opt.lib.linkage,
			.root_module = mod,
		});
		b.installArtifact(lib);

		const zig_lib_mod = b.addModule("libpd", .{
			.target = target,
			.optimize = optimize,
			.root_source_file = b.path("src/libpd.zig"),
			.imports = &.{.{ .name = "pd", .module = zig_mod }},
		});
		zig_lib_mod.linkLibrary(lib);
	}

	const exe = b.addExecutable(.{
		.name = "pd",
		.root_module = baseModule(b, opt, upstream, target, optimize),
	});
	exe.rdynamic = true;
	const install_exe = b.addInstallArtifact(exe, .{});

	//---------------------------------------------------------------------------
	// Executable
	{
		const mod = exe.root_module;
		if (os != .emscripten and os != .wasi) {
			mod.linkSystemLibrary("pthread", .{});
			mod.linkSystemLibrary("m", .{});
		}

		var files = try baseFiles(b, opt);
		defer files.deinit();

		try files.appendSlice(&src.standalone);
		try files.appendSlice(&src.entry);

		var have_audio_api: bool = false;
		if (opt.alsa) {
			try files.appendSlice(&src.alsa);
			mod.addCMacro("USEAPI_ALSA", "1");
			mod.linkSystemLibrary("asound", .{});
			have_audio_api = true;
		}
		if (opt.oss) {
			try files.appendSlice(&src.oss);
			mod.addCMacro("USEAPI_OSS", "1");
			have_audio_api = true;
		}
		if (opt.jack) {
			try files.appendSlice(&src.jack);
			mod.addCMacro("USEAPI_JACK", "1");
			mod.linkSystemLibrary("jack", .{});
			have_audio_api = true;
		}
		if (opt.portaudio.enabled) {
			try files.appendSlice(&src.portaudio);
			mod.addCMacro("USEAPI_PORTAUDIO", "1");
			if (opt.portaudio.local) {
				const pa = @import("build.portaudio.zig");
				mod.linkLibrary(try pa.library(b, target, optimize));
			} else {
				mod.linkSystemLibrary("portaudio", .{});
			}
			have_audio_api = true;
		}

		if (!have_audio_api) {
			mod.addCMacro("USEAPI_DUMMY", "1");
			try files.appendSlice(&src.dummy);
		} else if (opt.jack or opt.portaudio.enabled) {
			try files.appendSlice(&src.paring);
		}

		mod.addCSourceFiles(.{
			.root = root,
			.files = files.items,
			.flags = flags.items,
		});

		const step_install = b.step("exe", "Build the executable");
		step_install.dependOn(&install_exe.step);

		const run = b.addRunArtifact(exe);
		run.step.dependOn(&install_exe.step);
		const step_run = b.step("run", "Build and run the executable");
		step_run.dependOn(&run.step);
		if (b.args) |args| {
			run.addArgs(args);
		}
	}

	const mod_args: std.Build.Module.CreateOptions = .{
		.target = target,
		.optimize = optimize,
		.link_libc = true,
	};

	//---------------------------------------------------------------------------
	// Watchdog
	if (opt.watchdog) {
		exe.root_module.addCMacro("PD_WATCHDOG", "1");
		const watchdog = b.addExecutable(.{
			.name = "pd-watchdog",
			.root_module = b.createModule(mod_args),
		});
		watchdog.addCSourceFiles(.{
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
		send.addCSourceFiles(.{
			.root = root,
			.files = &src.send,
			.flags = flags.items
		});
		install_exe.step.dependOn(&b.addInstallArtifact(send, .{}).step);

		const receive = b.addExecutable(.{
			.name = "pdreceive",
			.root_module = b.createModule(mod_args),
		});
		receive.addCSourceFiles(.{
			.root = root,
			.files = &src.receive,
			.flags = flags.items
		});
		install_exe.step.dependOn(&b.addInstallArtifact(receive, .{}).step);
	}

	//---------------------------------------------------------------------------
	// Tcl
	try installFileType(b, upstream, install_exe, "tcl", ".tcl");
	install_exe.step.dependOn(&b.addInstallFile(
		upstream.path("tcl/pd.gif"), "lib/pd/tcl/pd.gif").step);

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
			const tail = std.mem.lastIndexOf(u8, x, "/").?;
			const lib = b.addLibrary(.{
				.name = x[tail + 1..end],
				.linkage = .dynamic,
				.root_module = mod,
			});

			const install_lib = b.addInstallFile(lib.getEmittedBin(),
				b.fmt("lib/pd/{s}{s}", .{ x[0..end], ext }));
			install_lib.step.dependOn(&lib.step);
			install_exe.step.dependOn(&install_lib.step);
			try installFileType(b, upstream, install_exe, x[0..tail], ".pd");
		}
		try installFileType(b, upstream, install_exe, "extra", ".pd");

		// Zig extern examples
		for (&src.zig_extra) |x| {
			const path = b.fmt("extra/{s}/{s}", .{ x, x });
			const lib = b.addLibrary(.{
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
			const install_lib = b.addInstallFile(lib.getEmittedBin(),
				b.fmt("lib/pd/{s}{s}", .{ path, ext }));
			install_lib.step.dependOn(&lib.step);
			install_exe.step.dependOn(&install_lib.step);

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
}

const src = struct {
	const lib = [_][]const u8{
		"src/z_libpd.c",
		"src/z_hooks.c",
		"src/x_libpdreceive.c",
		"src/s_libpdmidi.c",
	};

	const util = [_][]const u8{
		"src/z_print_util.c",
		"src/z_queued.c",
		"src/z_ringbuffer.c"
	};

	const extra = [_][]const u8{
		"extra/bob~/bob~.c",
		"extra/bonk~/bonk~.c",
		"extra/choice/choice.c",
		"extra/fiddle~/fiddle~.c",
		"extra/loop~/loop~.c",
		"extra/lrshift~/lrshift~.c",
		"extra/pique/pique.c",
		"extra/pd~/pdsched.c",
		"extra/pd~/pd~.c",
		"extra/sigmund~/sigmund~.c",
		"extra/stdout/stdout.c",
	};

	const zig_extra = [_][]const u8{
		"sesom",
	};

	const fftw = [_][]const u8{
		"src/d_fft_fftw.c",
	};

	const fftsg = [_][]const u8{
		"src/d_fft_fftsg.c",
	};

	const entry = [_][]const u8{
		"src/s_entry.c",
	};

	const core = [_][]const u8{
		"src/d_arithmetic.c",
		"src/d_array.c",
		"src/d_ctl.c",
		"src/d_dac.c",
		"src/d_delay.c",
		"src/d_fft.c",
		"src/d_filter.c",
		"src/d_global.c",
		"src/d_math.c",
		"src/d_misc.c",
		"src/d_osc.c",
		"src/d_resample.c",
		"src/d_soundfile.c",
		"src/d_soundfile_aiff.c",
		"src/d_soundfile_caf.c",
		"src/d_soundfile_next.c",
		"src/d_soundfile_wave.c",
		"src/d_ugen.c",
		"src/g_all_guis.c",
		"src/g_array.c",
		"src/g_bang.c",
		"src/g_canvas.c",
		"src/g_clone.c",
		"src/g_editor.c",
		"src/g_editor_extras.c",
		"src/g_graph.c",
		"src/g_guiconnect.c",
		"src/g_io.c",
		"src/g_mycanvas.c",
		"src/g_numbox.c",
		"src/g_radio.c",
		"src/g_readwrite.c",
		"src/g_rtext.c",
		"src/g_scalar.c",
		"src/g_slider.c",
		"src/g_template.c",
		"src/g_text.c",
		"src/g_toggle.c",
		"src/g_traversal.c",
		"src/g_undo.c",
		"src/g_vumeter.c",
		"src/m_atom.c",
		"src/m_binbuf.c",
		"src/m_class.c",
		"src/m_conf.c",
		"src/m_glob.c",
		"src/m_memory.c",
		"src/m_obj.c",
		"src/m_pd.c",
		"src/m_sched.c",
		"src/s_audio.c",
		"src/s_inter.c",
		"src/s_inter_gui.c",
		"src/s_loader.c",
		"src/s_main.c",
		"src/s_net.c",
		"src/s_path.c",
		"src/s_print.c",
		"src/s_utf8.c",
		"src/x_acoustics.c",
		"src/x_arithmetic.c",
		"src/x_array.c",
		"src/x_connective.c",
		"src/x_file.c",
		"src/x_gui.c",
		"src/x_interface.c",
		"src/x_list.c",
		"src/x_midi.c",
		"src/x_misc.c",
		"src/x_net.c",
		"src/x_scalar.c",
		"src/x_text.c",
		"src/x_time.c",
		"src/x_vexp.c",
		"src/x_vexp_fun.c",
		"src/x_vexp_if.c",
	};

	const standalone = [_][]const u8{
		"src/s_file.c",
		"src/s_midi.c",
	};

	const alsa = [_][]const u8{
		"src/s_audio_alsa.c",
		"src/s_audio_alsamm.c",
		"src/s_midi_alsa.c",
	};

	const jack = [_][]const u8{
		"src/s_audio_jack.c",
	};

	const oss = [_][]const u8{
		"src/s_audio_oss.c",
		"src/s_midi_oss.c",
	};

	const portaudio = [_][]const u8{
		"src/s_audio_pa.c",
	};

	const dummy = [_][]const u8{
		"src/s_audio_dummy.c",
	};

	const paring = [_][]const u8{
		"src/s_audio_paring.c",
	};

	const watchdog = [_][]const u8{
		"src/s_watchdog.c",
	};

	const send = [_][]const u8{
		"src/u_pdsend.c",
		"src/s_net.c",
	};

	const receive = [_][]const u8{
		"src/u_pdreceive.c",
		"src/s_net.c",
	};
};
