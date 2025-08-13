// based on: https://github.com/allyourcodebase/portaudio/blob/main/build.zig

const std = @import("std");
const LinkMode = std.builtin.LinkMode;
const StringList = std.ArrayList([]const u8);

pub const HostApi = enum {
	alsa,
	asihpi,
	asio,
	coreaudio,
	dsound,
	jack,
	oss,
	pulseaudio,
	wasapi,
	wdmks,
	wmme,

	pub const defaults = struct {
		pub const macos: []const HostApi = &.{.coreaudio};
		pub const linux: []const HostApi = &.{ .alsa, .pulseaudio };
		pub const windows: []const HostApi = &.{.wasapi};
	};
};

fn unsupportedOs(os: std.Target.Os.Tag) noreturn {
	std.log.err("unsupported OS: {s}", .{@tagName(os)});
	std.process.exit(1);
}

fn unsupportedHostApi(os: std.Target.Os.Tag, api: HostApi) noreturn {
	std.log.err("host API {s} is unsupported on {s}", .{ @tagName(api), @tagName(os) });
	std.process.exit(1);
}

pub fn library(
	b: *std.Build,
	target: std.Build.ResolvedTarget,
	optimize: std.builtin.OptimizeMode,
) !*std.Build.Step.Compile {
	const upstream = b.dependency("portaudio", .{});
	const os = target.result.os.tag;

	const host_apis = b.option([]const HostApi, "host-api",
		"Enable specific host audio APIs"
	) orelse switch (os) {
		.macos => HostApi.defaults.macos,
		.linux => HostApi.defaults.linux,
		.windows => HostApi.defaults.windows,
		else => unsupportedOs(os),
	};

	const mod = b.createModule(.{
		.target = target,
		.optimize = optimize,
		.link_libc = true,
	});
	mod.addIncludePath(upstream.path("include"));
	mod.addIncludePath(upstream.path("src/common"));

	var files: StringList = .init(b.allocator);
	defer files.deinit();
	try files.appendSlice(&src.common);

	switch (os) {
		.macos => {
			for (host_apis) |api| {
				switch (api) {
					.coreaudio => {
						try files.appendSlice(&src.hostapi_coreaudio);
						mod.addCMacro("PA_USE_COREAUDIO", "1");
						mod.addIncludePath(upstream.path("src/hostapi/coreaudio"));
						mod.linkFramework("AudioToolbox", .{});
						mod.linkFramework("AudioUnit", .{});
						mod.linkFramework("CoreAudio", .{});
						mod.linkFramework("CoreServices", .{});
					},
					else => unsupportedHostApi(os, api),
				}
			}
			try files.appendSlice(&src.os_unix);
			mod.addIncludePath(upstream.path("src/os/unix"));
		},
		.linux => {
			for (host_apis) |api| {
				switch (api) {
					.alsa => {
						try files.appendSlice(&src.hostapi_alsa);
						mod.addCMacro("PA_USE_ALSA", "1");
						mod.addIncludePath(upstream.path("src/hostapi/alsa"));
						mod.linkSystemLibrary("asound", .{});
					},
					.asihpi => {
						try files.appendSlice(&src.hostapi_asihpi);
						mod.addCMacro("PA_USE_ASIHPI", "1");
						mod.addIncludePath(upstream.path("src/hostapi/asihpi"));
						mod.linkSystemLibrary("asihpi", .{});
					},
					.jack => {
						try files.appendSlice(&src.hostapi_jack);
						mod.addCMacro("PA_USE_JACK", "1");
						mod.addIncludePath(upstream.path("src/hostapi/jack"));
						mod.linkSystemLibrary("jack", .{});
					},
					.oss => {
						try files.appendSlice(&src.hostapi_oss);
						mod.addCMacro("PA_USE_OSS", "1");
						mod.addIncludePath(upstream.path("src/hostapi/oss"));
					},
					.pulseaudio => {
						try files.appendSlice(&src.hostapi_pulseaudio);
						mod.addCMacro("PA_USE_PULSEAUDIO", "1");
						mod.addIncludePath(upstream.path("src/hostapi/pulseaudio"));
						mod.linkSystemLibrary("pulse", .{});
					},
					else => unsupportedHostApi(os, api),
				}
			}
			try files.appendSlice(&src.os_unix);
			mod.addIncludePath(upstream.path("src/os/unix"));
		},
		.windows => {
			for (host_apis) |api| {
				switch (api) {
					.asio => {
						// mod.addIncludePath(upstream.path("src/hostapi/asio"));
						// mod.addCMacro("PA_USE_ASIO", "1");
						// try files.appendSlice(&src.hostapi_asio);
						// mod.link_libcpp = true;
						std.log.err("TODO: ASIO on Windows", .{});
						std.process.exit(1);
					},
					.dsound => {
						try files.appendSlice(&src.hostapi_dsound);
						mod.addCMacro("PA_USE_DS", "1");
						mod.addIncludePath(upstream.path("src/hostapi/dsound"));
					},
					.wasapi => {
						try files.appendSlice(&src.hostapi_wasapi);
						mod.addCMacro("PA_USE_WASAPI", "1");
						mod.addIncludePath(upstream.path("src/hostapi/wasapi"));
					},
					.wdmks => {
						try files.appendSlice(&src.hostapi_wdmks);
						mod.addCMacro("PA_USE_WDMKS", "1");
						mod.addIncludePath(upstream.path("src/hostapi/wdmks"));
					},
					.wmme => {
						try files.appendSlice(&src.hostapi_wmme);
						mod.addCMacro("PA_USE_WMME", "1");
						mod.addIncludePath(upstream.path("src/hostapi/wmme"));
					},
					else => unsupportedHostApi(os, api),
				}
			}
			try files.appendSlice(&src.os_win);
			mod.addIncludePath(upstream.path("src/os/win"));
			mod.linkSystemLibrary("winmm", .{});
			mod.linkSystemLibrary("ole32", .{});
		},
		else => unsupportedOs(os),
	}
	mod.addCSourceFiles(.{
		.root = upstream.path("."),
		.files = files.items,
	});

	const lib = b.addLibrary(.{
		.name = "portaudio",
		.linkage = .static,
		.root_module = mod,
	});
	lib.installHeadersDirectory(upstream.path("include"), "", .{});
	return lib;
}

const src = struct {
	const common = [_][]const u8{
		"src/common/pa_allocation.c",
		"src/common/pa_converters.c",
		"src/common/pa_cpuload.c",
		"src/common/pa_debugprint.c",
		"src/common/pa_dither.c",
		"src/common/pa_front.c",
		"src/common/pa_process.c",
		"src/common/pa_ringbuffer.c",
		"src/common/pa_stream.c",
		"src/common/pa_trace.c",
	};

	const os_unix = [_][]const u8{
		"src/os/unix/pa_pthread_util.c",
		"src/os/unix/pa_unix_hostapis.c",
		"src/os/unix/pa_unix_util.c",
	};

	const os_win = [_][]const u8{
		"src/os/win/pa_win_coinitialize.c",
		"src/os/win/pa_win_hostapis.c",
		"src/os/win/pa_win_util.c",
		"src/os/win/pa_win_version.c",
		"src/os/win/pa_win_waveformat.c",
		"src/os/win/pa_win_wdmks_utils.c",
		"src/os/win/pa_x86_plain_converters.c",
	};

	const hostapi_alsa = [_][]const u8{
		"src/hostapi/alsa/pa_linux_alsa.c",
	};

	const hostapi_asihpi = [_][]const u8{
		"src/hostapi/asihpi/pa_linux_asihpi.c",
	};

	// const hostapi_asio = [_][]const u8{
	//     "src/hostapi/asio/iasiothiscallresolver.cpp",
	//     "src/hostapi/asio/pa_asio.cpp",
	// };

	const hostapi_coreaudio = [_][]const u8{
		"src/hostapi/coreaudio/pa_mac_core.c",
		"src/hostapi/coreaudio/pa_mac_core_blocking.c",
		"src/hostapi/coreaudio/pa_mac_core_utilities.c",
	};

	const hostapi_dsound = [_][]const u8{
		"src/hostapi/dsound/pa_win_ds.c",
		"src/hostapi/dsound/pa_win_ds_dynlink.c",
	};

	const hostapi_jack = [_][]const u8{
		"src/hostapi/jack/pa_jack.c",
	};

	const hostapi_oss = [_][]const u8{
		"src/hostapi/oss/pa_unix_oss.c",
	};

	const hostapi_pulseaudio = [_][]const u8{
		"src/hostapi/pulseaudio/pa_linux_pulseaudio.c",
		"src/hostapi/pulseaudio/pa_linux_pulseaudio_block.c",
		"src/hostapi/pulseaudio/pa_linux_pulseaudio_cb.c",
	};

	const hostapi_wasapi = [_][]const u8{
		"src/hostapi/wasapi/pa_win_wasapi.c",
	};

	const hostapi_wdmks = [_][]const u8{
		"src/hostapi/wdmks/pa_win_wdmks.c",
	};

	const hostapi_wmme = [_][]const u8{
		"src/hostapi/wmme/pa_win_wmme.c",
	};
};
