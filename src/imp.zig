const std = @import("std");
const c = @import("cdef");
const m = @import("pd.zig");
const cnv = @import("canvas.zig");

const strlen = @import("std").mem.len;

const Pd = m.Pd;
const GObj = m.GObj;
const GPointer = m.GPointer;
const BinBuf = m.BinBuf;
const NewMethod = m.NewMethod;
const Method = m.Method;
const GotFn = m.GotFn;
const Atom = m.Atom;
const Float = m.Float;
const Symbol = m.Symbol;

pub fn printStruct(T: type, name: [:0]const u8) void {
	const info = @typeInfo(T).@"struct";
	const Field = struct {
		name: []const u8,
		offset: usize,
		type: type,
	};
	const fields: [info.fields.len]Field = comptime blk: {
		var fields: [info.fields.len]Field = undefined;
		for (info.fields, 0..) |field, i| {
			fields[i] = .{
				.name = field.name,
				.offset = @offsetOf(T, field.name),
				.type = field.type,
			};
		}
		for (0..fields.len) |i| {
			for (i + 1..fields.len) |j| {
				if (fields[j].offset < fields[i].offset) {
					const temp = fields[i];
					fields[i] = fields[j];
					fields[j] = temp;
				}
			}
		}
		break :blk fields;
	};
	m.post.do("[%s]: %s", .{ name.ptr, @typeName(T) });
	inline for (fields) |field| {
		m.post.do("    %s: %s -> %u", .{
			field.name.ptr,
			@typeName(field.type),
			@as(c_uint, @intCast(field.offset)),
		});
	}
}


// ----------------------------------- Class -----------------------------------
// -----------------------------------------------------------------------------
pub const MethodEntry = extern struct {
	name: *Symbol,
	fun: *const GotFn,
	arg: [m.max_arg:0]u8,
};

pub const Class = extern struct {
	name: *Symbol,
	helpname: *Symbol,
	externdir: *Symbol,
	size: usize,
	methods: [*]MethodEntry,
	nmethod: c_uint,
	method_free: ?*const Method,
	method_bang: ?*const BangFn,
	method_pointer: ?*const PointerFn,
	method_float: ?*const FloatFn,
	method_symbol: ?*const SymbolFn,
	method_list: ?*const ListFn,
	method_any: ?*const AnyFn,
	wb: ?*const cnv.WidgetBehavior,
	pwb: ?*const cnv.parent.WidgetBehavior,
	fn_save: ?*const SaveFn,
	fn_properties: ?*const PropertiesFn,
	next: ?*Class,
	float_signal_in: c_uint,
	flags: Flags,
	fn_free: ?*const FreeFn,

	pub const BangFn = fn (*Pd) callconv(.c) void;
	pub const PointerFn = fn (*Pd, *GPointer) callconv(.c) void;
	pub const FloatFn = fn (*Pd, Float) callconv(.c) void;
	pub const SymbolFn = fn (*Pd, *Symbol) callconv(.c) void;
	pub const ListFn = fn (*Pd, ?*Symbol, c_uint, [*]Atom) callconv(.c) void;
	pub const AnyFn = fn (*Pd, *Symbol, c_uint, [*]Atom) callconv(.c) void;
	pub const FreeFn = fn (*Class) callconv(.c) void;
	pub const SaveFn = fn (*GObj, *BinBuf) callconv(.c) void;
	pub const PropertiesFn = fn (*GObj, *cnv.GList) callconv(.c) void;

	pub const Flags = packed struct(u8) {
		/// true if is a gobj
		gobj: bool,
		/// true if we have an `Object` header
		patchable: bool,
		/// if so, true if drawing first inlet
		first_in: bool,
		/// drawing command for a template
		draw_command: bool,
		/// can deal with multichannel sigs
		multichannel: bool,
		/// don't promote scalars to signals
		no_promote_sig: bool,
		/// don't promote the main (left) inlet to signals
		no_promote_left: bool,
		_unused: u1,
	};

	pub const Options = struct {
		/// non-canvasable pd such as an inlet
		bare: bool = false,
		/// pd that can belong to a canvas
		gobj: bool = false,
		/// pd that also can have inlets and outlets
		patchable: bool = false,

		/// suppress left inlet
		no_inlet: bool = false,
		/// can deal with multichannel signals
		multichannel: bool = false,
		/// don't promote scalars to signals
		no_promote_sig: bool = false,
		/// don't promote the main (left) inlet to signals
		no_promote_left: bool = false,

		fn toInt(self: Options) c_int {
			return @intFromBool(self.bare)
				| (@as(u2, @intFromBool(self.gobj)) << 1)
				| (@as(u2, @intFromBool(self.patchable)) * 3)
				| (@as(u4, @intFromBool(self.no_inlet)) << 3)
				| (@as(u5, @intFromBool(self.multichannel)) << 4)
				| (@as(u6, @intFromBool(self.no_promote_sig)) << 5)
				| (@as(u7, @intFromBool(self.no_promote_left)) << 6);
		}
	};

	pub const pd = m.Pd.init;
	pub const gui = m.iem.Gui.init;

	pub fn deinit(self: *Class) void {
		c.class_free(@ptrCast(self));
	}

	pub fn addBang(self: *Class, func: *const Method) void {
		c.class_addbang(@ptrCast(self), func);
	}

	pub fn addPointer(self: *Class, func: *const Method) void {
		c.class_addpointer(@ptrCast(self), func);
	}

	pub fn addFloat(self: *Class, func: *const Method) void {
		c.class_doaddfloat(@ptrCast(self), func);
	}

	pub fn addSymbol(self: *Class, func: *const Method) void {
		c.class_addsymbol(@ptrCast(self), func);
	}

	pub fn addList(self: *Class, func: *const Method) void {
		c.class_addlist(@ptrCast(self), func);
	}

	pub fn addAnything(self: *Class, func: *const Method) void {
		c.class_addanything(@ptrCast(self), func);
	}

	pub fn setHelpSymbol(self: *Class, sym: *Symbol) void {
		c.class_sethelpsymbol(@ptrCast(self), @ptrCast(sym));
	}

	pub fn setWidget(self: *Class, wb: *const cnv.WidgetBehavior) void {
		c.class_setwidget(@ptrCast(self), @ptrCast(wb));
	}

	pub fn setParentWidget(self: *Class, pwb: *const cnv.parent.WidgetBehavior) void {
		c.class_setparentwidget(@ptrCast(self), @ptrCast(pwb));
	}

	pub fn getName(self: *const Class) [*:0]const u8 {
		return c.class_getname(@ptrCast(self));
	}

	pub fn getHelpName(self: *const Class) [*:0]const u8 {
		return c.class_gethelpname(@ptrCast(self));
	}

	pub fn getHelpDir(self: *const Class) [*:0]const u8 {
		return c.class_gethelpdir(@ptrCast(self));
	}

	pub fn setDrawCommand(self: *Class) void {
		c.class_setdrawcommand(@ptrCast(self));
	}

	pub fn doMainSignalIn(self: *Class, onset: usize) void {
		c.class_domainsignalin(@ptrCast(self), @intCast(onset));
	}

	pub fn setSaveFn(self: *Class, savefn: ?*const SaveFn) void {
		c.class_setsavefn(@ptrCast(self), @ptrCast(savefn));
	}

	pub fn getSaveFn(self: *const Class) ?*const SaveFn {
		return @ptrCast(c.class_getsavefn(@ptrCast(self)));
	}

	/// Set a function to start the properties dialog
	pub fn setPropertiesFn(self: *Class, propfn: ?*const PropertiesFn) void {
		c.class_setpropertiesfn(@ptrCast(self), @ptrCast(propfn));
	}

	pub fn getPropertiesFn(self: *const Class) ?*const PropertiesFn {
		return @ptrCast(c.class_getpropertiesfn(@ptrCast(self)));
	}

	pub fn setFreeFn(self: *Class, freefn: ?*const FreeFn) void {
		c.class_setfreefn(@ptrCast(self), @ptrCast(freefn));
	}

	pub fn isDrawCommand(self: *const Class) bool {
		return (c.class_isdrawcommand(@ptrCast(self)) != 0);
	}

	pub fn find(self: *const Class, sym: *Symbol) ?*Pd {
		return @ptrCast(c.pd_findbyclass(@ptrCast(sym), @ptrCast(self)));
	}

	pub fn addMethod(
		self: *Class,
		meth: *const Method,
		sym: *Symbol,
		comptime args: []const Atom.Type,
	) void {
		const cls: *c.struct__class = @ptrCast(self);
		const sm: *c.t_symbol = @ptrCast(sym);
		@call(.auto, c.pd_class_addmethod, .{ cls, meth, sm } ++ Atom.Type.tuple(args));
	}

	pub fn init(
		T: type,
		name: [:0]const u8,
		comptime args: []const Atom.Type,
		new_method: ?*const m.NewFn(T, args),
		free_method: ?*const fn(*T) callconv(.c) void,
		options: Options,
	) error{ClassInit}!*Class {
		// printStruct(T, name); // uncomment this to view struct field order
		const sym: *c.t_symbol = c.gensym(name.ptr);
		const newm: ?*const NewMethod = @ptrCast(new_method);
		const freem: ?*const Method = @ptrCast(free_method);
		return if (@call(.auto, c.pd_class_new,
			.{ sym, newm, freem, @sizeOf(T), options.toInt() } ++ Atom.Type.tuple(args)
		)) |cls| @ptrCast(@alignCast(cls)) else error.ClassInit;
	}

	pub fn getFirst() error{SingleInstanceMode}!*Class {
		return if (m.opt.multi) class_getfirst() else error.SingleInstanceMode;
	}
	extern fn class_getfirst() *Class;
};
