const pd = @import("pd");

const Sesom = extern struct {
	const name = "sesom";
	var class: *pd.Class = undefined;

	obj: pd.Object,
	out: [2]*pd.Outlet,
	f: pd.Float,

	fn floatC(self: *Sesom, f: pd.Float) callconv(.c) void {
		self.out[if (f > self.f) 0 else 1].float(f);
	}

	inline fn init(f: pd.Float) !*Sesom {
		const self: *Sesom = @ptrCast(try class.pd());
		const obj: *pd.Object = &self.obj;
		errdefer obj.g.pd.deinit();

		self.out[0] = try obj.outlet(&pd.s_float);
		self.out[1] = try obj.outlet(&pd.s_float);
		_ = try obj.inletFloat(&self.f);

		self.f = f;
		return self;
	}

	fn initC(f: pd.Float) callconv(.c) ?*Sesom {
		return init(f) catch |e| {
			pd.post.err(null, name ++ ": {s}", .{ @errorName(e) });
			return null;
		};
	}

	inline fn setup() !void {
		class = try .init(Sesom, name, &.{ .deffloat }, &initC, null, .{});
		class.addFloat(@ptrCast(&floatC));
	}
};

export fn sesom_setup() void {
	Sesom.setup() catch |e|
		pd.post.err(null, "{s}: {s}", .{ @src().fn_name, @errorName(e) });
}
