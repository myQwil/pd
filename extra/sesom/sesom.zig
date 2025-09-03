const pd = @import("pd");

const Float = pd.Float;

const Sesom = extern struct {
	obj: pd.Object,
	out_l: *pd.Outlet,
	out_r: *pd.Outlet,
	f: Float,

	const name = "sesom";
	var class: *pd.Class = undefined;

	fn floatC(self: *Sesom, f: Float) callconv(.c) void {
		(if (f > self.f) self.out_l else self.out_r).float(f);
	}

	inline fn init(f: Float) !*Sesom {
		const self: *Sesom = @ptrCast(try class.pd());
		const obj: *pd.Object = &self.obj;
		errdefer obj.g.pd.deinit();

		self.out_l = try obj.outlet(&pd.s_float);
		self.out_r = try obj.outlet(&pd.s_float);
		_ = try obj.inletFloat(&self.f);

		self.f = f;
		return self;
	}

	fn initC(f: Float) callconv(.c) ?*Sesom {
		return init(f) catch |e| blk: {
			pd.post.err(null, name ++ ": %s", .{ @errorName(e).ptr });
			break :blk null;
		};
	}

	inline fn setup() !void {
		class = try .init(Sesom, name, &.{ .deffloat }, &initC, null, .{});
		class.addFloat(@ptrCast(&floatC));
	}
};

export fn sesom_setup() void {
	Sesom.setup() catch |e|
		pd.post.err(null, "%s: %s", .{ @src().fn_name.ptr, @errorName(e).ptr });
}
