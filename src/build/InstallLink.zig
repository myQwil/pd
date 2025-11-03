const std = @import("std");
const Build = std.Build;
const Step = Build.Step;
const LazyPath = Build.LazyPath;
const InstallDir = Build.InstallDir;
const InstallLink = @This();
const assert = std.debug.assert;

step: Step,
source: LazyPath,
dir: InstallDir,
dest_rel_path: []const u8,

pub fn create(
	owner: *Build,
	source: LazyPath,
	dir: InstallDir,
	dest_rel_path: []const u8,
) *InstallLink {
	assert(dest_rel_path.len != 0);
	const link = owner.allocator.create(InstallLink) catch @panic("OOM");
	link.* = .{
		.step = .init(.{
			.id = .custom,
			.name = owner.fmt("install symlink of {s} to {s}", .{
				source.getDisplayName(),
				dest_rel_path,
			}),
			.owner = owner,
			.makeFn = make,
		}),
		.source = source.dupe(owner),
		.dir = dir.dupe(owner),
		.dest_rel_path = owner.dupePath(dest_rel_path),
	};
	source.addStepDependencies(&link.step);
	return link;
}

fn make(step: *Step, _: Step.MakeOptions) !void {
	const b = step.owner;
	const link: *InstallLink = @fieldParentPtr("step", step);

	const dest = b.getInstallPath(link.dir, link.dest_rel_path);
	const head = std.fs.path.dirname(dest).?;

	// dest folder must already exist before attempting to put symlinks in it
	var dir: std.fs.Dir = blk: { if (std.fs.path.isAbsolute(head)) {
		var root = try std.fs.openDirAbsolute("/", .{});
		defer root.close();
		root.access(head[1..], .{}) catch root.makePath(head[1..]) catch {};
		break :blk try std.fs.openDirAbsolute(head, .{});
	} else {
		const cwd = std.fs.cwd();
		cwd.access(head, .{}) catch cwd.makePath(head) catch {};
		break :blk try cwd.openDir(head, .{});
	}};
	defer dir.close();

	const target_path = blk: {
		const p = link.source.getPath3(b, step);
		const full_src_path = b.pathResolve(&.{ p.root_dir.path orelse ".", p.sub_path });
		if (std.fs.path.relative(b.allocator, head, full_src_path)) |rel| {
			b.allocator.free(full_src_path);
			break :blk rel;
		} else |_| {
			break :blk full_src_path;
		}
	};
	defer b.allocator.free(target_path);

	dir.symLink(target_path, dest[head.len+1..], .{}) catch |err| switch (err) {
		error.PathAlreadyExists => {},
		else => return step.fail("unable to install symlink '{s}' -> '{s}': {s}",
			.{ link.dest_rel_path, target_path, @errorName(err) }),
	};
}

pub fn addWithDir(
	b: *Build,
	source: LazyPath,
	install_dir: InstallDir,
	dest_rel_path: []const u8,
) *InstallLink {
	return create(b, source, install_dir, dest_rel_path);
}

pub fn add(b: *Build, source: LazyPath, dest_rel_path: []const u8) *InstallLink {
	return create(b, source, .prefix, dest_rel_path);
}

pub fn install(b: *Build, src_path: []const u8, dest_rel_path: []const u8) void {
	b.getInstallStep().dependOn(&add(b, b.path(src_path), dest_rel_path).step);
}
