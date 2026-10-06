const std = @import("std");

pub fn main(init: std.process.Init) !void {
	const io = init.io;
	const gpa = init.gpa;
	const args = try init.minimal.args.toSlice(init.arena.allocator());
	if (args.len < 3) {
		return error.MissingArguments;
	}
	const dest = args[1];
	const src = args[2];
	const target = try std.Io.Dir.path.relativeAlloc(gpa, ".", null, dest, src);
	defer gpa.free(target);
	// std.debug.print("{s} -> {s}\n", .{ dest, target });

	// dest folder must already exist before attempting to put symlinks in it
	var dir: std.Io.Dir = blk: {
		const cwd: std.Io.Dir = .cwd();
		cwd.access(io, dest, .{}) catch cwd.createDirPath(io, dest) catch {};
		break :blk try cwd.openDir(io, dest, .{});
	};
	defer dir.close(io);
	dir.symLink(io, target, std.fs.path.basename(src), .{})
		catch |e| if (e != error.PathAlreadyExists) return e;
}
