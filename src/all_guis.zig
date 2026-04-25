const c = @import("cdef");
const m = @import("pd.zig");
const cnv = @import("canvas.zig");

const Class = @import("imp.zig").Class;
const uint = m.uint;
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
	_unused: @Int(.unsigned, @bitSizeOf(c_uint) - 31),

	pub const Style = enum(u6) {
		/// usually dejavu, or menlo on MacOS
		system = 0,
		helvetica = 1,
		times = 2,
	};

	pub fn set(self: *FontStyleFlags, n: c_int) void {
		c.iem_inttofstyle(@ptrCast(self), n);
	}

	pub fn toInt(self: *FontStyleFlags) c_int {
		c.iem_fstyletoint(@ptrCast(self));
	}
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
	_unused: @Int(.unsigned, @bitSizeOf(c_uint) - 28),

	pub fn set(self: *InitSymArgs, n: c_int) void {
		c.iem_inttosymargs(@ptrCast(self), n);
	}

	pub fn toInt(self: *InitSymArgs) c_int {
		c.iem_symargstoint(@ptrCast(self));
	}
};

pub const Gui = extern struct {
	obj: Object,
	glist: *GList,
	draw: ?*const IemFn,
	h: c_uint,
	w: c_uint,
	private: *Private,
	ld: [2]c_int,
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

	pub fn defaultSize() uint {
		const current = GList.getCurrent() orelse return 0;
		return m.zoomFontHeight(current.font, 1, false) + 2 + 3;
	}

	pub fn defaultScale() Float {
		return @as(Float, @floatFromInt(defaultSize())) / 15;
	}

	pub fn deinit(self: *Gui) void {
		c.iemgui_free(@ptrCast(self));
	}

	pub fn verifySendNotEqReceive(self: *Gui) void {
		c.iemgui_verify_snd_ne_rcv(@ptrCast(self));
	}

	/// Get the send, receive, and label symbols in their unexpanded "$" form.
	/// Initialize them if necessary.
	pub fn getDollarSymbols(self: *Gui, srl: [*]*Symbol) void {
		c.iemgui_all_sym2dollararg(@ptrCast(self), @ptrCast(srl));
	}

	/// Set the send, receive, and label symbols from an unexpanded "$" form.
	/// They will be converted to expanded form in the process.
	pub fn setDollarSymbols(self: *Gui, srl: [*]*Symbol) void {
		c.iemgui_all_dollararg2sym(@ptrCast(self), @ptrCast(srl));
	}

	pub fn getName(self: *Gui, index: uint, argv: [*]Atom) ?*Symbol {
		return @ptrCast(c.iemgui_new_dogetname(@ptrCast(self), index, @ptrCast(argv)));
	}

	pub fn getNames(self: *Gui, index: uint, argv: ?[*]Atom) void {
		c.iemgui_new_getnames(@ptrCast(self), index, @ptrCast(argv));
	}

	pub fn loadColors(self: *Gui, bcol: *Atom, fcol: *Atom, lcol: *Atom) void {
		c.iemgui_all_loadcolors(
			@ptrCast(self), @ptrCast(bcol), @ptrCast(fcol), @ptrCast(lcol));
	}

	pub fn setDrawFunctions(self: *Gui, w: *const DrawFunctions) void {
		c.iemgui_setdrawfunctions(@ptrCast(self), @ptrCast(w));
	}

	/// Store saveable symbols (spaces and dollars escaped) into srl[3] and bflcol[3].
	pub fn save(self: *Gui, srl: [*]*Symbol, bflcol: [*]*Symbol) void {
		c.iemgui_save(@ptrCast(self), @ptrCast(srl), @ptrCast(bflcol));
	}

	/// Inform GUIs that glist's zoom is about to change.  The glist will
	/// take care of x,y locations but we have to adjust width and height.
	pub fn zoom(self: *Gui, f: Float) void {
		c.iemgui_zoom(@ptrCast(self), f);
	}

	/// When creating a new GUI from menu onto a zoomed canvas, pretend to
	/// change the canvas's zoom so we'll get properly sized
	pub fn newZoom(self: *Gui) void {
		c.iemgui_newzoom(@ptrCast(self));
	}

	pub fn properties(self: *Gui, srl: [*]*Symbol) void {
		c.iemgui_properties(@ptrCast(self), @ptrCast(srl));
	}

	pub fn size(self: *Gui, x: *anyopaque) void {
		c.iemgui_size(x, @ptrCast(self));
	}

	pub fn delta(self: *Gui, x: *anyopaque, s: *Symbol, av: []const Atom) void {
		c.iemgui_delta(x, @ptrCast(self), @ptrCast(s), @intCast(av.len), @ptrCast(av.ptr));
	}

	pub fn pos(self: *Gui, x: *anyopaque, s: *Symbol, av: []const Atom) void {
		c.iemgui_pos(x, @ptrCast(self), @ptrCast(s), @intCast(av.len), @ptrCast(av.ptr));
	}

	pub fn color(self: *Gui, x: *anyopaque, s: *Symbol, av: []const Atom) void {
		c.iemgui_color(x, @ptrCast(self), @ptrCast(s), @intCast(av.len), @ptrCast(av.ptr));
	}

	pub fn send(self: *Gui, x: *anyopaque, s: *Symbol) void {
		c.iemgui_send(x, @ptrCast(self), @ptrCast(s));
	}

	pub fn receive(self: *Gui, x: *anyopaque, s: *Symbol) void {
		c.iemgui_receive(x, @ptrCast(self), @ptrCast(s));
	}

	pub fn label(self: *Gui, x: *anyopaque, s: *Symbol) void {
		c.iemgui_label(x, @ptrCast(self), @ptrCast(s));
	}

	pub fn labelPos(self: *Gui, x: *anyopaque, s: *Symbol, av: []const Atom) void {
		c.iemgui_label_pos(
			x, @ptrCast(self), @ptrCast(s), @intCast(av.len), @ptrCast(av.ptr));
	}

	pub fn labelFont(self: *Gui, x: *anyopaque, s: *Symbol, av: []const Atom) void {
		c.iemgui_label_font(
			x, @ptrCast(self), @ptrCast(s), @intCast(av.len), @ptrCast(av.ptr));
	}

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
		c.iemgui_dolabel(x, @ptrCast(self), @ptrCast(s), @intFromEnum(send_to_gui));
	}

	pub const Scale = enum(c_int) {
		linear = 0,
		logarithmic = 1,
	};

	pub const RangeCheck = enum(c_int) {
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
		c.iemgui_new_dialog(
			x, @ptrCast(self), objname,
			width, width_min,
			height, height_min,
			range_min, range_max, @intFromEnum(range_checkmode),
			@intFromEnum(scale), mode_label0, mode_label1,
			@intFromBool(canloadbang), @intFromEnum(steady), number,
		);
	}

	pub fn setDialogAtoms(self: *Gui, argv: []Atom) void {
		c.iemgui_setdialogatoms(@ptrCast(self), @intCast(argv.len), @ptrCast(argv.ptr));
	}

	pub const DialogBitMask = packed struct(u2) {
		sendable: bool,
		receivable: bool,
	};

	pub fn dialog(self: *Gui, srl: [*]*Symbol, av: []const Atom) DialogBitMask {
		return @bitCast(@as(u2, @intCast(c.iemgui_dialog(
			@ptrCast(self), @ptrCast(srl), @intCast(av.len), @ptrCast(av.ptr)))));
	}

	pub fn init(cls: *Class) error{GuiInitFail}!*Gui {
		return if (c.iemgui_new(cls)) |gui| @ptrCast(gui) else error.GuiInitFail;
	}
};

pub fn displace(gobj: *GObj, gl: *GList, dx: c_int, dy: c_int) void {
	c.iemgui_displace(@ptrCast(gobj), @ptrCast(gl), dx, dy);
}

pub fn setSelected(gobj: *GObj, gl: *GList, selected: bool) void {
	c.iemgui_select(@ptrCast(gobj), @ptrCast(gl), @intFromBool(selected));
}

/// use `setSelected` when directly calling within zig
pub fn select(gobj: *GObj, gl: *GList, selected: c_int) callconv(.c) void {
	c.iemgui_select(@ptrCast(gobj), @ptrCast(gl), selected);
}

pub fn delete(gobj: *GObj, gl: *GList) void {
	c.iemgui_delete(@ptrCast(gobj), @ptrCast(gl));
}

pub fn setVisible(gobj: *GObj, list: *GList, visible: bool) void {
	c.iemgui_vis(@ptrCast(gobj), @ptrCast(list), @intFromBool(visible));
}

/// use `setVisible` when directly calling within zig
pub fn vis(gobj: *GObj, list: *GList, visible: c_int) callconv(.c) void {
	c.iemgui_vis(@ptrCast(gobj), @ptrCast(list), visible);
}
