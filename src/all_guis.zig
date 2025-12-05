const m = @import("pd.zig");
const cnv = @import("canvas.zig");

const Class = @import("imp.zig").Class;
const Atom = m.Atom;
const Float = m.Float;
const Symbol = m.Symbol;
const Object = m.Object;
const GList = cnv.GList;
const GObj = m.GObj;

pub const min_size = 8;
pub const max_size = 1000;
pub const max_num_len = 32;
pub const io_height = cnv.i_height;

inline fn contains(comptime haystack: []const Atom.Type, needle: Atom.Type) bool {
	inline for (haystack) |item| {
		if (item == needle) {
			return true;
		}
	}
	return false;
}

/// check if all atoms match a type in the haystack
pub inline fn matchTypes(
	av: [*]const Atom,
	comptime start: usize,
	comptime end: usize,
	comptime haystack: []const Atom.Type,
) bool {
	inline for (av[start..end]) |a| {
		if (!contains(haystack, a.type)) {
			return false;
		}
	}
	return true;
}


// ------------------------------------ Gui ------------------------------------
// -----------------------------------------------------------------------------
pub const DrawMode = enum(c_uint) {
	update = 0,
	move = 1,
	new = 2,
	select = 3,
	erase = 4,
	config = 5,
	io = 6,
};

pub const IemFn = fn (*anyopaque, *GList, DrawMode) callconv(.c) void;
pub const DrawFn = fn (*anyopaque, *GList) callconv(.c) void;

pub const DrawFunctions = extern struct {
	new: ?*const DrawFn = null,
	config: ?*const DrawFn = null,
	iolets: ?*const IemFn = null,
	update: ?*const DrawFn = null,
	select: ?*const DrawFn = null,
	erase: ?*const DrawFn = null,
	move: ?*const DrawFn = null,
};

pub const FontStyleFlags = packed struct(c_uint) {
	font_style: Style,
	rcv_able: bool,
	snd_able: bool,
	lab_is_unique: bool,
	rcv_is_unique: bool,
	snd_is_unique: bool,
	lab_arg_tail_len: u6,
	lab_is_arg_num: u6,
	shiftdown: bool,
	selected: bool,
	finemoved: bool,
	put_in2out: bool,
	change: bool,
	thick: bool,
	lin0_log1: bool,
	steady: bool,
	_unused: @Type(.{.int = .{
		.signedness = .unsigned, .bits = @bitSizeOf(c_uint) - 31,
	}}),

	pub const Style = enum(u6) {
		/// usually dejavu, or menlo on MacOS
		system = 0,
		helvetica = 1,
		times = 2,
	};

	pub const set = iem_inttofstyle;
	extern fn iem_inttofstyle(*FontStyleFlags, c_uint) void;

	pub const toInt = iem_fstyletoint;
	extern fn iem_fstyletoint(*FontStyleFlags) c_uint;
};

pub const InitSymArgs = packed struct(c_uint) {
	loadinit: bool,
	rcv_arg_tail_len: u6,
	snd_arg_tail_len: u6,
	rcv_is_arg_num: u6,
	snd_is_arg_num: u6,
	scale: bool,
	flashed: bool,
	locked: bool,
	_unused: @Type(.{.int = .{
		.signedness = .unsigned, .bits = @bitSizeOf(c_uint) - 28,
	}}),

	pub const set = iem_inttosymargs;
	extern fn iem_inttosymargs(*InitSymArgs, c_uint) void;

	pub const toInt = iem_symargstoint;
	extern fn iem_symargstoint(*InitSymArgs) c_uint;
};

pub const Gui = extern struct {
	obj: Object,
	glist: *GList,
	draw: ?*const IemFn,
	h: c_uint,
	w: c_uint,
	private: *Private,
	ldx: c_int,
	ldy: c_int,
	font: [m.max_string-1:0]u8,
	fsf: FontStyleFlags,
	fontsize: c_uint,
	isa: InitSymArgs,
	fcol: c_uint,
	bcol: c_uint,
	lcol: c_uint,
	snd: ?*Symbol,
	rcv: ?*Symbol,
	lab: *Symbol,
	snd_unexpanded: *Symbol,
	rcv_unexpanded: *Symbol,
	lab_unexpanded: *Symbol,
	binbufindex: c_uint,
	labelbindex: c_uint,

	pub const Private = opaque {};

	pub const Error = error {
		GuiInit,
	};

	pub fn defaultSize() c_uint {
		const current = cnv.GList.current() orelse return 0;
		return m.zoomFontHeight(current.font, 1, false) + 2 + 3;
	}

	pub fn defaultScale() Float {
		return @as(Float, @floatFromInt(defaultSize())) / 15;
	}

	pub const deinit = iemgui_free;
	extern fn iemgui_free(*Gui) void;

	pub const verifySendNotEqReceive = iemgui_verify_snd_ne_rcv;
	extern fn iemgui_verify_snd_ne_rcv(*Gui) void;

	/// Get the send, receive, and label symbols in their unexpanded "$" form.
	/// Initialize them if necessary.
	pub const getDollarSymbols = iemgui_all_sym2dollararg;
	extern fn iemgui_all_sym2dollararg(*Gui, srl: [*]*Symbol) void;

	/// Set the send, receive, and label symbols from an unexpanded "$" form.
	/// They will be converted to expanded form in the process.
	pub const setDollarSymbols = iemgui_all_dollararg2sym;
	extern fn iemgui_all_dollararg2sym(*Gui, srl: [*]*Symbol) void;

	pub const getName = iemgui_new_dogetname;
	extern fn iemgui_new_dogetname(*Gui, index: c_uint, argv: [*]Atom) ?*Symbol;

	pub const getNames = iemgui_new_getnames;
	extern fn iemgui_new_getnames(*Gui, index: c_uint, argv: ?[*]Atom) void;

	pub const loadColors = iemgui_all_loadcolors;
	extern fn iemgui_all_loadcolors(*Gui, bcol: *Atom, fcol: *Atom, lcol: *Atom) void;

	pub const setDrawFunctions = iemgui_setdrawfunctions;
	extern fn iemgui_setdrawfunctions(*Gui, w: *const DrawFunctions) void;

	/// Store saveable symbols (with spaces and dollars escaped) into srl[3] and bflcol[3].
	pub const save = iemgui_save;
	extern fn iemgui_save(*Gui, srl: [*]*Symbol, bflcol: [*]*Symbol) void;

	/// Inform GUIs that glist's zoom is about to change.  The glist will
	/// take care of x,y locations but we have to adjust width and height.
	pub const zoom = iemgui_zoom;
	extern fn iemgui_zoom(*Gui, zoom: Float) void;

	/// When creating a new GUI from menu onto a zoomed canvas, pretend to
	/// change the canvas's zoom so we'll get properly sized
	pub const newZoom = iemgui_newzoom;
	extern fn iemgui_newzoom(*Gui) void;

	pub const properties = iemgui_properties;
	extern fn iemgui_properties(*Gui, srl: [*]*Symbol) void;

	pub fn size(self: *Gui, x: *anyopaque) void {
		iemgui_size(x, self);
	}
	extern fn iemgui_size(*anyopaque, *Gui) void;

	pub fn delta(self: *Gui, x: *anyopaque, s: *Symbol, av: []const Atom)
	void {
		iemgui_delta(x, self, s, @intCast(av.len), av.ptr);
	}
	extern fn iemgui_delta(*anyopaque, *Gui, *Symbol, c_uint, [*]const Atom) void;

	pub fn pos(self: *Gui, x: *anyopaque, s: *Symbol, av: []const Atom)
	void {
		iemgui_pos(x, self, s, @intCast(av.len), av.ptr);
	}
	extern fn iemgui_pos(*anyopaque, *Gui, *Symbol, c_uint, [*]const Atom) void;

	pub fn color(self: *Gui, x: *anyopaque, s: *Symbol, av: []const Atom)
	void {
		iemgui_color(x, self, s, @intCast(av.len), av.ptr);
	}
	extern fn iemgui_color(*anyopaque, *Gui, *Symbol, c_uint, [*]const Atom) void;

	pub fn send(self: *Gui, x: *anyopaque, s: *Symbol) void {
		iemgui_send(x, self, s);
	}
	extern fn iemgui_send(*anyopaque, *Gui, *Symbol) void;

	pub fn receive(self: *Gui, x: *anyopaque, s: *Symbol) void {
		iemgui_receive(x, self, s);
	}
	extern fn iemgui_receive(*anyopaque, *Gui, *Symbol) void;

	pub fn label(self: *Gui, x: *anyopaque, s: *Symbol) void {
		iemgui_label(x, self, s);
	}
	extern fn iemgui_label(*anyopaque, *Gui, *Symbol) void;

	pub fn labelPos(self: *Gui, x: *anyopaque, s: *Symbol, av: []const Atom) void {
		iemgui_label_pos(x, self, s, @intCast(av.len), av.ptr);
	}
	extern fn iemgui_label_pos(*anyopaque, *Gui, *Symbol, c_uint, [*]const Atom) void;

	pub fn labelFont(self: *Gui, x: *anyopaque, s: *Symbol, av: []const Atom) void {
		iemgui_label_font(x, self, s, @intCast(av.len), av.ptr);
	}
	extern fn iemgui_label_font(*anyopaque, *Gui, *Symbol, c_uint, [*]const Atom) void;

	pub const SendToGui = enum(c_int) {
		auto = -1,
		never = 0,
		always = 1,
	};

	/// update the label (both internally and on the GUI)
	pub fn doLabel(
		self: *Gui,
		x: *anyopaque,
		s: *Symbol,
		send_to_gui: SendToGui,
	) void {
		iemgui_dolabel(x, self, s, @intFromEnum(send_to_gui));
	}
	extern fn iemgui_dolabel(*anyopaque, *Gui, *Symbol, c_int) void;

	pub const Scale = enum(c_uint) {
		linear = 0,
		logarithmic = 1,
	};

	pub const RangeCheck = enum(c_uint) {
		none = 0,
		toggle = 1,
		flash = 2,
	};

	pub const Steady = enum(c_int) {
		none = -1,
		jump = 0,
		steady = 1,
	};

	pub fn newDialog(
		self: *Gui, x: *anyopaque,
		objname: [*:0]const u8,
		width: Float, width_min: Float,
		height: Float, height_min: Float,
		range_min: Float, range_max: Float, range_checkmode: RangeCheck,
		scale: Scale, mode_label0: [*:0]const u8, mode_label1: [*:0]const u8,
		canloadbang: bool, steady: Steady, number: c_int,
	) void {
		iemgui_new_dialog(x, self, objname, width, width_min, height, height_min,
			range_min, range_max, @intFromEnum(range_checkmode), @intFromEnum(scale),
			mode_label0, mode_label1, @intFromBool(canloadbang),
			@intFromEnum(steady), number);
	}
	extern fn iemgui_new_dialog(
		*anyopaque, *Gui, [*:0]const u8,
		Float, Float, Float, Float, Float, Float, c_uint, c_uint,
		[*:0]const u8, [*:0]const u8, c_uint, c_int, c_int
	) void;

	pub fn setDialogAtoms(self: *Gui, argv: []Atom) void {
		iemgui_setdialogatoms(self, @intCast(argv.len), argv.ptr);
	}
	extern fn iemgui_setdialogatoms(*Gui, c_uint, [*]Atom) void;

	/// Returns a sendable/receivable bit mask.
	pub fn dialog(self: *Gui, srl: [*]*Symbol, av: []const Atom) u2 {
		return @intCast(iemgui_dialog(self, srl, @intCast(av.len), av.ptr));
	}
	extern fn iemgui_dialog(*Gui, [*]*Symbol, c_uint, [*]const Atom) c_uint;

	pub fn init(cls: *Class) Error!*Gui {
		return iemgui_new(cls) orelse Error.GuiInit;
	}
	extern fn iemgui_new(*Class) ?*Gui;
};

pub const displace = iemgui_displace;
extern fn iemgui_displace(*GObj, *GList, dx: c_int, dy: c_int) void;

pub fn setSelected(obj: *GObj, list: *GList, selected: bool) void {
	iemgui_select(obj, list, @intFromBool(selected));
}
/// use `setSelected` when directly calling within zig
pub const select = iemgui_select;
extern fn iemgui_select(*GObj, *GList, c_uint) void;

pub const delete = iemgui_delete;
extern fn iemgui_delete(*GObj, *GList) void;

pub fn setVisible(obj: *GObj, list: *GList, visible: bool) void {
	iemgui_vis(obj, list, @intFromBool(visible));
}
/// use `setVisible` when directly calling within zig
pub const vis = iemgui_vis;
extern fn iemgui_vis(*GObj, *GList, c_uint) void;
