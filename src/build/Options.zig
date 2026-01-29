const Options = @This();

const std = @import("std");
const LinkMode = std.builtin.LinkMode;

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

pub fn init(
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
