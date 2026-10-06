const std = @import("std");

pub fn main(init: std.process.Init) !void {
	const io = init.io;
	const args = try init.minimal.args.toSlice(init.arena.allocator());
	if (args.len < 2) {
		return error.MissingArguments;
	}
	const prefix = args[1];

	var stdout_buffer: [1024]u8 = undefined;
	var stdout_file_writer: std.Io.File.Writer = .init(.stdout(), io, &stdout_buffer);
	const w = &stdout_file_writer.interface;
	try w.print(
		\\#!/bin/sh
		\\#
		\\# script to launch the Pure Data gui
		\\
		\\# this will be replaced with a full path during `make`
		\\prefix={s}
		\\exec_prefix=${{prefix}}
		\\PD_PREFIX=${{exec_prefix}}/lib/pd
		\\
		\\# for convenience, a symlink is created from this (unexpanded) file
		\\# to ${{builddir}}/bin/pd-gui
		\\# when called as such, we want to launch the local (non-installed) pd-gui.tcl
		\\if [ "x${{PD_PREFIX#@}}" != "x${{PD_PREFIX}}" ]; then
		\\# the PD_PREFIX starts with '@', so it hasn't been replaced...
		\\ PD_PREFIX=${{0%/*}}/..
		\\fi
		\\
		\\exec ${{PD_PREFIX}}/tcl/pd-gui.tcl "$@"
		\\
	, .{ prefix });
	try w.flush();
}
