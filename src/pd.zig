const std = @import("std");
const opt = @import("options");
pub const imp = @import("imp.zig");
pub const cnv = @import("canvas.zig");
pub const iem = @import("all_guis.zig");
pub const stf = @import("stuff.zig");

pub extern const pd_compatibilitylevel: c_int;

pub const Float = std.meta.Float(opt.float_size);
pub const Sample = Float;

pub const Method = fn () callconv(.c) void;
pub const NewMethod = fn () callconv(.c) ?*anyopaque;

pub const Class = imp.Class;
pub const GList = cnv.GList;
pub const Array = cnv.Array;
pub const Gui = iem.Gui;

pub const Word = extern union {
	// we're going to trust pd to give us valid pointers of the respective types
	float: Float,
	symbol: *Symbol,
	gpointer: *GPointer,
	array: *Array,
	binbuf: *BinBuf,
	index: c_int,
};


// ----------------------------------- Atom ------------------------------------
// -----------------------------------------------------------------------------
pub const Atom = extern struct {
	type: Type,
	w: Word,

	pub const Type = enum(c_uint) {
		none,
		float,
		symbol,
		pointer,
		semi,
		comma,
		deffloat,
		defsymbol,
		dollar,
		dollsym,
		gimme,
		cant,

		const Tuple = std.meta.Tuple;
		pub fn tuple(
			comptime args: []const Type,
		) Tuple(&[_]type {c_uint} ** (args.len + 1)) {
			var arr: Tuple(&[_]type {c_uint} ** (args.len + 1)) = undefined;
			inline for (0..args.len) |i| {
				arr[i] = @intFromEnum(args[i]);
			}
			arr[args.len] = @intFromEnum(Type.none);
			return arr;
		}
	};

	pub inline fn getFloat(self: *const Atom) ?Float {
		return if (self.type == .float) self.w.float else null;
	}

	pub inline fn getSymbol(self: *const Atom) ?*Symbol {
		return if (self.type == .symbol) self.w.symbol else null;
	}

	pub const toSymbol = atom_gensym;
	extern fn atom_gensym(*const Atom) *Symbol;

	pub fn bufPrint(self: *const Atom, buf: []u8) void {
		atom_string(self, buf.ptr, @intCast(buf.len));
	}
	extern fn atom_string(*const Atom, [*]u8, c_uint) void;

	pub inline fn float(f: Float) Atom {
		return .{ .type = .float, .w = .{ .float = f } };
	}

	pub inline fn symbol(s: *Symbol) Atom {
		return .{ .type = .symbol, .w = .{ .symbol = s } };
	}

	pub inline fn pointer(p: *GPointer) Atom {
		return .{ .type = .pointer, .w = .{ .gpointer = p } };
	}
};

pub const ArgError = error {
	WrongAtomType,
	IndexOutOfBounds,
};

pub inline fn floatArg(idx: usize, av: []const Atom) ArgError!Float {
	return if (av.len > idx)
		av[idx].getFloat() orelse ArgError.WrongAtomType
	else
		ArgError.IndexOutOfBounds;
}

pub inline fn symbolArg(idx: usize, av: []const Atom) ArgError!*Symbol {
	return if (av.len > idx)
		av[idx].getSymbol() orelse ArgError.WrongAtomType
	else
		ArgError.IndexOutOfBounds;
}

fn typesFromAtoms(comptime args: []const Atom.Type) [args.len]type {
	var types: [args.len]type = undefined;
	for (args, 0..) |a, i| {
		types[i] = switch (a) {
			.symbol, .defsymbol => *Symbol,
			else => Float,
		};
	}
	return types;
}

const Fn = std.builtin.Type.Fn;

fn paramsFromTypes(comptime types: []const type) [types.len]Fn.Param {
	var params: [types.len]Fn.Param = undefined;
	for (types, 0..) |t, i| {
		params[i] = .{
			.is_generic = false,
			.is_noalias = false,
			.type = t,
		};
	}
	return params;
}

pub fn NewFn(T: type, comptime args: []const Atom.Type) type {
	return @Type(.{ .@"fn" = Fn{
		.calling_convention = .c,
		.is_generic = false,
		.is_var_args = false,
		.return_type = ?*T,
		.params = if (args.len == 0) &.{} else &paramsFromTypes(
			if (args[0] == .gimme)
				&.{ *Symbol, c_uint, [*]Atom }
			else
				&typesFromAtoms(args)
		),
	}});
}

pub fn addCreator(
	T: type,
	name: [:0]const u8,
	comptime args: []const Atom.Type,
	new_method: ?*const NewFn(T, args),
) void {
	const sym: *Symbol = .gen(name);
	const newm: *const NewMethod = @ptrCast(new_method);
	@call(.auto, class_addcreator, .{ newm, sym } ++ Atom.Type.tuple(args));
}
extern fn class_addcreator(*const NewMethod, *Symbol, c_uint, ...) void;


// ---------------------------------- BinBuf -----------------------------------
// -----------------------------------------------------------------------------
pub const BinBuf = opaque {
	pub const Error = error {
		BinBufDuplicate,
		BinBufFromText,
		BinBufAdd,
		BinBufJoin,
		BinBufAddSemi,
		BinBufRestore,
		BinBufRead,
		BinBufReadViaCanvas,
		BinBufWrite,
		BinBufResize,
		BinBufInit,
		BinBufFromName,
	};

	pub const Options = packed struct(c_uint) {
		skip_shebang: bool = false,
		map_cr: bool = false,
		_unused: @Type(.{.int = .{
			.signedness = .unsigned, .bits = @bitSizeOf(c_uint) - 2,
		}}) = 0,
	};

	pub const deinit = binbuf_free;
	extern fn binbuf_free(*BinBuf) void;

	pub fn duplicate(self: *const BinBuf) Error!*BinBuf {
		return binbuf_duplicate(self) orelse Error.BinBufDuplicate;
	}
	extern fn binbuf_duplicate(*const BinBuf) ?*BinBuf;

	pub const len = binbuf_getnatom;
	extern fn binbuf_getnatom(*const BinBuf) c_uint;

	pub fn vec(self: *BinBuf) []Atom {
		return binbuf_getvec(self)[0..binbuf_getnatom(self)];
	}
	extern fn binbuf_getvec(*const BinBuf) [*]Atom;

	pub fn fromText(self: *BinBuf, txt: []const u8) Error!*void {
		binbuf_text(self, txt.ptr, txt.len);
		if (binbuf_getnatom(self) == 0)
			return Error.BinBufFromText;
	}
	extern fn binbuf_text(*BinBuf, [*]const u8, usize) void;

	/// Convert a binbuf to text. No null termination.
	pub fn text(self: *const BinBuf) []u8 {
		var ptr: [*]u8 = undefined;
		var n: c_uint = undefined;
		binbuf_gettext(self, &ptr, &n);
		return ptr[0..n];
	}
	extern fn binbuf_gettext(*const BinBuf, *[*]u8, *c_uint) void;

	pub const clear = binbuf_clear;
	extern fn binbuf_clear(*BinBuf) void;

	pub fn add(self: *BinBuf, av: []const Atom) Error!void {
		const newsize = binbuf_getnatom(self) + av.len;
		binbuf_add(self, @intCast(av.len), av.ptr);
		if (binbuf_getnatom(self) != newsize)
			return Error.BinBufAdd;
	}
	extern fn binbuf_add(*BinBuf, c_uint, [*]const Atom) void;

	pub fn addV(self: *BinBuf, fmt: [*:0]const u8, args: anytype) void {
		@call(.auto, binbuf_addv, .{ self, fmt } ++ args);
	}
	extern fn binbuf_addv(*BinBuf, fmt: [*:0]const u8, ...) void;

	/// add a binbuf to another one for saving.  Semicolons and commas go to
	/// symbols ";", "'",; and inside symbols, characters ';', ',' and '$' get
	/// escaped.  LATER also figure out about escaping white space
	pub fn join(self: *BinBuf, other: *const BinBuf) Error!void {
		const newsize = binbuf_getnatom(self) + binbuf_getnatom(other);
		binbuf_addbinbuf(self, other);
		if (binbuf_getnatom(self) != newsize)
			return Error.BinBufJoin;
	}
	extern fn binbuf_addbinbuf(*BinBuf, *const BinBuf) void;

	pub fn addSemi(self: *BinBuf) Error!void {
		const newsize = binbuf_getnatom(self) + 1;
		binbuf_addsemi(self);
		if (binbuf_getnatom(self) != newsize)
			return Error.BinBufAddSemi;
	}
	extern fn binbuf_addsemi(*BinBuf) void;

	/// Supply atoms to a binbuf from a message, making the opposite changes
	/// from `join`.  The symbol ";" goes to a semicolon, etc.
	pub fn restore(self: *BinBuf, av: []Atom) Error!void {
		const newsize = binbuf_getnatom(self) + av.len;
		binbuf_restore(self, av.len, av.ptr);
		if (binbuf_getnatom(self) != newsize)
			return Error.BinBufRestore;
	}
	extern fn binbuf_restore(*BinBuf, c_uint, [*]const Atom) void;

	pub const print = binbuf_print;
	extern fn binbuf_print(*const BinBuf) void;

	pub fn eval(self: *const BinBuf, target: *Pd, av: []Atom) void {
		binbuf_eval(self, target, @intCast(av.len), av.ptr);
	}
	extern fn binbuf_eval(*const BinBuf, *Pd, c_uint, [*]const Atom) void;

	pub fn read(
		self: *BinBuf,
		filename: [*:0]const u8,
		dirname: [*:0]const u8,
		crflag: Options,
	) Error!void {
		if (binbuf_read(self, filename, dirname, crflag) != 0)
			return Error.BinBufRead;
	}
	extern fn binbuf_read(*BinBuf, [*:0]const u8, [*:0]const u8, Options) c_int;

	pub fn readViaCanvas(
		self: *BinBuf,
		filename: [*:0]const u8,
		canvas: *const GList,
		crflag: Options,
	) Error!void {
		if (binbuf_read_via_canvas(self, filename, canvas, crflag) != 0)
			return Error.BinBufReadViaCanvas;
	}
	extern fn binbuf_read_via_canvas(*BinBuf, [*:0]const u8, *const GList, Options) c_int;

	pub fn write(
		self: *const BinBuf,
		filename: [*:0]const u8,
		dirname: [*:0]const u8,
		crflag: Options,
	) Error!void {
		if (binbuf_write(self, filename, dirname, crflag) != 0)
			return Error.BinBufWrite;
	}
	extern fn binbuf_write(*const BinBuf, [*:0]const u8, [*:0]const u8, Options) c_int;

	pub fn resize(self: *BinBuf, newsize: c_uint) Error!void {
		if (binbuf_resize(self, newsize) == 0)
			return Error.BinBufResize;
	}
	extern fn binbuf_resize(*BinBuf, c_uint) c_uint;

	pub fn init() Error!*BinBuf {
		return binbuf_new() orelse Error.BinBufInit;
	}
	extern fn binbuf_new() ?*BinBuf;

	/// Public interface to get text buffers by name
	pub fn fromName(sym: *Symbol) Error!*BinBuf {
		return text_getbufbyname(sym) orelse Error.BinBufFromName;
	}
	extern fn text_getbufbyname(*BinBuf) ?*BinBuf;
};

pub const evalFile = binbuf_evalfile;
extern fn binbuf_evalfile(name: *Symbol, dir: *Symbol) void;

pub fn realizeDollSym(
	sym: *Symbol,
	av: []const Atom,
	tonew: bool
) error{RealizeDollSym}!*Symbol {
	return binbuf_realizedollsym(sym, @intCast(av.len), av.ptr, @intFromBool(tonew))
		orelse error.RealizeDollSym;
}
extern fn binbuf_realizedollsym(*Symbol, c_uint, [*]const Atom, c_uint) ?*Symbol;


// ----------------------------------- Clock -----------------------------------
// -----------------------------------------------------------------------------
pub const Clock = opaque {
	pub const Error = error {
		ClockInit,
	};

	pub const deinit = clock_free;
	extern fn clock_free(*Clock) void;

	pub const set = clock_set;
	extern fn clock_set(*Clock, systime: f64) void;

	pub const delay = clock_delay;
	extern fn clock_delay(*Clock, delaytime: f64) void;

	pub const unset = clock_unset;
	extern fn clock_unset(*Clock) void;

	pub fn setUnit(self: *Clock, timeunit: f64, in_samples: bool) void {
		clock_setunit(self, timeunit, @intFromBool(in_samples));
	}
	extern fn clock_setunit(*Clock, f64, c_uint) void;

	pub fn init(owner: *anyopaque, func: *const Method) Error!*Clock {
		return clock_new(owner, func) orelse Error.ClockInit;
	}
	extern fn clock_new(*anyopaque, *const Method) ?*Clock;
};

pub const time = clock_getlogicaltime;
extern fn clock_getlogicaltime() f64;

pub const timeSince = clock_gettimesince;
extern fn clock_gettimesince(prevsystime: f64) f64;

pub const sysTimeAfter = clock_getsystimeafter;
extern fn clock_getsystimeafter(delaytime: f64) f64;

pub fn timeSinceWithUnits(prevsystime: f64, units: f64, in_samples: bool) f64 {
	return clock_gettimesincewithunits(prevsystime, units, @intFromBool(in_samples));
}
extern fn clock_gettimesincewithunits(f64, f64, c_uint) f64;


// ------------------------------------ Dsp ------------------------------------
// -----------------------------------------------------------------------------
pub const dsp = struct {
	pub const PerfRoutine = fn ([*]usize) callconv(.c) [*]usize;

	pub fn add(perf: *const PerfRoutine, args: anytype) void {
		@call(.auto, dsp_add, .{ perf, @as(c_uint, @intCast(args.len)) } ++ args);
	}
	extern fn dsp_add(*const PerfRoutine, c_uint, ...) void;

	pub fn addVec(perf: *const PerfRoutine, vec: []usize) void {
		dsp_addv(perf, @intCast(vec.len), vec.ptr);
	}
	extern fn dsp_addv(*const PerfRoutine, c_uint, [*]usize) void;

	pub const addPlus = dsp_add_plus;
	extern fn dsp_add_plus(
		in1: [*]Sample,
		in2: [*]Sample,
		out: [*]Sample,
		n: c_uint
	) void;

	pub const addCopy = dsp_add_copy;
	extern fn dsp_add_copy(in: [*]Sample, out: [*]Sample, n: c_uint) void;

	pub const addScalarCopy = dsp_add_scalarcopy;
	extern fn dsp_add_scalarcopy(in: [*]Float, out: [*]Sample, n: c_uint) void;

	pub const addZero = dsp_add_zero;
	extern fn dsp_add_zero([*]Sample, c_uint) void;
};


// ---------------------------------- GArray -----------------------------------
// -----------------------------------------------------------------------------
pub extern const garray_class: *Class;
pub extern const scalar_class: *Class;

pub const GArray = opaque {
	pub const Error = error {
		GArrayGetArray,
		GArrayFloatWords,
	};

	pub const redraw = garray_redraw;
	extern fn garray_redraw(*GArray) void;

	pub fn array(self: *GArray) Error!*Array {
		return garray_getarray(self) orelse Error.GArrayGetArray;
	}
	extern fn garray_getarray(*GArray) ?*Array;

	pub fn vec(self: *GArray) ![]u8 {
		const arr = try self.array();
		return arr.vec[0..arr.len];
	}

	pub const resize = garray_resize_long;
	extern fn garray_resize_long(*GArray, c_ulong) void;

	pub const useInDsp = garray_usedindsp;
	extern fn garray_usedindsp(*GArray) void;

	pub fn setSaveInPatch(self: *GArray, saveit: bool) void {
		garray_setsaveit(self, @intFromBool(saveit));
	}
	extern fn garray_setsaveit(*GArray, c_uint) void;

	pub const glist = garray_getglist;
	extern fn garray_getglist(*GArray) *GList;

	pub fn floatWords(self: *GArray) Error![]Word {
		var len: c_uint = undefined;
		var ptr: [*]Word = undefined;
		return if (garray_getfloatwords(self, &len, &ptr) != 0)
			ptr[0..len] else Error.GArrayFloatWords;
	}
	extern fn garray_getfloatwords(*GArray, *c_uint, vec: *[*]Word) c_uint;
};


// --------------------------------- GPointer ----------------------------------
// -----------------------------------------------------------------------------
pub const Scalar = extern struct {
	/// header for graphical object
	gobj: GObj,
	/// template name (LATER replace with pointer)
	template: *Symbol,
	/// indeterminate-length array of words
	vec: [1]Word,
};

pub const GStub = extern struct {
	un: Union,
	which: Type,
	refcount: c_int,

	pub const Union = extern union {
		glist: *GList,
		array: *Array,
	};

	pub const Type = enum(c_uint) {
		none,
		glist,
		array,
	};
};

pub const GPointer = extern struct {
	un: Union,
	valid: c_int,
	stub: *GStub,

	pub const Union = extern union {
		scalar: *Scalar,
		w: *Word,
	};

	pub const init = gpointer_init;
	extern fn gpointer_init(*GPointer) void;

	/// Copy a pointer to another, assuming the second one hasn't yet been
	/// initialized.  New gpointers should be initialized either by this
	/// routine or by gpointer_init below.
	pub const copyTo = gpointer_copy;
	extern fn gpointer_copy(from: *const GPointer, to: *GPointer) void;

	/// Clear a gpointer that was previously set, releasing the associated
	/// gstub if this was the last reference to it.
	pub const unset = gpointer_unset;
	extern fn gpointer_unset(*GPointer) void;

	/// Call this to verify that a pointer is fresh, i.e., that it either
	/// points to real data or to the head of a list, and that in either case
	/// the object hasn't disappeared since this pointer was generated.
	/// Unless "headok" is set,  the routine also fails for the head of a list.
	pub fn isValid(self: *GPointer, headok: bool) bool {
		return (gpointer_check(self, @intFromBool(headok)) != 0);
	}
	extern fn gpointer_check(*const GPointer, headok: c_uint) c_uint;
};


// ----------------------------------- Inlet -----------------------------------
// -----------------------------------------------------------------------------
pub const Inlet = opaque {
	pub const Error = error {
		InletInit,
		InletInitFloat,
		InletInitSymbol,
		InletInitSignal,
		InletInitPointer,
	};

	pub const deinit = inlet_free;
	extern fn inlet_free(*Inlet) void;

	pub fn init(obj: *Object, dest: *Pd, from: ?*Symbol, to: ?*Symbol) Error!*Inlet {
		return inlet_new(obj, dest, from, to) orelse Error.InletInit;
	}
	extern fn inlet_new(*Object, *Pd, ?*Symbol, ?*Symbol) ?*Inlet;

	pub fn initFloat(obj: *Object, fp: *Float) Error!*Inlet {
		return floatinlet_new(obj, fp) orelse Error.InletInitFloat;
	}
	extern fn floatinlet_new(*Object, *Float) ?*Inlet;

	pub fn initSymbol(obj: *Object, sym: **Symbol) Error!*Inlet {
		return symbolinlet_new(obj, sym) orelse Error.InletInitSymbol;
	}
	extern fn symbolinlet_new(*Object, **Symbol) ?*Inlet;

	pub fn initSignal(obj: *Object, f: Float) Error!*Inlet {
		return signalinlet_new(obj, f) orelse Error.InletInitSignal;
	}
	extern fn signalinlet_new(*Object, Float) ?*Inlet;

	pub fn initPointer(obj: *Object, gp: *GPointer) Error!*Inlet {
		return pointerinlet_new(obj, gp) orelse Error.InletInitPointer;
	}
	extern fn pointerinlet_new(*Object, *GPointer) ?*Inlet;
};


// ---------------------------------- Memory -----------------------------------
// -----------------------------------------------------------------------------
const Allocator = std.mem.Allocator;
const Alignment = std.mem.Alignment;

fn alloc(_: *anyopaque, len: usize, _: Alignment, _: usize) ?[*]u8 {
	std.debug.assert(len > 0);
	return @ptrCast(getbytes(len));
}
extern fn getbytes(usize) ?*anyopaque;

fn resize(_: *anyopaque, buf: []u8, _: Alignment, new_len: usize, _: usize) bool {
	return (new_len <= buf.len);
}

fn remap(_: *anyopaque, buf: []u8, _: Alignment, new_len: usize, _: usize) ?[*]u8 {
	return if (new_len <= buf.len) buf.ptr else null;
}

fn free(_: *anyopaque, buf: []u8, _: Alignment, _: usize) void {
	freebytes(buf.ptr, buf.len);
}
extern fn freebytes(*anyopaque, usize) void;

const mem_vtable = Allocator.VTable{
	.alloc = alloc,
	.resize = resize,
	.remap = remap,
	.free = free,
};

pub const mem = Allocator{
	.ptr = undefined,
	.vtable = &mem_vtable,
};


// ---------------------------------- Object -----------------------------------
// -----------------------------------------------------------------------------
pub const GObj = extern struct {
	pd: Pd,
	next: ?*GObj,
};

pub const Object = extern struct {
	/// header for graphical object
	g: GObj,
	/// holder for the text
	binbuf: *BinBuf,
	/// linked list of outlets
	outlets: ?*Outlet,
	/// linked list of inlets
	inlets: ?*Inlet,
	/// x location (within the toplevel)
	xpix: i16,
	/// y location (within the toplevel)
	ypix: i16,
	/// requested width in chars, 0 if auto
	width: i16,
	type: Type,

	const Type = enum(u8) {
		/// just a textual comment
		text = 0,
		/// a MAX style patchable object
		object = 1,
		/// a MAX type message
		message = 2,
		/// a cell to display a number or symbol
		atom = 3,
	};

	pub fn list(self: *Object, sym: *Symbol, av: []Atom) void {
		obj_list(self, sym, av.len, av.ptr);
	}
	extern fn obj_list(*Object, *Symbol, ac: c_uint, av: [*]Atom) void;

	pub const saveFormat = obj_saveformat;
	extern fn obj_saveformat(*const Object, *BinBuf) void;

	pub const xPix = text_xpix;
	extern fn text_xpix(*Object, *GList) c_int;

	pub const yPix = text_ypix;
	extern fn text_ypix(*Object, *GList) c_int;

	pub const outlet = Outlet.init;
	pub const inlet = Inlet.init;
	pub const inletFloat = Inlet.initFloat;
	pub const inletSymbol = Inlet.initSymbol;
	pub const inletSignal = Inlet.initSignal;
	pub const inletPointer = Inlet.initPointer;
};


// ---------------------------------- Outlet -----------------------------------
// -----------------------------------------------------------------------------
pub const Outlet = opaque {
	pub const Error = error {
		OutletInit,
	};

	pub const deinit = outlet_free;
	extern fn outlet_free(*Outlet) void;

	pub const bang = outlet_bang;
	extern fn outlet_bang(*Outlet) void;

	pub const pointer = outlet_pointer;
	extern fn outlet_pointer(*Outlet, *GPointer) void;

	pub const float = outlet_float;
	extern fn outlet_float(*Outlet, Float) void;

	pub const symbol = outlet_symbol;
	extern fn outlet_symbol(*Outlet, *Symbol) void;

	pub fn list(self: *Outlet, sym: ?*Symbol, av: []Atom) void {
		outlet_list(self, sym, @intCast(av.len), av.ptr);
	}
	extern fn outlet_list(*Outlet, ?*Symbol, c_uint, [*]Atom) void;

	pub fn anything(self: *Outlet, sym: *Symbol, av: []Atom) void {
		outlet_anything(self, sym, @intCast(av.len), av.ptr);
	}
	extern fn outlet_anything(*Outlet, *Symbol, c_uint, [*]Atom) void;

	/// Get the outlet's declared symbol
	pub const getSymbol = outlet_getsymbol;
	extern fn outlet_getsymbol(*Outlet) *Symbol;

	pub fn init(obj: *Object, atype: ?*Symbol) Error!*Outlet {
		return outlet_new(obj, atype) orelse Error.OutletInit;
	}
	extern fn outlet_new(*Object, ?*Symbol) ?*Outlet;
};


// ------------------------------------ Pd -------------------------------------
// -----------------------------------------------------------------------------
/// object to send "pd" messages
pub extern const glob_pdobject: *Class;

pub const Pd = extern struct {
	class: *const Class,

	pub const Error = error {
		PdInit,
	};

	pub const deinit = pd_free;
	extern fn pd_free(*Pd) void;

	pub const bind = pd_bind;
	extern fn pd_bind(*Pd, *Symbol) void;

	pub const unbind = pd_unbind;
	extern fn pd_unbind(*Pd, *Symbol) void;

	pub const pushSymbol = pd_pushsym;
	extern fn pd_pushsym(*Pd) void;

	pub const popSymbol = pd_popsym;
	extern fn pd_popsym(*Pd) void;

	pub const bang = pd_bang;
	extern fn pd_bang(*Pd) void;

	pub const pointer = pd_pointer;
	extern fn pd_pointer(*Pd, *GPointer) void;

	pub const float = pd_float;
	extern fn pd_float(*Pd, Float) void;

	pub const symbol = pd_symbol;
	extern fn pd_symbol(*Pd, *Symbol) void;

	pub fn list(self: *Pd, sym: ?*Symbol, av: []Atom) void {
		pd_list(self, sym, @intCast(av.len), av.ptr);
	}
	extern fn pd_list(*Pd, ?*Symbol, c_uint, [*]Atom) void;

	pub fn anything(self: *Pd, sym: *Symbol, av: []Atom) void {
		pd_anything(self, sym, @intCast(av.len), av.ptr);
	}
	extern fn pd_anything(*Pd, *Symbol, c_uint, [*]Atom) void;

	pub fn typedMess(self: *Pd, sym: ?*Symbol, av: []Atom) void {
		pd_typedmess(self, sym, @intCast(av.len), av.ptr);
	}
	extern fn pd_typedmess(*Pd, ?*Symbol, c_uint, [*]Atom) void;

	pub fn forwardMess(self: *Pd, av: []Atom) void {
		pd_forwardmess(self, @intCast(av.len), av.ptr);
	}
	extern fn pd_forwardmess(*Pd, c_uint, [*]Atom) void;

	/// Checks that a pd is indeed a patchable object, and returns
	/// it, correctly typed, or null if the check failed.
	pub const checkObject = pd_checkobject;
	extern fn pd_checkobject(*Pd) ?*Object;

	pub const parentWidget = pd_getparentwidget;
	extern fn pd_getparentwidget(*Pd) ?*const cnv.parent.WidgetBehavior;

	pub fn stub(
		self: *Pd,
		dest: [*:0]const u8,
		key: *anyopaque,
		fmt: [*:0]const u8,
		args: anytype
	) void {
		@call(.auto, pdgui_stub_vnew, .{ self, dest, key, fmt } ++ args);
	}
	extern fn pdgui_stub_vnew(*Pd, [*:0]const u8, *anyopaque, [*:0]const u8, ...) void;

	pub const func = getfn;
	extern fn getfn(*const Pd, *Symbol) ?*const GotFn;

	pub const zFunc = zgetfn;
	extern fn zgetfn(*const Pd, *Symbol) ?*const GotFn;

	/// This is externally available, but note that it might later disappear; the
	/// whole "newest" thing is a hack which needs to be redesigned.
	pub const newest = pd_newest; // static
	extern fn pd_newest() *Pd;

	pub fn init(cls: *Class) Error!*Pd {
		return pd_new(cls) orelse Error.PdInit;
	}
	extern fn pd_new(*Class) ?*Pd;
};


// ----------------------------------- Post ------------------------------------
// -----------------------------------------------------------------------------
pub const post = struct {
	pub fn do(fmt: [*:0]const u8, args: anytype) void {
		@call(.auto, post_, .{ fmt } ++ args);
	}
	const post_ = @extern(
		*const fn([*:0]const u8, ...) callconv(.c) void, .{ .name = "post" });

	pub fn start(fmt: [*:0]const u8, args: anytype) void {
		@call(.auto, startpost, .{ fmt } ++ args);
	}
	extern fn startpost([*:0]const u8, ...) void;

	pub const end = endpost;
	extern fn endpost() void;

	pub const string = poststring;
	extern fn poststring([*:0]const u8) void;

	pub const float = postfloat;
	extern fn postfloat(f: Float) void;

	pub fn atom(av: []const Atom) void {
		postatom(@intCast(av.len), av.ptr);
	}
	extern fn postatom(c_uint, [*]const Atom) void;

	pub fn bug(fmt: [*:0]const u8, args: anytype) void {
		@call(.auto, bug_, .{ fmt } ++ args);
	}
	const bug_ = @extern(
		*const fn([*:0]const u8, ...) callconv(.c) void, .{ .name = "bug" });

	pub fn err(self: ?*const anyopaque, fmt: [*:0]const u8, args: anytype) void {
		@call(.auto, pd_error, .{ self, fmt } ++ args);
	}
	extern fn pd_error(?*const anyopaque, fmt: [*:0]const u8, ...) void;

	pub const LogLevel = enum(c_uint) {
		critical = 0,
		err = 1,
		normal = 2,
		debug = 3,
		verbose = 4,
		_,
	};

	pub fn log(
		obj: ?*const anyopaque,
		lvl: LogLevel,
		fmt: [*:0]const u8,
		args: anytype
	) void {
		@call(.auto, logpost, .{ obj, lvl, fmt } ++ args);
	}
	extern fn logpost(?*const anyopaque, LogLevel, [*:0]const u8, ...) void;
};


// --------------------------------- Resample ----------------------------------
// -----------------------------------------------------------------------------
pub const Resample = extern struct {
	/// unused
	method: Converter,
	/// downsampling factor
	downsample: c_uint,
	/// upsampling factor
	upsample: c_uint,
	/// here we hold the resampled data
	vec: [*]Sample,
	n: c_uint,
	/// coefficients for filtering...
	coeffs: [*]Sample,
	coef_size: c_uint,
	/// buffer for filtering
	buffer: [*]Sample,
	buf_size: c_uint,

	pub const Converter = enum(c_uint) {
		zero_padding = 0,
		zero_order_hold = 1,
		linear = 2,
	};

	pub const deinit = resample_free;
	extern fn resample_free(*Resample) void;

	pub const init = resample_init;
	extern fn resample_init(*Resample) void;

	pub fn dsp(self: *Resample, in: []Sample, out: []Sample, conv: Converter) void {
		resample_dsp(self, in.ptr, @intCast(in.len), out.ptr, @intCast(out.len), conv);
	}
	extern fn resample_dsp(*Resample, *Sample, c_uint, *Sample, c_uint, Converter) void;

	pub fn dspFrom(self: *Resample, in: []Sample, out_len: usize, conv: Converter) void {
		resamplefrom_dsp(self, in.ptr, @intCast(in.len), @intCast(out_len), conv);
	}
	extern fn resamplefrom_dsp(*Resample, *Sample, c_uint, c_uint, Converter) void;

	pub fn dspTo(self: *Resample, out: []Sample, in_len: usize, conv: Converter) void {
		resampleto_dsp(self, out.ptr, @intCast(in_len), @intCast(out.len), conv);
	}
	extern fn resampleto_dsp(*Resample, *Sample, c_uint, c_uint, Converter) void;
};


// ---------------------------------- Signal -----------------------------------
// -----------------------------------------------------------------------------
pub const Signal = extern struct {
	len: c_uint,
	vec: [*]Sample,
	srate: Float,
	nchans: c_uint,
	overlap: c_int,
	refcount: c_uint,
	isborrowed: c_uint,
	isscalar: c_uint,
	borrowedfrom: ?*Signal,
	nextfree: ?*Signal,
	nextused: ?*Signal,
	nalloc: c_uint,

	pub const Error = error {
		SignalInit,
	};

	/// Pop an audio signal from free list or create a new one.
	///
	/// If `scalarptr` is nonzero, it's a pointer to a scalar owned by the
	/// tilde object. In this case, we neither allocate nor free it.
	/// Otherwise, if `length` is zero, return a "borrowed"
	/// signal whose buffer and size will be obtained later via
	/// `signal_setborrowed()`.
	pub fn init(
		length: c_uint,
		nchans: c_uint,
		samplerate: Float,
		scalarptr: *Sample
	) Error!*Signal {
		return signal_new(length, nchans, samplerate, scalarptr) orelse Error.SignalInit;
	}
	extern fn signal_new(c_uint, c_uint, Float, *Sample) ?*Signal;

	/// Only use this in the context of dsp routines to set number of channels
	/// on output signal - we assume it's currently a pointer to the null signal.
	pub const setMultiOut = signal_setmultiout;
	extern fn signal_setmultiout(**Signal, c_uint) void;
};


// ---------------------------------- Symbol -----------------------------------
// -----------------------------------------------------------------------------
pub const Symbol = extern struct {
	name: [*:0]const u8,
	thing: ?*Pd,
	next: ?*Symbol,

	pub const gen = gensym;
	extern fn gensym([*:0]const u8) *Symbol; // could run out of memory
};

pub const setExternDir = class_set_extern_dir;
extern fn class_set_extern_dir(*Symbol) void;

pub const notify = text_notifybyname;
extern fn text_notifybyname(*Symbol) void;

pub extern var s_pointer: Symbol;
pub extern var s_float: Symbol;
pub extern var s_symbol: Symbol;
pub extern var s_bang: Symbol;
pub extern var s_list: Symbol;
pub extern var s_anything: Symbol;
pub extern var s_signal: Symbol;
pub extern var s__N: Symbol;
pub extern var s__X: Symbol;
pub extern var s_x: Symbol;
pub extern var s_y: Symbol;
pub extern var s_: Symbol;


// ---------------------------------- System -----------------------------------
// -----------------------------------------------------------------------------
pub const GuiCallbackFn = fn (*GObj, *GList) callconv(.c) void;

pub const blockSize = sys_getblksize;
extern fn sys_getblksize() c_uint;

pub const sampleRate = sys_getsr;
extern fn sys_getsr() Float;

pub const inChannels = sys_get_inchannels;
extern fn sys_get_inchannels() c_uint;

pub const outChannels = sys_get_outchannels;
extern fn sys_get_outchannels() c_uint;

/// If some GUI object is having to do heavy computations, it can tell
/// us to back off from doing more updates by faking a big one itself.
pub const pretendGuiBytes = sys_pretendguibytes;
extern fn sys_pretendguibytes(c_uint) void;

pub const queueGui = sys_queuegui;
extern fn sys_queuegui(
	client: *anyopaque, glist: *GList, f: ?*const GuiCallbackFn,
) void;

pub const unqueueGui = sys_unqueuegui;
extern fn sys_unqueuegui(client: *anyopaque) void;

pub const version = sys_getversion;
extern fn sys_getversion(major: *c_uint, minor: *c_uint, bugfix: *c_uint) c_uint;

pub const floatSize = sys_getfloatsize;
extern fn sys_getfloatsize() c_uint;

/// Get "real time" in seconds. Take the
/// first time we get called as a reference time of zero.
pub const realTime = sys_getrealtime;
extern fn sys_getrealtime() f64;

pub const lock = sys_lock;
extern fn sys_lock() void;

pub const unlock = sys_unlock;
extern fn sys_unlock() void;

pub const tryLock = sys_trylock;
extern fn sys_trylock() c_int;

pub const hostFontSize = sys_hostfontsize;
extern fn sys_hostfontsize(c_uint, c_uint) c_uint;

pub fn zoomFontWidth(fontsize: c_uint, zoom: c_uint, worst_case: bool) c_uint {
	return sys_zoomfontwidth(fontsize, zoom, @intFromBool(worst_case));
}
extern fn sys_zoomfontwidth(c_uint, c_uint, c_uint) c_uint;

pub fn zoomFontHeight(fontsize: c_uint, zoom: c_uint, worst_case: bool) c_uint {
	return sys_zoomfontheight(fontsize, zoom, @intFromBool(worst_case));
}
extern fn sys_zoomfontheight(c_uint, c_uint, c_uint) c_uint;

pub const fontWidth = sys_fontwidth;
extern fn sys_fontwidth(c_uint) c_uint;

pub const fontHeight = sys_fontheight;
extern fn sys_fontheight(c_uint) c_uint;

pub fn isAbsolutePath(dir: [*:0]const u8) bool {
	return (sys_isabsolutepath(dir) != 0);
}
extern fn sys_isabsolutepath([*:0]const u8) c_uint;

pub fn currentDir() ?*Symbol {
	// avoid `extern fn canvas_getcurrentdir()`, it will cause pd to crash.
	return if (GList.current()) |glist| glist.dir() else null;
}

/// DSP can be suspended before, and resumed after, operations which
/// might affect the DSP chain.  For example, we suspend before loading and
/// resume afterward, so that DSP doesn't get resorted for every DSP object
/// in the patch.
pub fn suspendDsp() bool {
	return (canvas_suspend_dsp() != 0);
}
extern fn canvas_suspend_dsp() c_uint;

pub fn resumeDsp(old_state: bool) void {
	canvas_resume_dsp(@intFromBool(old_state));
}
extern fn canvas_resume_dsp(c_uint) void;

/// this is equivalent to suspending and resuming in one step.
pub const updateDsp = canvas_update_dsp;
extern fn canvas_update_dsp() void;

pub const setFileName = glob_setfilename;
extern fn glob_setfilename(dummy: *anyopaque, name: *Symbol, dir: *Symbol) void;

pub const canvasList = pd_getcanvaslist;
extern fn pd_getcanvaslist() *GList;

pub fn dspState() bool {
	return (pd_getdspstate() != 0);
}
extern fn pd_getdspstate() c_uint;


// ----------------------------------- Value -----------------------------------
// -----------------------------------------------------------------------------
pub const value = struct {
	pub const Error = error {
		ValueGet,
		ValueSet,
	};

	/// Get a pointer to a named floating-point variable.  The variable
	/// belongs to a `vcommon` object, which is created if necessary.
	pub const from = value_get;
	extern fn value_get(*Symbol) *Float;

	pub const release = value_release;
	extern fn value_release(*Symbol) void;

	/// obtain the float value of a "value" object
	pub fn get(sym: *Symbol, f: *Float) Error!void {
		if (value_getfloat(sym, f) != 0)
			return Error.ValueGet;
	}
	extern fn value_getfloat(*Symbol, *Float) c_int;

	pub fn set(sym: *Symbol, f: Float) Error!void {
		if (value_setfloat(sym, f) != 0)
			return Error.ValueSet;
	}
	extern fn value_setfloat(*Symbol, Float) c_int;
};


// ----------------------------------- Misc ------------------------------------
// -----------------------------------------------------------------------------
pub const object_maker = &pd_objectmaker;
pub extern var pd_objectmaker: Pd;

pub const canvas_maker = &pd_canvasmaker;
pub extern var pd_canvasmaker: Pd;

pub const GotFn = fn (*anyopaque, ...) callconv(.c) void;
pub const GotFn1 = fn (*anyopaque, *anyopaque) callconv(.c) void;
pub const GotFn2 = fn (*anyopaque, *anyopaque, *anyopaque) callconv(.c) void;
pub const GotFn3 = fn (*anyopaque, *anyopaque, *anyopaque, *anyopaque) callconv(.c) void;
pub const GotFn4 = fn (
	*anyopaque, *anyopaque, *anyopaque, *anyopaque, *anyopaque,
) callconv(.c) void;
pub const GotFn5 = fn (
	*anyopaque, *anyopaque, *anyopaque, *anyopaque, *anyopaque, *anyopaque,
) callconv(.c) void;

pub const nullFn = nullfn;
extern fn nullfn() void;

pub const font: [*:0]u8 = @extern([*:0]u8, .{ .name = "sys_font" });
pub const font_weight: [*:0]u8 = @extern([*:0]u8, .{ .name = "sys_fontweight" });

/// Get a number unique to the (clock, MIDI, GUI, etc.) event we're on
pub const eventNumber = sched_geteventno;
extern fn sched_geteventno() c_uint;

/// sys_idlehook is a hook the user can fill in to grab idle time.  Return
/// nonzero if you actually used the time; otherwise we're really really idle and
/// will now sleep.
pub extern var sys_idlehook: ?*const fn () callconv(.c) c_int;

pub const plusPerform = plus_perform;
extern fn plus_perform(args: [*]usize) *usize;

pub const plusPerf8 = plus_perf8;
extern fn plus_perf8(args: [*]usize) *usize;

pub const zeroPerform = zero_perform;
extern fn zero_perform(args: [*]usize) *usize;

pub const zeroPerf8 = zero_perf8;
extern fn zero_perf8(args: [*]usize) *usize;

pub const copyPerform = copy_perform;
extern fn copy_perform(args: [*]usize) *usize;

pub const copyPerf8 = copy_perf8;
extern fn copy_perf8(args: [*]usize) *usize;

pub const scalarCopyPerform = scalarcopy_perform;
extern fn scalarcopy_perform(args: [*]usize) *usize;

pub const scalarCopyPerf8 = scalarcopy_perf8;
extern fn scalarcopy_perf8(args: [*]usize) *usize;

pub const mayer = struct {
	pub fn fht(fz: []Sample) void {
		mayer_fht(fz.ptr, @intCast(fz.len));
	}
	extern fn mayer_fht([*]Sample, c_uint) void;

	pub const fft = mayer_fft;
	extern fn mayer_fft(c_uint, [*]Sample, [*]Sample) void;

	pub const ifft = mayer_ifft;
	extern fn mayer_ifft(c_uint, [*]Sample, [*]Sample) void;

	pub fn realfft(real: []Sample) void {
		mayer_realfft(@intCast(real.len), real.ptr);
	}
	extern fn mayer_realfft(c_uint, [*]Sample) void;

	pub fn realifft(real: []Sample) void {
		mayer_realifft(@intCast(real.len), real.ptr);
	}
	extern fn mayer_realifft(c_uint, [*]Sample) void;
};

pub fn fft(buf: []Float, inverse: bool) void {
	pd_fft(buf.ptr, @intCast(buf.len), @intFromBool(inverse));
}
extern fn pd_fft([*]Float, c_uint, c_uint) void;

const ushift = std.meta.Int(.unsigned, @log2(@as(Float, @bitSizeOf(usize))));
pub fn ulog2(n: usize) ushift {
	var i = n;
	var r: ushift = 0;
	while (i > 1) : (i >>= 1) {
		r += 1;
	}
	return r;
}

pub const mToF = mtof;
extern fn mtof(Float) Float;

pub const fToM = ftom;
extern fn ftom(Float) Float;

pub const rmsToDb = rmstodb;
extern fn rmstodb(Float) Float;

pub const powToDb = powtodb;
extern fn powtodb(Float) Float;

pub const dbToRms = dbtorms;
extern fn dbtorms(Float) Float;

pub const dbToPow = dbtopow;
extern fn dbtopow(Float) Float;

pub const q8Sqrt = q8_sqrt;
extern fn q8_sqrt(Float) Float;

pub const q8Rsqrt = q8_rsqrt;
extern fn q8_rsqrt(Float) Float;

pub const qSqrt = qsqrt;
extern fn qsqrt(Float) Float;

pub const qRsqrt = qrsqrt;
extern fn qrsqrt(Float) Float;

pub fn vMess(destination: ?[*:0]const u8, fmt: ?[*:0]const u8, args: anytype) void {
	@call(.auto, pdgui_vmess, .{ destination, fmt } ++ args);
}
extern fn pdgui_vmess(?[*:0]const u8, ?[*:0]const u8, ...) void;

pub const deleteStubForKey = pdgui_stub_deleteforkey;
extern fn pdgui_stub_deleteforkey(key: *anyopaque) void;

const float_bits = @bitSizeOf(Float);
const mantissa_bits = std.math.floatMantissaBits(Float);
const exponent_bits = std.math.floatExponentBits(Float);
const exp_mask = ((1 << exponent_bits) - 1) << mantissa_bits;
const bos_mask = 1 << (float_bits - 3);

pub const BigOrSmall = extern union {
	f: Float,
	ui: @Type(.{ .int = .{ .signedness = .unsigned, .bits = float_bits } }),
};

pub fn badFloat(f: Float) bool {
	var pun = BigOrSmall{ .f = f };
	pun.ui &= exp_mask;
	return (f != 0 and (pun.ui == 0 or pun.ui == exp_mask));
}

test badFloat {
	try std.testing.expect(badFloat((BigOrSmall{ .ui = exp_mask }).f)); // infinity
	try std.testing.expect(badFloat((BigOrSmall{ .ui = exp_mask + 1 }).f)); // NaN
	try std.testing.expect(badFloat((BigOrSmall{ .ui = 1 }).f)); // denormal
	try std.testing.expect(!badFloat(123.45)); // good float
}

pub fn bigOrSmall(f: Float) bool {
	const pun = BigOrSmall{ .f = f };
	return ((pun.ui & bos_mask) == ((pun.ui >> 1) & bos_mask));
}

test bigOrSmall {
	const big = if (float_bits == 64) 0x1p513 else 0x1p65;
	const small = if (float_bits == 64) 0x1p-512 else 0x1p-64;
	const almost_big = if (float_bits == 64) 0x1p512 else 0x1p64;
	const almost_small = if (float_bits == 64) 0x1p-511 else 0x1p-63;
	try std.testing.expect(bigOrSmall(big));
	try std.testing.expect(bigOrSmall(small));
	try std.testing.expect(!bigOrSmall(almost_big));
	try std.testing.expect(!bigOrSmall(almost_small));
}

pub const Instance = extern struct {
	/// global time in Pd ticks
	systime: f64,
	/// linked list of set clocks
	clock_setlist: ?*Clock,
	/// linked list of all root canvases
	canvaslist: ?*GList,
	/// linked list of all templates
	templatelist: ?*cnv.Template,
	/// ordinal number of this instance
	instanceno: c_uint,
	/// symbol table hash table
	symhash: [*]*Symbol,
	/// private stuff for x_midi.c
	midi: *Midi,
	/// private stuff for s_inter.c
	inter: *Inter,
	/// private stuff for d_ugen.c
	ugen: *Ugen,
	/// semi-private stuff in g_canvas.h
	gui: *GList.Instance,
	/// semi-private stuff in s_stuff.h
	stuff: *stf.Instance,
	/// most recently created object
	newest: *Pd,
	// islocked: c_uint, // should only exist if threads are enabled

	pub const Midi = opaque {};
	pub const Inter = opaque {};
	pub const Ugen = opaque {};
};
pub extern const pd_maininstance: Instance;

pub fn this() *const Instance {
	// TODO: fix this to be multi-instance compatible
	return &pd_maininstance;
}

pub const max_string = 1000;
pub const max_arg = 5;
pub const max_logsig = 32;
pub const max_sigsize = 1 << max_logsig;
pub const threads = 1;
