const c = @import("cdef");
const std = @import("std");
const builtin = @import("builtin");
pub const opt = @import("options");
pub const imp = @import("imp.zig");
pub const cnv = @import("canvas.zig");
pub const iem = @import("all_guis.zig");
pub const stf = @import("stuff.zig");

pub extern const pd_compatibilitylevel: c_int;

pub const uint = @Int(.unsigned, @bitSizeOf(c_int) - 1);
pub const Float = c.t_float;
pub const Sample = Float;

pub fn Rect(T: type) type { return struct {
	/// top-left
	p1: @Vector(2, T),
	/// bottom-right
	p2: @Vector(2, T),

	pub fn size(self: *const @This()) @Vector(2, T) {
		return self.p2 - self.p1;
	}
};}

pub const Method = fn () callconv(.c) void;
pub const NewMethod = fn () callconv(.c) ?*anyopaque;

pub const Array = cnv.Array;
pub const Class = imp.Class;
pub const GList = cnv.GList;
pub const GObj = cnv.GObj;
pub const Gui = iem.Gui;
pub const RText = cnv.RText;

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

		pub fn tuple(
			comptime args: []const Type,
		) @Tuple(&[_]type {c_uint} ** (args.len + 1)) {
			var tpl: @Tuple(&[_]type {c_uint} ** (args.len + 1)) = undefined;
			inline for (0..args.len) |i| {
				tpl[i] = @intFromEnum(args[i]);
			}
			tpl[args.len] = @intFromEnum(Type.none);
			return tpl;
		}
	};

	pub inline fn getFloat(self: Atom) ?Float {
		return if (self.type == .float) self.w.float else null;
	}

	pub inline fn getSymbol(self: Atom) ?*Symbol {
		return if (self.type == .symbol) self.w.symbol else null;
	}

	pub fn toSymbol(self: *const Atom) *Symbol {
		return c.atom_gensym(@ptrCast(self));
	}

	pub fn bufPrint(self: *const Atom, buf: []u8) void {
		c.atom_string(@ptrCast(self), buf.ptr, @intCast(buf.len));
	}

	pub inline fn float(f: Float) Atom {
		return .{ .type = .float, .w = .{ .float = f } };
	}

	pub inline fn symbol(sym: *Symbol) Atom {
		return .{ .type = .symbol, .w = .{ .symbol = sym } };
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
	return if (idx < av.len)
		av[idx].getFloat() orelse error.WrongAtomType
	else error.IndexOutOfBounds;
}

pub inline fn symbolArg(idx: usize, av: []const Atom) ArgError!*Symbol {
	return if (idx < av.len)
		av[idx].getSymbol() orelse error.WrongAtomType
	else error.IndexOutOfBounds;
}

fn typesFromAtoms(comptime args: []const Atom.Type) [args.len]type {
	var types: [args.len]type = undefined;
	for (args, &types) |a, *t| {
		t.* = switch (a) {
			.symbol, .defsymbol => *Symbol,
			else => Float,
		};
	}
	return types;
}

const Fn = std.builtin.Type.Fn;

fn paramsFromTypes(comptime types: []const type) [types.len]Fn.Param {
	var params: [types.len]Fn.Param = undefined;
	for (types, &params) |t, *p| {
		p.* = .{
			.is_generic = false,
			.is_noalias = false,
			.type = t,
		};
	}
	return params;
}

pub fn NewFn(T: type, comptime args: []const Atom.Type) type {
	const types: []const type = if (args.len == 0)
		&.{}
	else if (args[0] == .gimme)
		&.{ *Symbol, c_uint, [*]Atom }
	else
		&typesFromAtoms(args);

	return @Fn(types, &@splat(.{}), ?*T, .{ .@"callconv" = .c });
}

pub fn addCreator(
	T: type,
	name: [:0]const u8,
	comptime args: []const Atom.Type,
	new_method: ?*const NewFn(T, args),
) void {
	const sym: *Symbol = .gen(name);
	const csym: *c.t_symbol = @ptrCast(sym);
	const newm: *const NewMethod = @ptrCast(new_method);
	@call(.auto, c.class_addcreator, .{ newm, csym } ++ Atom.Type.tuple(args));
}


// ---------------------------------- BinBuf -----------------------------------
// -----------------------------------------------------------------------------
pub const BinBuf = opaque {
	pub const Options = packed struct(c_uint) {
		skip_shebang: bool = false,
		map_cr: bool = false,
		_unused: @Int(.unsigned, @bitSizeOf(c_uint) - 2) = 0,
	};

	pub fn deinit(self: *BinBuf) void {
		return c.binbuf_free(@ptrCast(self));
	}

	pub fn duplicate(self: *const BinBuf) error{OutOfMemory}!*BinBuf {
		return c.binbuf_duplicate(@ptrCast(self)) orelse error.OutOfMemory;
	}

	pub fn len(self: *const BinBuf) uint {
		return @intCast(c.binbuf_getnatom(@ptrCast(self)));
	}

	pub fn getVec(self: *const BinBuf) [*]Atom {
		return @ptrCast(c.binbuf_getvec(@ptrCast(self)));
	}

	pub fn getSlice(self: *BinBuf) []Atom {
		return self.getVec()[0..self.len()];
	}

	pub fn fromText(self: *BinBuf, txt: []const u8) error{BinBufNoAtoms}!*void {
		c.binbuf_text(@ptrCast(self), txt.ptr, txt.len);
		if (self.len() == 0)
			return error.BinBufNoAtoms;
	}

	/// Convert a binbuf to text. No null termination.
	pub fn toText(self: *const BinBuf) []u8 {
		var ptr: [*]u8 = undefined;
		var n: c_int = undefined;
		c.binbuf_gettext(@ptrCast(self), &ptr, &n);
		return ptr[0..@intCast(n)];
	}

	pub fn clear(self: *BinBuf) void {
		return c.binbuf_clear(@ptrCast(self));
	}

	pub fn add(self: *BinBuf, av: []const Atom) error{OutOfMemory}!void {
		const newsize = self.len() + av.len;
		c.binbuf_add(@ptrCast(self), @intCast(av.len), @ptrCast(av.ptr));
		if (self.len() != newsize)
			return error.OutOfMemory;
	}

	pub fn addV(
		self: *BinBuf,
		fmt: [:0]const u8,
		args: anytype,
	) error{OutOfMemory}!void {
		const newsize = self.len() + fmt.len;
		const info = @typeInfo(@TypeOf(c.binbuf_addv));
		const x: info.@"fn".params[0].type.? = @ptrCast(self);
		@call(.auto, c.binbuf_addv, .{ x, fmt.ptr } ++ args);
		if (self.len() != newsize)
			return error.OutOfMemory;
	}

	/// Add a binbuf to another one for saving. Semicolons and commas go to
	/// symbols ";", "'",; and inside symbols, characters ';', ',' and '$' get
	/// escaped. LATER also figure out about escaping white space
	pub fn join(self: *BinBuf, other: *const BinBuf) error{OutOfMemory}!void {
		const newsize = self.len() + other.len();
		c.binbuf_addbinbuf(@ptrCast(self), @ptrCast(self));
		if (self.len() != newsize)
			return error.OutOfMemory;
	}

	pub fn addSemi(self: *BinBuf) error{OutOfMemory}!void {
		const newsize = self.len() + 1;
		c.binbuf_addsemi(@ptrCast(self));
		if (self.len() != newsize)
			return error.OutOfMemory;
	}

	/// Supply atoms to a binbuf from a message, making the opposite changes
	/// from `join`.  The symbol ";" goes to a semicolon, etc.
	pub fn restore(self: *BinBuf, av: []Atom) error{OutOfMemory}!void {
		const newsize = self.len() + av.len;
		c.binbuf_restore(@ptrCast(self), @intCast(av.len), @ptrCast(av.ptr));
		if (self.len() != newsize)
			return error.OutOfMemory;
	}

	pub fn print(self: *const BinBuf) void {
		return c.binbuf_print(@ptrCast(self));
	}

	pub fn eval(self: *const BinBuf, target: *Pd, av: []Atom) void {
		c.binbuf_eval(@ptrCast(self), target, @intCast(av.len), @ptrCast(av.ptr));
	}

	pub fn read(
		self: *BinBuf,
		filename: [*:0]const u8,
		dirname: [*:0]const u8,
		crflag: Options,
	) error{BinBufRead}!void {
		if (c.binbuf_read(@ptrCast(self), filename, dirname, crflag) != 0)
			return error.BinBufRead;
	}

	/// Read a binbuf from a file, via the search patch of a canvas
	pub fn readViaCanvas(
		self: *BinBuf,
		filename: [*:0]const u8,
		canvas: *const GList,
		crflag: Options,
	) error{BinBufReadViaCanvas}!void {
		if (c.binbuf_read_via_canvas(@ptrCast(self), filename, canvas, crflag) != 0)
			return error.BinBufReadViaCanvas;
	}

	pub fn write(
		self: *const BinBuf,
		filename: [*:0]const u8,
		dirname: [*:0]const u8,
		crflag: Options,
	) error{BinBufWrite}!void {
		if (c.binbuf_write(@ptrCast(self), filename, dirname, crflag) != 0)
			return error.BinBufWrite;
	}

	pub fn resize(self: *BinBuf, newsize: uint) error{OutOfMemory}!void {
		if (c.binbuf_resize(@ptrCast(self), newsize) == 0)
			return error.OutOfMemory;
	}

	pub fn init() error{OutOfMemory}!*BinBuf {
		return if (c.binbuf_new()) |bb| @ptrCast(bb) else error.OutOfMemory;
	}

	/// Public interface to get text buffers by name
	pub fn fromName(name: *Symbol) ?*BinBuf {
		return c.text_getbufbyname(@ptrCast(name));
	}
};

pub fn evalFile(name: *Symbol, dir: *Symbol) void {
	c.binbuf_evalfile(@ptrCast(name), @ptrCast(dir));
}

pub fn realizeDollSym(
	sym: *Symbol,
	av: []const Atom,
	tonew: bool
) error{RealizeDollSym}!*Symbol {
	return c.binbuf_realizedollsym(
		@ptrCast(sym), @intCast(av.len), @ptrCast(av.ptr), @intFromBool(tonew),
	) orelse error.RealizeDollSym;
}


// ----------------------------------- Clock -----------------------------------
// -----------------------------------------------------------------------------
pub const Clock = opaque {
	pub fn deinit(self: *Clock) void {
		return c.clock_free(@ptrCast(self));
	}

	pub fn set(self: *Clock, sys_time: f64) void {
		c.clock_set(@ptrCast(self), sys_time);
	}

	pub fn delay(self: *Clock, delay_time: f64) void {
		c.clock_delay(@ptrCast(self), delay_time);
	}

	pub fn unset(self: *Clock) void {
		c.clock_unset(@ptrCast(self));
	}

	pub fn setUnit(self: *Clock, unit: TimeUnit) void {
		c.clock_setunit(@ptrCast(self), unit.amount, @intFromBool(unit.in_samples));
	}

	pub fn init(owner: *anyopaque, func: *const Method) error{OutOfMemory}!*Clock {
		return if (c.clock_new(owner, func)) |clk| @ptrCast(clk) else error.OutOfMemory;
	}
};

pub const TimeUnit = extern struct {
	amount: f64 = 1,
	in_samples: bool = false,

	pub fn init(amount: Float, unit: *Symbol) error{UnknownTimeUnit}!TimeUnit {
		const name: [:0]const u8 = std.mem.sliceTo(unit.name, 0);
		const is_per = std.mem.startsWith(u8, name, "per");
		const sym = if (is_per) name[3..] else name;

		const in_samples = std.mem.startsWith(u8, sym, "sam");
		const f: Float = if (in_samples or std.mem.startsWith(u8, sym, "ms")) 1
		else if (std.mem.startsWith(u8, sym, "sec")) 1000
		else if (std.mem.startsWith(u8, sym, "min")) 60000
		else return error.UnknownTimeUnit;

		const amt = if (amount <= 0) 1 else amount;
		return .{
			.amount = if (is_per) f / amt else f * amt,
			.in_samples = in_samples,
		};
	}

	pub fn timeSince(self: TimeUnit, prevsystime: f64) f64 {
		return c.clock_gettimesincewithunits(prevsystime,
			self.amount, @intFromBool(self.in_samples));
	}
};

/// Get current logical time.  We don't specify what units this is in;
/// use `timeSince()` to measure intervals from time of this call.
pub const time = c.clock_getlogicaltime;

/// elapsed time in milliseconds since the given logical time.
pub const timeSince = c.clock_gettimesince;

/// what value the system clock will have after a delay
pub const timeAfter = c.clock_getsystimeafter;


// ------------------------------------ Dsp ------------------------------------
// -----------------------------------------------------------------------------
pub const dsp = struct {
	pub const PerfRoutine = fn ([*]usize) callconv(.c) [*]usize;

	pub fn add(perf: *const PerfRoutine, args: anytype) void {
		const p: c.t_perfroutine = @ptrCast(perf);
		@call(.auto, c.dsp_add, .{ p, @as(c_int, @intCast(args.len)) } ++ args);
	}

	pub fn addV(perf: *const PerfRoutine, vec: []usize) void {
		c.dsp_addv(@ptrCast(perf), @intCast(vec.len), vec.ptr);
	}

	pub fn addPlus(in1: [*]Sample, in2: [*]Sample, out: [*]Sample, len: uint) void {
		c.dsp_add_plus(in1, in2, out, len);
	}

	pub fn addCopy(in: [*]Sample, out: [*]Sample, len: uint) void {
		c.dsp_add_copy(in, out, len);
	}

	pub fn addScalarCopy(in: [*]Float, out: [*]Sample, len: uint) void {
		c.dsp_add_scalarcopy(in, out, len);
	}

	pub fn addZero(out: [*]Sample, len: uint) void {
		c.dsp_add_zero(out, len);
	}
};


// ---------------------------------- GArray -----------------------------------
// -----------------------------------------------------------------------------
pub extern const garray_class: *Class;
pub extern const scalar_class: *Class;

pub const GArray = opaque {
	pub fn redraw(self: *GArray) void {
		c.garray_redraw(@ptrCast(self));
	}

	pub fn array(self: *GArray) error{GetArrayFail}!*Array {
		return if (c.garray_getarray(@ptrCast(self))) |arr|
			@ptrCast(arr)
		else error.GetArrayFail;
	}

	pub fn vec(self: *GArray) ![]u8 {
		const arr = try self.array();
		return arr.vec[0..arr.len];
	}

	pub fn resize(self: *GArray, len: uint) !void {
		c.garray_resize_long(@ptrCast(self), len);
		const arr = try self.array();
		if (arr.len < len) {
			return error.OutOfMemory;
		}
	}

	pub fn useInDsp(self: *GArray) void {
		c.garray_usedindsp(@ptrCast(self));
	}

	pub fn setSaveInPatch(self: *GArray, saveit: bool) void {
		c.garray_setsaveit(@ptrCast(self), @intFromBool(saveit));
	}

	pub fn gList(self: *GArray) *GList {
		return c.garray_getglist(@ptrCast(self));
	}

	pub fn floatWords(self: *GArray) error{GArrayBadTemplate}![]Word {
		var len: c_int = undefined;
		var ptr: [*]Word = undefined;
		return if (c.garray_getfloatwords(@ptrCast(self), &len, @ptrCast(&ptr)) != 0)
			ptr[0..@intCast(len)]
		else error.GArrayBadTemplate;
	}
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
	refcount: c_uint,

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
	un: Union = .{ .scalar = null },
	valid: c_int = 0,
	stub: ?*GStub = null,

	pub const Union = extern union {
		scalar: ?*Scalar,
		w: *Word,
	};

	pub fn init(self: *GPointer) void {
		self.* = .{};
	}

	/// Copy a pointer to another, assuming the second one hasn't yet been
	/// initialized. New gpointers should be initialized either by this
	/// routine or by `init()`.
	pub fn copyTo(self: *const GPointer, target: *GPointer) void {
		c.gpointer_copy(@ptrCast(self), @ptrCast(target));
	}

	/// Clear a `GPointer` that was previously set, releasing the associated
	/// gstub if this was the last reference to it.
	pub fn unset(self: *GPointer) void {
		c.gpointer_unset(@ptrCast(self));
	}

	/// Call this to verify that a pointer is fresh, i.e., that it either
	/// points to real data or to the head of a list, and that in either case
	/// the object hasn't disappeared since this pointer was generated.
	/// Unless `head_ok` is set, the routine also fails for the head of a list.
	pub fn check(self: *GPointer, head_ok: bool) bool {
		return (c.gpointer_check(@ptrCast(self), @intFromBool(head_ok)) != 0);
	}
};


// ----------------------------------- Inlet -----------------------------------
// -----------------------------------------------------------------------------
pub const Inlet = opaque {
	pub fn deinit(self: *Inlet) void {
		c.inlet_free(@ptrCast(self));
	}

	pub fn init(
		owner: *Object, dest: *Pd,
		from: ?*Symbol, to: ?*Symbol,
	) error{OutOfMemory}!*Inlet {
		const s1: ?*c.t_symbol = @ptrCast(from);
		const s2: ?*c.t_symbol = @ptrCast(to);
		return if (c.inlet_new(@ptrCast(owner), @ptrCast(dest), s1, s2)) |inlet|
			@ptrCast(inlet)
		else error.OutOfMemory;
	}

	pub fn initFloat(owner: *Object, fp: *Float) error{OutOfMemory}!*Inlet {
		return if (c.floatinlet_new(@ptrCast(owner), fp)) |inlet|
			@ptrCast(inlet)
		else error.OutOfMemory;
	}

	pub fn initSymbol(owner: *Object, sym: **Symbol) error{OutOfMemory}!*Inlet {
		return if (c.symbolinlet_new(@ptrCast(owner), @ptrCast(sym))) |inlet|
			@ptrCast(inlet)
		else error.OutOfMemory;
	}

	pub fn initSignal(owner: *Object, f: Float) error{OutOfMemory}!*Inlet {
		return if (c.signalinlet_new(@ptrCast(owner), f)) |inlet|
			@ptrCast(inlet)
		else error.OutOfMemory;
	}

	pub fn initPointer(owner: *Object, gp: *GPointer) error{OutOfMemory}!*Inlet {
		return if (c.pointerinlet_new(@ptrCast(owner), @ptrCast(gp))) |inlet|
			@ptrCast(inlet)
		else error.OutOfMemory;
	}
};


// --------------------------------- Instance ----------------------------------
// -----------------------------------------------------------------------------
pub const Midi = opaque {};
pub const Inter = opaque {};
pub const Ugen = opaque {};

pub const Instance = if (opt.multi) extern struct {
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

	s_pointer: Symbol,
	s_float: Symbol,
	s_symbol: Symbol,
	s_bang: Symbol,
	s_list: Symbol,
	s_anything: Symbol,
	s_signal: Symbol,
	s__N: Symbol,
	s__X: Symbol,
	s_x: Symbol,
	s_y: Symbol,
	s_: Symbol,

	islocked: c_uint,

	pub fn init() error{OutOfMemory}!*Instance {
		return pdinstance_new() orelse error.OutOfMemory;
	}
	extern fn pdinstance_new() ?*Instance;

	pub const get = pd_getinstance;
	extern fn pd_getinstance() *Instance;

	pub const set = pd_setinstance;
	extern fn pd_setinstance(self: *const Instance) void;

	pub const free = pdinstance_free;
	extern fn pdinstance_free(self: *Instance) void;
} else extern struct {
	systime: f64,
	clock_setlist: ?*Clock,
	canvaslist: ?*GList,
	templatelist: ?*cnv.Template,
	instanceno: c_uint,
	symhash: [*]*Symbol,
	midi: *Midi,
	inter: *Inter,
	ugen: *Ugen,
	gui: *GList.Instance,
	stuff: *stf.Instance,
	newest: *Pd,
};

pub extern var pd_maininstance: Instance;

pub inline fn this() *Instance {
	return if (opt.multi) Instance.get() else &pd_maininstance;
}


// ---------------------------------- Memory -----------------------------------
// -----------------------------------------------------------------------------
const Allocator = std.mem.Allocator;
const Alignment = std.mem.Alignment;

fn alloc(_: *anyopaque, len: usize, _: Alignment, _: usize) ?[*]u8 {
	std.debug.assert(len > 0);
	return @ptrCast(c.getbytes(len));
}

fn resize(_: *anyopaque, buf: []u8, _: Alignment, new_len: usize, _: usize) bool {
	std.debug.assert(new_len > 0);
	return (new_len <= buf.len);
}

fn remap(_: *anyopaque, buf: []u8, _: Alignment, new_len: usize, _: usize) ?[*]u8 {
	return @ptrCast(c.resizebytes(buf.ptr, buf.len, new_len));
}

fn free(_: *anyopaque, buf: []u8, _: Alignment, _: usize) void {
	c.freebytes(buf.ptr, buf.len);
}

const mem_vtable = Allocator.VTable{
	.alloc = alloc,
	.resize = resize,
	.remap = remap,
	.free = free,
};

pub const gpa = Allocator{
	.ptr = undefined,
	.vtable = &mem_vtable,
};


// ---------------------------------- Object -----------------------------------
// -----------------------------------------------------------------------------
pub const Object = extern struct {
	/// header for graphical object
	g: GObj = .{},
	/// holder for the text
	binbuf: ?*BinBuf = null,
	/// linked list of outlets
	outlets: ?*Outlet = null,
	/// linked list of inlets
	inlets: ?*Inlet = null,
	/// location (within the toplevel)
	pix: [2]c_short = .{ 0, 0 },
	/// requested width in chars, 0 if auto
	width: c_ushort = 0,
	bf: packed struct(BitFieldType) {
		type: Type = .text,
		_unused: @Int(.unsigned, @bitSizeOf(BitFieldType) - 2) = 0,
	} = .{},

	const BitFieldType = if (builtin.os.tag == .windows) c_uint else u8;

	const Type = enum(u2) {
		/// just a textual comment
		text = 0,
		/// a MAX style patchable object
		object = 1,
		/// a MAX type message
		message = 2,
		/// a cell to display a number or symbol
		atom = 3,
	};

	pub fn drawBorder(
		self: *Object,
		glist: *GList,
		tag: [*:0]const u8,
		firsttime: bool,
	) void {
		c.text_drawborder(@ptrCast(self), @ptrCast(glist), tag, @intFromBool(firsttime));
	}

	pub fn eraseBorder(self: *Object, glist: *GList, tag: [*:0]const u8) void {
		c.text_eraseborder(@ptrCast(self), @ptrCast(glist), tag);
	}

	/// Interpret lists by feeding them to the individual inlets.
	/// Before you call this check that the object doesn't have a more
	/// specific way to handle lists.
	pub fn list(self: *Object, sym: *Symbol, av: []Atom) void {
		c.obj_list(@ptrCast(self), @ptrCast(sym), @intCast(av.len), @ptrCast(av.ptr));
	}

	pub fn saveFormat(self: *const Object, binbuf: *BinBuf) void {
		c.obj_saveformat(@ptrCast(self), @ptrCast(binbuf));
	}

	/// Get the window location in pixels of a "text" object.
	/// The object's x and y positions are in pixels when the glist they're
	/// in is toplevel. Otherwise, if it's a new-style graph-on-parent
	/// (so gl_goprect is set) we use the offset into the framing subrectangle
	/// as an offset into the parent rectangle. Finally, it might be an old,
	/// proportional-style GOP. In this case we do a coordinate transformation.
	pub fn pos(self: *const Object, glist: *const GList) @Vector(2, c_int) {
		const FVec2 = @Vector(2, Float);
		const IVec2 = @Vector(2, c_int);
		const pix: IVec2 = @intCast(@as(@Vector(2, c_short), self.pix));

		if (glist.flags.havewindow or !glist.flags.isgraph) {
			const zoom: c_int = @intCast(glist.zoom);
			return pix * IVec2{ zoom, zoom };
		}
		const rect: Rect(Float) = .{ .p1 = glist.p1, .p2 = glist.p2 };
		if (glist.flags.goprect) {
			const zoom: c_int = @intCast(glist.zoom);
			const p1: IVec2 = @intFromFloat(glist.toPixels(rect.p1));
			return p1 + IVec2{ zoom, zoom } * (pix - glist.margin);
		}
		const fpix: FVec2 = @floatFromInt(pix);
		const screen_size: FVec2 = @floatFromInt((Rect(c_int){
			.p1 = glist.screen1,
			.p2 = glist.screen2,
		}).size());
		return @intFromFloat(glist.toPixels(rect.p1 + rect.size() * fpix / screen_size));
	}

	pub const outlet = Outlet.init;
	pub const inlet = Inlet.init;
	pub const inletFloat = Inlet.initFloat;
	pub const inletSymbol = Inlet.initSymbol;
	pub const inletSignal = Inlet.initSignal;
	pub const inletPointer = Inlet.initPointer;

	/// connect an outlet of one object to an inlet of another.  The receiving
   /// "pd" is usually a patchable object, but this may be used to add a
   /// non-patchable pd to an outlet by specifying the 0th inlet.
	pub fn connect(
		self: *Object, outno: c_int,
		sink: *Object, inno: c_int,
	) error{ConnectFail}!*OutConnect {
		return if (c.obj_connect(@ptrCast(self), outno, @ptrCast(sink), inno)) |cnct|
			@ptrCast(cnct)
		else error.ConnectFail;
	}

	pub fn disconnect(self: *Object, outno: c_int, sink: *Object, inno: c_int) void {
		c.obj_disconnect(@ptrCast(self), outno, @ptrCast(sink), inno);
	}
};


// ---------------------------------- Outlet -----------------------------------
// -----------------------------------------------------------------------------
pub const Outlet = opaque {
	pub fn deinit(self: *Outlet) void {
		c.outlet_free(@ptrCast(self));
	}

	pub fn bang(self: *Outlet) void {
		c.outlet_bang(@ptrCast(self));
	}

	pub fn pointer(self: *Outlet, p: *GPointer) void {
		c.outlet_pointer(@ptrCast(self), @ptrCast(p));
	}

	pub fn float(self: *Outlet, f: Float) void {
		c.outlet_float(@ptrCast(self), f);
	}

	pub fn symbol(self: *Outlet, sym: *Symbol) void {
		c.outlet_symbol(@ptrCast(self), @ptrCast(sym));
	}

	pub fn list(self: *Outlet, sym: ?*Symbol, av: []const Atom) void {
		c.outlet_list(
			@ptrCast(self), @ptrCast(sym), @intCast(av.len), @ptrCast(@constCast(av.ptr)));
	}

	pub fn anything(self: *Outlet, sym: *Symbol, av: []const Atom) void {
		c.outlet_anything(
			@ptrCast(self), @ptrCast(sym), @intCast(av.len), @ptrCast(@constCast(av.ptr)));
	}

	/// Get the outlet's declared symbol
	pub fn getSymbol(self: *Outlet) *Symbol {
		return c.outlet_getsymbol(@ptrCast(self));
	}

	pub fn init(obj: *Object, atype: ?*Symbol) error{OutOfMemory}!*Outlet {
		return if (c.outlet_new(@ptrCast(obj), @ptrCast(atype))) |o|
			@ptrCast(o)
		else error.OutOfMemory;
	}
};


// ------------------------------------ Pd -------------------------------------
// -----------------------------------------------------------------------------
/// object to send "pd" messages
pub extern const glob_pdobject: *Class;

pub const Pd = extern struct {
	class: *const Class = undefined,

	pub fn deinit(self: *Pd) void {
		c.pd_free(@ptrCast(self));
	}

	pub fn bind(self: *Pd, sym: *Symbol) void {
		c.pd_bind(@ptrCast(self), @ptrCast(sym));
	}

	pub fn unbind(self: *Pd, sym: *Symbol) void {
		c.pd_unbind(@ptrCast(self), @ptrCast(sym));
	}

	pub fn pushSymbol(self: *Pd) void {
		c.pd_pushsym(@ptrCast(self));
	}

	pub fn popSymbol(self: *Pd) void {
		c.pd_popsym(@ptrCast(self));
	}

	pub fn bang(self: *Pd) void {
		c.pd_bang(@ptrCast(self));
	}

	pub fn pointer(self: *Pd, gp: *GPointer) void {
		c.pd_pointer(@ptrCast(self), @ptrCast(gp));
	}

	pub fn float(self: *Pd, f: Float) void {
		c.pd_float(@ptrCast(self), f);
	}

	pub fn symbol(self: *Pd, sym: *Symbol) void {
		c.pd_symbol(@ptrCast(self), @ptrCast(sym));
	}

	pub fn list(self: *Pd, sym: ?*Symbol, av: []const Atom) void {
		c.pd_list(@ptrCast(self), @ptrCast(sym), @intCast(av.len), @ptrCast(av.ptr));
	}

	pub fn anything(self: *Pd, sym: *Symbol, av: []const Atom) void {
		c.pd_anything(@ptrCast(self), @ptrCast(sym), @intCast(av.len), @ptrCast(av.ptr));
	}

	pub fn typedMess(self: *Pd, sym: *Symbol, av: []const Atom) void {
		c.pd_typedmess(@ptrCast(self), @ptrCast(sym), @intCast(av.len), @ptrCast(av.ptr));
	}

	/// Convenience routine giving a stdarg interface to `typedmess()`.
	/// Only ten args supported; it seems unlikely anyone will need more since
	/// longer messages are likely to be programmatically generated anyway.
	pub fn vMess(self: *Pd, sym: *Symbol, fmt: [*:0]const u8, args: anytype) void {
		const x: *c.t_pd = @ptrCast(self);
		const sm: *c.t_symbol = @ptrCast(sym);
		@call(.auto, c.pd_vmess, .{ x, sm, fmt } ++ args);
	}

	pub fn forwardMess(self: *Pd, av: []Atom) void {
		c.pd_forwardmess(@ptrCast(self), @intCast(av.len), @ptrCast(av.ptr));
	}

	/// Checks that a pd is indeed a patchable object, and returns
	/// it, correctly typed, or null if the check failed.
	pub fn checkObject(self: *Pd) ?*Object {
		return @ptrCast(c.pd_checkobject(@ptrCast(self)));
	}

	pub fn parentWidget(self: *Pd) ?*const cnv.parent.WidgetBehavior {
		return @ptrCast(c.pd_getparentwidget(@ptrCast(self)));
	}

	pub fn stub(
		self: *Pd,
		dest: [*:0]const u8,
		key: *anyopaque,
		fmt: [*:0]const u8,
		args: anytype
	) void {
		const owner: *c.t_pd = @ptrCast(self);
		@call(.auto, c.pdgui_stub_vnew, .{ owner, dest, key, fmt } ++ args);
	}

	/// This is externally available, but note that it might later disappear; the
	/// whole "newest" thing is a hack which needs to be redesigned.
	pub fn newest() *Pd {
		return @ptrCast(c.pd_newest());
	}

	pub fn init(cls: *Class) error{OutOfMemory}!*Pd {
		return if (c.pd_new(@ptrCast(cls))) |new|
			@ptrCast(new)
		else error.OutOfMemory;
	}

	/// Returns a pointer to the function `nullFn` on failure.
	pub fn getFn(self: *const Pd, sym: *Symbol) *const GotFn {
		return c.getfn(@ptrCast(self), @ptrCast(sym)).?;
	}

	/// Similar to `getFn`, but returns null on failure.
	pub fn zGetFn(self: *const Pd, sym: *Symbol) ?*const GotFn {
		return c.zgetfn(@ptrCast(self), @ptrCast(sym));
	}
};

/// An empty function that does nothing.
pub const nullFn = c.nullfn;


// ----------------------------------- Post ------------------------------------
// -----------------------------------------------------------------------------
pub const post = struct {
	pub fn do(fmt: [*:0]const u8, args: anytype) void {
		@call(.auto, c.pd_post, .{ fmt } ++ args);
	}

	pub fn start(fmt: [*:0]const u8, args: anytype) void {
		@call(.auto, c.startpost, .{ fmt } ++ args);
	}

	pub fn string(str: [*:0]const u8) void {
		c.poststring(str);
	}

	pub const end = c.endpost;
	pub const float = c.postfloat;

	pub fn atom(av: []const Atom) void {
		c.postatom(@intCast(av.len), @ptrCast(av.ptr));
	}

	pub fn bug(fmt: [*:0]const u8, args: anytype) void {
		@call(.auto, c.bug, .{ fmt } ++ args);
	}

	pub fn err(self: ?*const anyopaque, fmt: [*:0]const u8, args: anytype) void {
		@call(.auto, c.pd_error, .{ self, fmt } ++ args);
	}

	pub const LogLevel = enum(c_int) {
		critical = 0,
		err = 1,
		normal = 2,
		debug = 3,
		verbose = 4,
		_,
	};

	pub fn log(
		obj: ?*const anyopaque,
		level: LogLevel,
		fmt: [*:0]const u8,
		args: anytype
	) void {
		@call(.auto, c.logpost, .{ obj, @as(c_int, @intFromEnum(level)), fmt } ++ args);
	}
};

/// Wrapper for new and setup functions
pub inline fn wrap(T: type, result: anyerror!T, comptime prefix: [:0]const u8) ?T {
	return result catch |e| blk: {
		post.err(null, prefix ++ ": %s", .{ @errorName(e).ptr });
		break :blk null;
	};
}


// --------------------------------- Resample ----------------------------------
// -----------------------------------------------------------------------------
pub const Resample = extern struct {
	/// unused
	method: Converter = .zero_padding,
	/// downsampling factor
	downsample: c_uint = 1,
	/// upsampling factor
	upsample: c_uint = 1,
	/// here we hold the resampled data
	vec: [*]Sample = &.{},
	n: c_uint = 0,
	/// coefficients for filtering...
	coeffs: [*]Sample = &.{},
	coef_size: c_uint = 0,
	/// buffer for filtering
	buffer: [*]Sample = &.{},
	buf_size: c_uint = 0,

	pub const Converter = enum(c_int) {
		zero_padding = 0,
		zero_order_hold = 1,
		linear = 2,
	};

	pub fn deinit(self: *Resample) void {
		c.resample_free(@ptrCast(self));
	}

	pub fn init(self: *Resample) void {
		self.* = .{};
	}

	pub fn dsp(self: *Resample, in: []Sample, out: []Sample, conv: Converter) void {
		c.resample_dsp(@ptrCast(self),
			in.ptr, @intCast(in.len), out.ptr, @intCast(out.len), @intFromEnum(conv));
	}

	pub fn dspFrom(self: *Resample, in: []Sample, out_len: uint, conv: Converter) void {
		c.resamplefrom_dsp(@ptrCast(self),
			in.ptr, @intCast(in.len), out_len, @intFromEnum(conv));
	}

	pub fn dspTo(self: *Resample, in_len: uint, out: []Sample, conv: Converter) void {
		c.resampleto_dsp(@ptrCast(self),
			out.ptr, in_len, @intCast(out.len), @intFromEnum(conv));
	}
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

	/// Pop an audio signal from free list or create a new one.
	///
	/// If `scalarptr` is nonzero, it's a pointer to a scalar owned by the
	/// tilde object. In this case, we neither allocate nor free it.
	/// Otherwise, if `length` is zero, return a "borrowed"
	/// signal whose buffer and size will be obtained later via
	/// `signal_setborrowed()`.
	pub fn init(
		length: uint,
		nchans: uint,
		samplerate: Float,
		scalarptr: *Sample
	) error{OutOfMemory}!*Signal {
		return if (c.signal_new(length, nchans, samplerate, scalarptr)) |sig|
			@ptrCast(sig)
		else error.OutOfMemory;
	}

	/// Only use this in the context of dsp routines to set number of channels
	/// on output signal - we assume it's currently a pointer to the null signal.
	pub fn setMultiOut(sig: **Signal, nchans: uint) void {
		c.signal_setmultiout(@ptrCast(sig), nchans);
	}
};


// ---------------------------------- Symbol -----------------------------------
// -----------------------------------------------------------------------------
pub const Symbol = extern struct {
	name: [*:0]const u8,
	thing: ?*Pd,
	next: ?*Symbol,

	pub fn add(name: [*:0]const u8) error{OutOfMemory}!*Symbol {
		return if (c.gensym(name)) |sym| @ptrCast(sym) else error.OutOfMemory;
	}
	pub fn gen(name: [*:0]const u8) *Symbol {
		return if (c.gensym(name)) |sym| @ptrCast(sym) else s.empty();
	}
};

pub fn setExternDir(sym: *Symbol) void {
	c.class_set_extern_dir(@ptrCast(sym));
}

pub fn notify(sym: *Symbol) void {
	c.text_notifybyname(@ptrCast(sym));
}

pub const s = struct {
	pub inline fn pointer() *Symbol {
		return if (opt.multi) &this().s_pointer else &s_pointer;
	}
	extern var s_pointer: Symbol;

	pub inline fn float() *Symbol {
		return if (opt.multi) &this().s_float else &s_float;
	}
	pub extern var s_float: Symbol;

	pub inline fn symbol() *Symbol {
		return if (opt.multi) &this().s_symbol else &s_symbol;
	}
	pub extern var s_symbol: Symbol;

	pub inline fn bang() *Symbol {
		return if (opt.multi) &this().s_bang else &s_bang;
	}
	pub extern var s_bang: Symbol;

	pub inline fn list() *Symbol {
		return if (opt.multi) &this().s_list else &s_list;
	}
	pub extern var s_list: Symbol;

	pub inline fn anything() *Symbol {
		return if (opt.multi) &this().s_anything else &s_anything;
	}
	pub extern var s_anything: Symbol;

	pub inline fn signal() *Symbol {
		return if (opt.multi) &this().s_signal else &s_signal;
	}
	pub extern var s_signal: Symbol;

	pub inline fn _N() *Symbol {
		return if (opt.multi) &this().s__N else &s__N;
	}
	pub extern var s__N: Symbol;

	pub inline fn _X() *Symbol {
		return if (opt.multi) &this().s__X else &s__X;
	}
	pub extern var s__X: Symbol;

	pub inline fn x() *Symbol {
		return if (opt.multi) &this().s_x else &s_x;
	}
	pub extern var s_x: Symbol;

	pub inline fn y() *Symbol {
		return if (opt.multi) &this().s_y else &s_y;
	}
	pub extern var s_y: Symbol;

	pub inline fn empty() *Symbol {
		return if (opt.multi) &this().s_ else &s_;
	}
	pub extern var s_: Symbol;
};


// ---------------------------------- System -----------------------------------
// -----------------------------------------------------------------------------
pub const GuiCallbackFn = fn (*GObj, *GList) callconv(.c) void;

pub fn blockSize() uint {
	return @intCast(c.sys_getblksize());
}

pub const sampleRate = c.sys_getsr;

pub fn inChannels() uint {
	return @intCast(c.sys_get_inchannels());
}

pub fn outChannels() uint {
	return @intCast(c.sys_get_outchannels());
}

/// If some GUI object is having to do heavy computations, it can tell
/// us to back off from doing more updates by faking a big one itself.
pub fn pretendGuiBytes(nbytes: uint) void {
	c.sys_pretendguibytes(nbytes);
}

pub fn queueGui(client: *anyopaque, glist: *GList, f: ?*const GuiCallbackFn) void {
	c.sys_queuegui(client, @ptrCast(glist), @ptrCast(f));
}

pub fn unqueueGui(client: *anyopaque) void {
	c.sys_unqueuegui(client);
}

pub const version = c.sys_getversion;

/// Get "real time" in seconds. Take the
/// first time we get called as a reference time of zero.
pub const realTime = c.sys_getrealtime;

pub const queue = struct {
	pub const MessFn = fn(?*Pd, *anyopaque) callconv(.c) void;

	/// Send a message to a Pd object from another (helper) thread.
	/// `func` will be called on the scheduler thread with `obj` and `data`.
	/// If the message has been canceled, the `obj` argument is null, see
	/// `pd_queue_cancel()` below.
	///
	/// NB: do not forget to free the `data` object!
	pub fn mess(instance: *Instance, obj: ?*Pd, data: *anyopaque, func: *const MessFn) void {
		c.pd_queue_mess(@ptrCast(instance), @ptrCast(obj), data, @ptrCast(func));
	}

	/// Cancel all pending messages for the given object.
	/// Typically called in the object destructor AFTER joining the helper thread.
	pub fn cancel(obj: *Pd) void {
		c.pd_queue_cancel(@ptrCast(obj));
	}
};

pub fn hostFontSize(fontsize: uint, zoom: uint) uint {
	return @intCast(c.sys_hostfontsize(fontsize, zoom));
}

pub fn zoomFontWidth(fontsize: uint, zoom: uint, worst_case: bool) uint {
	return @intCast(c.sys_zoomfontwidth(fontsize, zoom, @intFromBool(worst_case)));
}

pub fn zoomFontHeight(fontsize: uint, zoom: uint, worst_case: bool) uint {
	return @intCast(c.sys_zoomfontheight(fontsize, zoom, @intFromBool(worst_case)));
}

pub fn fontWidth(fontsize: uint) uint {
	return @intCast(c.sys_fontwidth(fontsize));
}

pub fn fontHeight(fontsize: uint) uint {
	return @intCast(c.sys_fontheight(fontsize));
}

pub fn isAbsolutePath(dir: [*:0]const u8) bool {
	return (c.sys_isabsolutepath(dir) != 0);
}

pub fn currentDir() ?*Symbol {
	// avoid `c.canvas_getcurrentdir()`, it will cause pd to crash.
	return if (GList.getCurrent()) |glist| glist.dir() else null;
}

/// DSP can be suspended before, and resumed after, operations which
/// might affect the DSP chain.  For example, we suspend before loading and
/// resume afterward, so that DSP doesn't get resorted for every DSP object
/// in the patch.
pub fn suspendDsp() bool {
	return (c.canvas_suspend_dsp() != 0);
}

pub fn resumeDsp(old_state: bool) void {
	c.canvas_resume_dsp(@intFromBool(old_state));
}

/// this is equivalent to suspending and resuming in one step.
pub const updateDsp = c.canvas_update_dsp;

pub fn setFileName(dummy: *anyopaque, name: *Symbol, dir: *Symbol) void {
	c.glob_setfilename(dummy, @ptrCast(name), @ptrCast(dir));
}

pub fn canvasList() ?*GList {
	return @ptrCast(c.pd_getcanvaslist());
}

pub fn dspState() bool {
	return (c.pd_getdspstate() != 0);
}


// ----------------------------------- Value -----------------------------------
// -----------------------------------------------------------------------------
pub const value = struct {
	/// Get a pointer to a named floating-point variable.  The variable
	/// belongs to a `vcommon` object, which is created if necessary.
	pub fn from(name: *Symbol) *Float {
		return c.value_get(@ptrCast(name));
	}

	pub fn release(name: *Symbol) void {
		c.value_release(@ptrCast(name));
	}

	/// obtain the float value of a "value" object
	pub fn get(name: *Symbol, f: *Float) error{ValueGetFail}!void {
		if (c.value_getfloat(@ptrCast(name), f) != 0)
			return error.ValueGetFail;
	}

	pub fn set(name: *Symbol, f: Float) error{ValueSetFail}!void {
		if (c.value_setfloat(@ptrCast(name), f) != 0)
			return error.ValueSetFail;
	}
};


// ----------------------------------- Misc ------------------------------------
// -----------------------------------------------------------------------------
pub const object_maker = &pd_objectmaker;
pub extern var pd_objectmaker: Pd;

pub const canvas_maker = &pd_canvasmaker;
pub extern var pd_canvasmaker: Pd;

pub const GotFn = c.t_gotfn;
pub const GotFn1 = c.t_gotfn1;
pub const GotFn2 = c.t_gotfn2;
pub const GotFn3 = c.t_gotfn3;
pub const GotFn4 = c.t_gotfn4;
pub const GotFn5 = c.t_gotfn5;

pub const font: [*:0]u8 = @extern([*:0]u8, .{ .name = "sys_font" });
pub const font_weight: [*:0]u8 = @extern([*:0]u8, .{ .name = "sys_fontweight" });

/// Get a number unique to the (clock, MIDI, GUI, etc.) event we're on
pub const eventNumber = c.sched_geteventno;

/// sys_idlehook is a hook the user can fill in to grab idle time.  Return
/// nonzero if you actually used the time; otherwise we're really really idle and
/// will now sleep.
pub extern var sys_idlehook: c.sys_idlehook;

pub fn plusPerform(args: [*]usize) *usize {
	return @ptrCast(c.plus_perform(@ptrCast(args)));
}

pub fn plusPerf8(args: [*]usize) *usize {
	return @ptrCast(c.plus_perf8(@ptrCast(args)));
}

pub fn zeroPerform(args: [*]usize) *usize {
	return @ptrCast(c.zero_perform(@ptrCast(args)));
}

pub fn zeroPerf8(args: [*]usize) *usize {
	return @ptrCast(c.zero_perf8(@ptrCast(args)));
}

pub fn copyPerform(args: [*]usize) *usize {
	return @ptrCast(c.copy_perform(@ptrCast(args)));
}

pub fn copyPerf8(args: [*]usize) *usize {
	return @ptrCast(c.copy_perf8(@ptrCast(args)));
}

pub fn scalarCopyPerform(args: [*]usize) *usize {
	return @ptrCast(c.scalarcopy_perform(@ptrCast(args)));
}

pub fn scalarCopyPerf8(args: [*]usize) *usize {
	return @ptrCast(c.scalarcopy_perf8(@ptrCast(args)));
}

pub const mayer = struct {
	pub fn fht(fz: []Sample) void {
		c.mayer_fht(@ptrCast(fz.ptr), @intCast(fz.len));
	}

	pub fn fft(real: [*]Sample, imag: [*]Sample, len: uint) void {
		c.mayer_fft(len, real, imag);
	}

	pub fn ifft(real: [*]Sample, imag: [*]Sample, len: uint) void {
		c.mayer_ifft(len, real, imag);
	}

	pub fn realfft(real: []Sample) void {
		c.mayer_realfft(@intCast(real.len), real.ptr);
	}

	pub fn realifft(real: []Sample) void {
		c.mayer_realifft(@intCast(real.len), real.ptr);
	}
};

pub fn fft(buf: []Float, inverse: bool) void {
	c.pd_fft(buf.ptr, @intCast(buf.len), @intFromBool(inverse));
}

const ushift = @Int(
	.unsigned,
	@bitSizeOf(usize) - 1 - @clz(@as(usize, @bitSizeOf(usize))),
);
pub fn ulog2(n: usize) ?ushift {
	return if (n == 0) null else @intCast(@bitSizeOf(usize) - 1 - @clz(n));
}

test ulog2 {
	try std.testing.expectEqual(ulog2(127), 6);
	try std.testing.expectEqual(ulog2(64), 6);
	try std.testing.expectEqual(ulog2(1), 0);
	try std.testing.expectEqual(ulog2(0), 0);
}

pub fn freqFromMidi(midi: Float) Float {
	return c.mtof(midi);
}

pub fn midiFromFreq(freq: Float) Float {
	return c.ftom(freq);
}

pub fn dbFromRms(rms: Float) Float {
	return c.rmstodb(rms);
}

pub fn dbFromPow(pow: Float) Float {
	return c.powtodb(pow);
}

pub fn rmsFromDb(db: Float) Float {
	return c.dbtorms(db);
}

pub fn powFromDb(db: Float) Float {
	return c.dbtopow(db);
}

pub fn q8Sqrt(f: Float) Float {
	return c.q8_sqrt(f);
}

pub fn q8Rsqrt(f: Float) Float {
	return c.q8_rsqrt(f);
}

pub fn qSqrt(f: Float) Float {
	return c.qsqrt(f);
}

pub fn qRsqrt(f: Float) Float {
	return c.qrsqrt(f);
}


/// Send a message to the GUI, with a simplified formatting syntax.
/// The usage of `null` as a `destination` is discouraged.
///
/// depending on the format specifiers, one or more values are passed
/// - `f` : `f64` : a floating point number
/// - `i` : `c_int` : an integer number
/// - `s` : `[*:0]const u8` : a string
/// - `r` : `[*:0]const u8` : a raw string
/// - `x` : `*anyopaque` : a generic pointer
/// - `o` : `*Object` : a graphical object
/// - `^` : `*GList` : a toplevel window (legacy)
/// - `c` : `*GList` : a canvas (on a window)
/// - `F` : `c_uint`, `[*]Float`: array of t_float's
/// - `S` : `c_uint`, `[*][*:0]const u8`: array of strings
/// - `R` : `c_uint`, `[*][*:0]const u8`: array of raw strings
/// - `a` : `c_uint`, `[*]const Atom`: list of atoms
/// - `A` : `c_uint`, `[*]const Atom`: array of atoms
/// - `w` : `c_uint`, `[*]const Word`: list of floatwords
/// - `W` : `c_uint`, `[*]const Word`: array of floatwords
/// - `m` : `*Symbol`, `c_uint`, `[*]Atom` : a Pd message
/// - `p` : `c_uint`, `[*]const u8`: a pascal string (explicit size; not \0-terminated)
/// - `k` : `c_int`: a color (or kolor, if you prefer)
/// - ` ` : ignored
///
/// the use of the specifiers 'x^' is discouraged.
/// raw-strings ('rR') should only be used for constant, well-known strings.
pub fn vMess(
	/// receiver on the GUI side (e.g. a Tcl/Tk 'proc')
	destination: ?[*:0]const u8,
	/// string of format specifiers
	fmt: ?[*:0]const u8,
	/// values according to the format specifiers
	args: anytype
) void {
	@call(.auto, c.pdgui_vmess, .{ destination, fmt } ++ args);
}

pub fn deleteStubForKey(key: *anyopaque) void {
	c.pdgui_stub_deleteforkey(key);
}

const float_bits = @bitSizeOf(Float);
const mantissa_bits = std.math.floatMantissaBits(Float);
const exponent_bits = std.math.floatExponentBits(Float);
const exp_mask = ((1 << exponent_bits) - 1) << mantissa_bits;
const bos_mask = 1 << (float_bits - 3);

pub const BigOrSmall = extern union {
	f: Float,
	ui: @Int(.unsigned, float_bits),
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

pub const OutConnect = opaque {};

/// 1000, minus the sentinel,
/// minus another sentinel in case we forgot about the first one.
pub const max_string = 1000 - 2;

pub const max_arg = 5;
pub const max_logsig = 32;
pub const max_sigsize = 1 << max_logsig;
pub const threads = 1;
