const std = @import("std");
const src = @import("sources.zig");

const Build = std.Build;
const Compile = std.Build.Step.Compile;
const StringList = std.ArrayList([]const u8);

const LibraryOptions = struct {
	opt: @import("Options.zig"),
	dep: *Build.Dependency,
	target: Build.ResolvedTarget,
	optimize: std.builtin.OptimizeMode,
};

pub fn addLibrary(b: *Build, options: LibraryOptions) !*Compile {
	const os = options.target.result.os.tag;
	const opt = options.opt;
	const mem = b.allocator;

	var flags: StringList = .{};
	defer flags.deinit(mem);
	try flags.append(mem, "-fno-sanitize=undefined");
	if (options.optimize != .Debug) {
		try flags.appendSlice(mem, &.{
			"-ffast-math",
			"-funroll-loops",
			"-fomit-frame-pointer",
			"-Wno-error=date-time",
		});
	}

	var files: StringList = .{};
	defer files.deinit(mem);
	try files.appendSlice(mem, &src.core);
	try files.appendSlice(mem, if (opt.fftw) &src.fftw else &src.fftsg);
	try files.appendSlice(mem, &src.lib);
	try files.appendSlice(mem, &src.dummy);

	const mod = b.createModule(.{
		.target = options.target,
		.optimize = options.optimize,
		.link_libc = true,
	});
	mod.addIncludePath(options.dep.path("src"));
	mod.addCMacro("PD", "1");
	mod.addCMacro("USEAPI_DUMMY", "1");
	mod.addCMacro("PD_INTERNAL", "1");
	mod.addCMacro("HAVE_UNISTD_H", "1");
	mod.addCMacro("PD_FLOATSIZE", b.fmt("{}", .{ opt.float_size }));

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
			mod.addCMacro("HAVE_LIBDL", "1");
			mod.addCMacro("HAVE_MACHINE_ENDIAN_H", "1");

			// helps for machine/endian.h to be found
			mod.addCMacro("_DARWIN_C_SOURCE", "1");

			// increase max allowed file descriptors
			mod.addCMacro("_DARWIN_UNLIMITED_SELECT", "1");
			mod.addCMacro("FD_SETSIZE", "10240");

			mod.linkSystemLibrary("dl", .{});
		},
		.linux, .freebsd => {
			mod.addCMacro("HAVE_ENDIAN_H", "1");
			try flags.appendSlice(mem, &.{
				"-Wno-int-to-pointer-cast",
				"-Wno-pointer-to-int-cast",
			});
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

	if (os != .emscripten and os != .wasi and opt.lib.linkage == .dynamic) {
		mod.linkSystemLibrary("pthread", .{});
		mod.linkSystemLibrary("m", .{});
	}

	if (opt.lib.extra) {
		try files.appendSlice(mem, &src.extra);
		mod.addCMacro("LIBPD_EXTRA", "1");
	}
	if (opt.lib.utils) {
		try files.appendSlice(mem, &src.util);
	}

	if (opt.lib.multi) {
		mod.addCMacro("PDINSTANCE", "1");
		mod.addCMacro("PDTHREADS", "1");
	}
	if (!opt.lib.setlocale) {
		mod.addCMacro("LIBPD_NO_NUMERIC", "1");
	}

	mod.addCSourceFiles(.{
		.root = options.dep.path("."),
		.files = files.items,
		.flags = flags.items,
	});

	return b.addLibrary(.{
		.name = "pd",
		.linkage = opt.lib.linkage,
		.root_module = mod,
	});
}
