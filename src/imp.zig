const std = @import("std");
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
		/// true if we have a t_object header
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

		fn toInt(self: Options) c_uint {
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

	pub const deinit = class_free;
	extern fn class_free(*Class) void;

	pub const addBang = class_addbang;
	extern fn class_addbang(*Class, *const Method) void;

	pub const addPointer = class_addpointer;
	extern fn class_addpointer(*Class, *const Method) void;

	pub const addFloat = class_doaddfloat;
	extern fn class_doaddfloat(*Class, *const Method) void;

	pub const addSymbol = class_addsymbol;
	extern fn class_addsymbol(*Class, *const Method) void;

	pub const addList = class_addlist;
	extern fn class_addlist(*Class, *const Method) void;

	pub const addAnything = class_addanything;
	extern fn class_addanything(*Class, *const Method) void;

	pub const setHelpSymbol = class_sethelpsymbol;
	extern fn class_sethelpsymbol(*Class, *Symbol) void;

	pub const setWidget = class_setwidget;
	extern fn class_setwidget(*Class, *const cnv.WidgetBehavior) void;

	pub const setParentWidget = class_setparentwidget;
	extern fn class_setparentwidget(*Class, *const cnv.parent.WidgetBehavior) void;

	pub const getName = class_getname;
	extern fn class_getname(*const Class) [*:0]const u8;

	pub const getHelpName = class_gethelpname;
	extern fn class_gethelpname(*const Class) [*:0]const u8;

	pub const getHelpDir = class_gethelpdir;
	extern fn class_gethelpdir(*const Class) [*:0]const u8;

	pub const setDrawCommand = class_setdrawcommand;
	extern fn class_setdrawcommand(*Class) void;

	pub const doMainSignalIn = class_domainsignalin;
	extern fn class_domainsignalin(*Class, onset: c_uint) void;

	pub const setSaveFn = class_setsavefn;
	extern fn class_setsavefn(*Class, ?*const SaveFn) void;

	pub const saveFn = class_getsavefn;
	extern fn class_getsavefn(*const Class) ?*const SaveFn;

	pub const setPropertiesFn = class_setpropertiesfn;
	extern fn class_setpropertiesfn(*Class, ?*const PropertiesFn) void;

	pub const propertiesFn = class_getpropertiesfn;
	extern fn class_getpropertiesfn(*const Class) ?*const PropertiesFn;

	pub const setFreeFn = class_setfreefn;
	extern fn class_setfreefn(*Class, ?*const FreeFn) void;

	pub fn isDrawCommand(self: *const Class) bool {
		return (class_isdrawcommand(self) != 0);
	}
	extern fn class_isdrawcommand(*const Class) c_uint;

	pub fn find(self: *const Class, sym: *Symbol) ?*Pd {
		return pd_findbyclass(sym, self);
	}
	extern fn pd_findbyclass(*Symbol, *const Class) ?*Pd;

	pub fn addMethod(
		self: *Class,
		meth: *const Method,
		sym: *Symbol,
		comptime args: []const Atom.Type,
	) void {
		@call(.auto, pd_class_addmethod, .{ self, meth, sym } ++ Atom.Type.tuple(args));
	}
	extern fn pd_class_addmethod(*Class, *const Method, *Symbol, c_uint, ...) void;

	pub fn init(
		T: type,
		name: [:0]const u8,
		comptime args: []const Atom.Type,
		new_method: ?*const m.NewFn(T, args),
		free_method: ?*const fn(*T) callconv(.c) void,
		options: Options,
	) error{ClassInit}!*Class {
		// printStruct(T, name); // uncomment this to view struct field order
		const sym: *Symbol = .gen(name.ptr);
		const newm: ?*const NewMethod = @ptrCast(new_method);
		const freem: ?*const Method = @ptrCast(free_method);
		return @call(.auto, pd_class_new,
			.{ sym, newm, freem, @sizeOf(T), options.toInt() } ++ Atom.Type.tuple(args)
		) orelse error.ClassInit;
	}
	extern fn pd_class_new(
		*Symbol, ?*const NewMethod, ?*const Method, usize, c_uint, c_uint, ...,
	) ?*Class;
};
