const c = @import("cdef");
const m = @import("pd.zig");

const Atom = m.Atom;
const BinBuf = m.BinBuf;
const Clock = m.Clock;
const Float = m.Float;
const GPointer = m.GPointer;
const GStub = m.GStub;
const Inlet = m.Inlet;
const Object = m.Object;
const OutConnect = m.OutConnect;
const Outlet = m.Outlet;
const Pd = m.Pd;
const Rect = m.Rect;
const Scalar = m.Scalar;
const Symbol = m.Symbol;
const Word = m.Word;
const uint = m.uint;

pub const io_width = 7;
pub const i_height = 3;
pub const o_height = 3;


// ----------------------------------- Array -----------------------------------
// -----------------------------------------------------------------------------
pub const Array = extern struct {
	len: c_uint,
	elemsize: c_uint,
	vec: [*]u8,
	templatesym: *Symbol,
	valid: c_uint,
	gp: GPointer,
	stub: *GStub,
};


// ---------------------------------- Editor -----------------------------------
// -----------------------------------------------------------------------------
pub const RText = opaque {
	pub fn getRect(self: *RText) Rect(c_int) {
		var x1: c_int = undefined;
		var y1: c_int = undefined;
		var x2: c_int = undefined;
		var y2: c_int = undefined;
		c.rtext_getrect(@ptrCast(self), &x1, &y1, &x2, &y2);
		return .{
			.p1 = .{ x1, y1 },
			.p2 = .{ x2, y2 },
		};
	}

	pub fn displace(self: *RText, dx: c_int, dy: c_int) void {
		c.rtext_displace(@ptrCast(self), dx, dy);
	}

	pub fn select(self: *RText, state: bool) void {
		c.rtext_select(@ptrCast(self), @intFromBool(state));
	}

	pub fn activate(self: *RText, state: bool) void {
		c.rtext_activate(@ptrCast(self), @intFromBool(state));
	}

	pub fn getTag(self: *RText) [*:0]const u8 {
		return c.rtext_gettag(@ptrCast(self));
	}

	pub fn draw(self: *RText) void {
		c.rtext_draw(@ptrCast(self));
	}

	pub fn erase(self: *RText) void {
		c.rtext_erase(@ptrCast(self));
	}
};

const GuiConnect = opaque {};

pub const UpdateHeader = extern struct {
	next: ?*UpdateHeader = null,
	flags: Flags = .{},

	pub const Flags = packed struct(c_uint) {
		/// true if array, false if glist
		array: bool = false,
		/// true if we're queued
		queued: bool = false,
		_unused: @Int(.unsigned, @bitSizeOf(c_uint) - 2) = 0,
	};
};

const Selection = extern struct {
	what: *GObj,
	next: ?*Selection,
};

pub const Editor = extern struct {
	/// update header structure
	upd: UpdateHeader,
	/// list of objects to update
	updlist: *Selection,
	/// text responder linked list
	rtext: *RText,
	/// head of the selection list
	selection: *Selection,
	/// the rtext if any that we are editing
	textedfor: *RText,
	/// object being "dragged"
	grab: *GObj,
	/// motion callback
	motionfn: ?*const GList.MotionFn,
	/// keypress callback
	keyfn: ?*const GList.KeyFn,
	/// connections to deleted objects
	connectbuf: *BinBuf,
	/// last stuff we deleted
	deleted: *BinBuf,
	/// GUI connection for filtering messages
	guiconnect: *GuiConnect,
	/// glist which owns this
	glist: *GList,
	/// pos on last mousedown or motion event
	was: [2]c_int,
	/// indices for the selected line if any
	selectline_index1: c_int,
	/// (only valid if e_selectedline is set)
	selectline_outno: c_int,
	selectline_index2: c_int,
	selectline_inno: c_int,
	selectline_tag: *OutConnect,
	flags: Flags,
	/// clock to filter GUI move messages
	clock: *Clock,
	/// pos for next move event
	new: [2]c_int,

	pub const Flags = packed struct(c_uint) {
		/// action to take on motion
		onmotion: OnMotion,
		/// true if mouse has moved since click
		lastmoved: bool,
		/// one if e_textedfor has changed
		textdirty: bool,
		/// one if a line is selected
		selectedline: bool,
		_unused: @Int(.unsigned, @bitSizeOf(c_uint) - 6),
	};

	pub const OnMotion = enum(u3) {
		/// do nothing
		none = 0,
		/// drag the selection around
		move = 1,
		/// make a connection
		connect = 2,
		/// selection region
		region = 3,
		/// send on to e_grab
		passout = 4,
		/// drag in text editor to alter selection
		dragtext = 5,
		/// drag to resize
		resize = 6,
	};

	pub const Instance = opaque {};
};


// ----------------------------------- GList -----------------------------------
// -----------------------------------------------------------------------------
/// where to put ticks on x or y axes
const Tick = extern struct {
	/// one point to draw a big tick at
	point: Float = 0,
	/// x or y increment per little tick
	inc: Float = 0,
	/// little ticks per big; 0 if no ticks to draw
	lperb: c_int = 0,
};

pub const GList = extern struct {
	/// header in case we're a glist
	obj: Object = .{},
	/// the actual data
	list: ?*GObj = null,
	/// safe pointer handler
	stub: *GStub,
	/// incremented when pointers might be stale
	valid: c_int,
	/// parent glist, supercanvas, or null
	owner: ?*GList = null,
	/// width and height in pixels (on parent, if a graph)
	pixsize: [2]c_uint = .{ 0, 0 },
	/// bounding rectangle in our own coordinates (upper-left)
	p1: [2]Float = .{ 0, 0 },
	/// bounding rectangle in our own coordinates (lower-right)
	p2: [2]Float = .{ 0, 0 },
	/// screen coordinates when toplevel (upper-left)
	screen1: [2]c_int = .{ 0, 0 },
	/// screen coordinates when toplevel (lower-right)
	screen2: [2]c_int = .{ 0, 0 },
	/// origin for GOP rectangle
	margin: [2]c_int = .{ 0, 0 },
	/// ticks marking X values
	xtick: Tick = .{},
	/// number of X coordinate labels
	nxlabels: c_uint = 0,
	/// array to hold X coordinate labels
	xlabel: [*]*Symbol = &.{},
	/// Y coordinate for X coordinate labels
	xlabely: Float = 0,
	/// ticks marking Y values
	ytick: Tick = .{},
	/// number of Y coordinate labels
	nylabels: c_uint = 0,
	/// array to hold Y coordinate labels
	ylabel: [*]*Symbol = &.{},
	/// X coordinate for Y coordinate labels
	ylabelx: Float = 0,
	/// editor structure when visible
	editor: ?*Editor = null,
	/// symbol bound here
	name: *Symbol,
	/// nominal font size in points, e.g., 10
	font: c_uint = 0,
	/// link in list of toplevels
	next: ?*GList = null,
	/// root canvases and abstractions only
	env: ?*Environment = null,
	flags: Flags = .{},
	/// zoom factor (integer zoom-in only)
	zoom: c_uint = 0,
	/// private data
	privatedata: ?*anyopaque = null,

	pub const Environment = opaque {};

	pub const Flags = packed struct(c_uint) {
		/// true if we own a window
		havewindow: bool = false,
		/// true if, moreover, it's "mapped"
		mapped: bool = false,
		/// (root canvas only:) patch has changed
		dirty: bool = false,
		/// am now loading from file
		loading: bool = false,
		/// make me visible after loading
		willvis: bool = false,
		/// edit mode
		edit: bool = false,
		/// we're inside glist_delete -- hack!
		isdeleting: bool = false,
		/// draw rectangle for graph-on-parent
		goprect: bool = false,
		/// show as graph on parent
		isgraph: bool = false,
		/// hide object-name + args when doing graph on parent
		hidetext: bool = false,
		/// private flag used in x_scalar.c
		private: bool = false,
		/// exists as part of a clone object
		isclone: bool = false,
		_unused: @Int(.unsigned, @bitSizeOf(c_uint) - 12) = 0,
	};

	pub const MotionFn = fn (*anyopaque, Float, Float, Float) callconv(.c) void;
	pub const KeyFn = fn (*anyopaque, *Symbol, Float) callconv(.c) void;

	pub const Instance = extern struct {
		/// more, semi-private stuff
		editor: *Editor.Instance,
		/// more, semi-private stuff
		template: *Template.Instance,
		/// name of file being read
		newfilename: *Symbol,
		/// directory of `newfilename`
		newdirectory: *Symbol,
		/// creation arg count for new canvas
		newargc: c_uint,
		/// creation args for new canvas
		newargv: [*]Atom,
		/// abstraction we're reloading
		reloading_abstraction: *GList,
		/// whether DSP is running
		dspstate: c_uint,
		/// counter for $0
		dollarzero: c_uint,
		/// state for dragging
		graph_lastpix: [2]Float,
		/// color for foreground
		foregroundcolor: c_uint,
		/// color for background
		backgroundcolor: c_uint,
		/// color for selection
		selectcolor: c_uint,
		/// color for Graph-On-Parent
		gopcolor: c_uint,
	};

	pub fn init(self: *GList) void {
		c.glist_init(@ptrCast(self));
	}

	pub fn add(self: *GList, g: *GObj) void {
		c.glist_add(@ptrCast(self), @ptrCast(g));
	}

	pub fn clear(self: *GList) void {
		c.glist_clear(@ptrCast(self));
	}

	pub fn getCanvas(self: *GList) *GList {
		return @ptrCast(@alignCast(c.glist_getcanvas(@ptrCast(self)).?));
	}

	pub fn isSelected(self: *GList, g: *GObj) bool {
		return (c.glist_isselected(@ptrCast(self), @ptrCast(g)) != 0);
	}

	pub fn select(self: *GList, g: *GObj) void {
		c.glist_select(@ptrCast(self), @ptrCast(g));
	}

	pub fn deselect(self: *GList, g: *GObj) void {
		c.glist_deselect(@ptrCast(self), @ptrCast(g));
	}

	pub fn noSelect(self: *GList) void {
		c.glist_noselect(@ptrCast(self));
	}

	pub fn selectAll(self: *GList) void {
		c.glist_selectall(@ptrCast(self));
	}

	pub fn delete(self: *GList, g: *GObj) void {
		c.glist_delete(@ptrCast(self), @ptrCast(g));
	}

	/// Remake text buffer
	pub fn retext(self: *GList, obj: *Object) void {
		c.glist_retext(@ptrCast(self), @ptrCast(obj));
	}

	pub fn grab(
		self: *GList, g: *GObj,
		motion: ?*const MotionFn, key: ?*const KeyFn,
		xpos: c_int, ypos: c_int,
	) void {
		c.glist_grab(
			@ptrCast(self), @ptrCast(g),
			@ptrCast(motion), @ptrCast(key),
			xpos, ypos,
		);
	}

	pub fn isVisible(self: *GList) bool {
		return (c.glist_isvisible(@ptrCast(self)) != 0);
	}

	pub fn isTopLevel(self: *GList) bool {
		return (c.glist_istoplevel(@ptrCast(self)) != 0);
	}

	/// Find the graph most recently added to this glist.
	/// If none exists, return null.
	pub fn findGraph(self: *GList) ?*GList {
		return @ptrCast(c.glist_findgraph(@ptrCast(self)));
	}

	/// Nominal font size in points, e.g., 10
	pub fn getFont(self: *GList) uint {
		return @intCast(c.glist_getfont(@ptrCast(self)));
	}

	pub fn fontWidth(self: *GList) uint {
		return @intCast(c.glist_fontwidth(@ptrCast(self)));
	}

	pub fn fontHeight(self: *GList) uint {
		return @intCast(c.glist_fontheight(@ptrCast(self)));
	}

	pub fn getZoom(self: *GList) uint {
		return @intCast(c.glist_getzoom(@ptrCast(self)));
	}

	pub fn sort(self: *GList) void {
		c.glist_sort(@ptrCast(self));
	}

	pub fn read(self: *GList, filename: *Symbol, format: *Symbol) void {
		c.glist_read(@ptrCast(self), @ptrCast(filename), @ptrCast(format));
	}

	pub fn mergeFile(self: *GList, filename: *Symbol, format: *Symbol) void {
		c.glist_mergefile(@ptrCast(self), @ptrCast(filename), @ptrCast(format));
	}

	pub fn pixelsToX(self: *GList, xpix: Float) Float {
		return c.glist_pixelstox(@ptrCast(self), xpix);
	}

	pub fn pixelsToY(self: *GList, ypix: Float) Float {
		return c.glist_pixelstoy(@ptrCast(self), ypix);
	}

	/// convert a coordinate value to a pixel location in window
	pub fn toPixels(self: *const GList, val: @Vector(2, Float)) @Vector(2, Float) {
		const FVec2 = @Vector(2, Float);
		const rect: Rect(Float) = .{ .p1 = self.p1, .p2 = self.p2 };

		if (!self.flags.isgraph) {
			const zoom: Float = @floatFromInt(self.zoom);
			return (val - rect.p1) * FVec2{ zoom, zoom } / rect.size();
		}
		if (self.flags.havewindow) {
			const screen_size: FVec2 = @floatFromInt((Rect(c_int){
				.p1 = self.screen1,
				.p2 = self.screen2,
			}).size());
			return screen_size * (val - rect.p1) / rect.size();
		}
		if (self.owner) |owner| {
			const zoom: Float = @floatFromInt(self.zoom);
			const size: FVec2 = @floatFromInt(@as(@Vector(2, c_uint), self.pixsize));
			const p1: FVec2 = @floatFromInt(self.obj.pos(owner));
			const p2 = p1 + FVec2{ zoom, zoom } * size;

			return p1 + (p2 - p1) * (val - rect.p1) / rect.size();
		} else {
			m.post.bug("GList.toPixels", .{});
			return val;
		}
	}

	pub fn dpixToDx(self: *GList, dxpix: Float) Float {
		return c.glist_dpixtodx(@ptrCast(self), dxpix);
	}

	pub fn dpixToDy(self: *GList, dypix: Float) Float {
		return c.glist_dpixtody(@ptrCast(self), dypix);
	}

	pub fn nextXY(self: *GList, xval: *c_int, yval: *c_int) void {
		c.glist_getnextxy(@ptrCast(self), xval, yval);
	}

	/// Call `glist_addglist()` from a Pd message.
	pub fn gList(self: *GList, s: *Symbol, av: []Atom) void {
		c.glist_glist(@ptrCast(self), @ptrCast(s), @intCast(av.len), @ptrCast(av.ptr));
	}

	/// Make a new glist and add it to this glist.
	/// It will appear as a "graph", not a text object.
	pub fn addGList(
		self: *GList, sym: *Symbol,
		x1: Float, y1: Float, x2: Float, y2: Float,
		px1: Float, py1: Float, px2: Float, py2: Float,
	) error{AddGListFail}!*GList {
		return if (c.glist_addglist(
			@ptrCast(self), @ptrCast(sym),
			x1, y1, x2, y2,
			px1, py1, px2, py2,
		)) |gl| @ptrCast(gl) else error.AddGListFail;
	}

	pub fn arrayDialog(
		self: *GList, name: *Symbol,
		size: Float, saveit: Float, newgraph: Float,
	) void {
		c.glist_arraydialog(@ptrCast(self), @ptrCast(name), size, saveit, newgraph);
	}

	/// Write all "scalars" in a glist to a binbuf.
	pub fn writeToBinbuf(self: *GList, wholething: bool) error{WriteToBinBufFail}!*BinBuf {
		return if (c.glist_writetobinbuf(@ptrCast(self), @intFromBool(wholething))) |bb|
			@ptrCast(bb)
		else error.WriteToBinBufFail;
	}

	pub fn isGraph(self: *GList) bool {
		return (c.glist_isgraph(@ptrCast(self)) != 0);
	}

	pub fn redraw(self: *GList) void {
		c.glist_redraw(@ptrCast(self));
	}

	/// Draw inlets and outlets for a text object or for a graph.
	pub fn drawIoFor(
		self: *GList, ob: *Object,
		first_time: bool,
		tag: [*:0]const u8,
		x1: c_int, y1: c_int,
		x2: c_int, y2: c_int,
	) void {
		c.glist_drawiofor(
			@ptrCast(self), @ptrCast(ob), @intFromBool(first_time), tag, x1, y1, x2, y2);
	}

	pub fn eraseIoFor(self: *GList, ob: *Object, tag: [*:0]const u8) void {
		c.glist_eraseiofor(@ptrCast(self), @ptrCast(ob), tag);
	}

	pub fn createEditor(self: *GList) void {
		c.canvas_create_editor(@ptrCast(self));
	}

	pub fn destroyEditor(self: *GList) void {
		c.canvas_destroy_editor(@ptrCast(self));
	}

	pub fn deleteLinesFor(self: *GList, ob: *Object) void {
		c.canvas_deletelinesfor(@ptrCast(self), @ptrCast(ob));
	}

	pub fn makeFilename(self: *const GList, file: [*:0]const u8, buf: []u8) void {
		c.canvas_makefilename(@ptrCast(self), file, buf.ptr, @intCast(buf.len));
	}

	pub fn dir(self: *const GList) *Symbol {
		return @ptrCast(c.canvas_getdir(@ptrCast(self)));
	}

	/// Read text from a "properties" window, called from a gfxstub set
	/// up in `scalar_properties()`. We try to restore the object; if successful
	/// we either copy the data from the new scalar to the old one in place
	/// (if their templates match) or else delete the old scalar and put the new
	/// thing in its place on the list.
	pub fn dataProperties(self: *GList, sc: *Scalar, b: *BinBuf) void {
		c.canvas_dataproperties(@ptrCast(self), @ptrCast(sc), @ptrCast(b));
	}

	/// Utility function to read a file, looking first down the canvas's search
	/// path (set with "declare" objects in the patch and recursively in calling
	/// patches), then down the system one.  The filename is the concatenation of
	/// `name` and `ext`. `name` may be absolute, or may be relative with
	/// slashes. If anything can be opened, the true directory
	/// is put in the buffer dirresult (provided by caller), which should
	/// be `size` bytes. The `nameresult` pointer will be set somewhere in
	/// the interior of `dirresult` and will give the file basename (with
	/// slashes trimmed). If `bin` is set, a 'binary' open is
	/// attempted, otherwise ASCII (this only matters on Microsoft.)
	/// If `self` is null, the file is sought in the directory "." or in the
	/// global path.
	pub fn open(
		self: ?*const GList,
		name: [*:0]const u8,
		ext: [*:0]const u8,
		dirresult: [*:0]u8,
		nameresult: *[*:0]u8,
		size: c_uint,
		bin: bool,
	) error{GListOpenFail}!uint {
		const fd = c.canvas_open(
			@ptrCast(self), name, ext, dirresult, nameresult, size, @intFromBool(bin));
		return if (fd < 0) error.GListOpenFail else @intCast(fd);
	}

	pub fn sampleRate(self: *GList) Float {
		return c.canvas_getsr(@ptrCast(self));
	}

	pub fn signalLength(self: *GList) uint {
		return @intCast(c.canvas_getsignallength(@ptrCast(self)));
	}

	pub fn setArgs(av: []const Atom) void {
		c.canvas_setargs(@intCast(av.len), @ptrCast(av.ptr));
	}

	pub fn args() []Atom {
		var ac: c_int = undefined;
		var av: [*]c.t_atom = undefined;
		c.canvas_getargs(&ac, &av);
		return @ptrCast(av[0..@intCast(ac)]);
	}

	pub fn setUndoState(
		self: *GList, x: *Pd, s: *Symbol,
		undo: []const Atom, redo: []const Atom,
	) void {
		c.pd_undo_set_objectstate(@ptrCast(self), @ptrCast(x), @ptrCast(s),
			@intCast(undo.len), @ptrCast(@constCast(undo.ptr)),
			@intCast(redo.len), @ptrCast(@constCast(redo.ptr)),
		);
	}

	pub fn getCurrent() ?*GList {
		return @ptrCast(@alignCast(c.canvas_getcurrent()));
	}

	pub fn getEnv(self: *GList) *Environment {
		return c.canvas_getenv(@ptrCast(self));
	}

	pub fn realizeDollar(self: *GList, s: *Symbol) *Symbol {
		return @ptrCast(c.canvas_realizedollar(@ptrCast(self), @ptrCast(s)));
	}

	/// Mark a glist dirty or clean.
	pub fn setDirty(self: *GList, state: bool) void {
		c.canvas_dirty(@ptrCast(self), @floatFromInt(@intFromBool(state)));
	}

	pub fn fixLinesFor(self: *GList, ob: *Object) void {
		c.canvas_fixlinesfor(@ptrCast(self), @ptrCast(ob));
	}

	/// Find the RText that goes with a text item. Return `null` if the
	/// text item is invisible, either because the glist itself is, or because
	/// the item is in a GOP subpatch and its (x,y) origin is outside the GOP
	/// area (Or if it's within a nested GOP which itself isn't visible). In
	/// some cases, the RText is created in order to check the bounds rectangle,
	/// in which case it was created even if invisible. But since `gobj_shouldvis()`
	/// first checks the upper right corner (x,y) before creating the RText, the
	/// majority of invisible 'text' objects never get RTexts created for them.
	pub fn getRText(
		self: *GList,
		who: *Object,
		/// whether we're being called within `gobj_shouldvis`,
		/// in which case we can't just go call `shouldvis` back from here.
		really: bool,
	) ?*RText {
		return @ptrCast(c.glist_getrtext(
			@ptrCast(self), @ptrCast(who), @intFromBool(really),
		));
	}
};


// ----------------------------------- GObj ------------------------------------
// -----------------------------------------------------------------------------
pub const GObj = extern struct {
	pd: Pd = .{},
	next: ?*GObj = null,

	pub fn getRect(
		self: *GObj, owner: *GList,
		x1: *c_int, y1: *c_int,
		x2: *c_int, y2: *c_int,
	) void {
		c.gobj_getrect(@ptrCast(self), @ptrCast(owner), x1, y1, x2, y2);
	}

	pub fn displace(self: *GObj, owner: *GList, dx: c_int, dy: c_int) void {
		c.gobj_displace(@ptrCast(self), @ptrCast(owner), dx, dy);
	}

	pub fn select(self: *GObj, owner: *GList, state: bool) void {
		c.gobj_select(@ptrCast(self), @ptrCast(owner), @intFromBool(state));
	}

	pub fn activate(self: *GObj, owner: *GList, state: bool) void {
		c.gobj_activate(@ptrCast(self), @ptrCast(owner), @intFromBool(state));
	}

	pub fn delete(self: *GObj, owner: *GList) void {
		c.gobj_delete(@ptrCast(self), @ptrCast(owner));
	}

	pub fn vis(self: *GObj, owner: *GList, state: bool) void {
		c.gobj_vis(@ptrCast(self), @ptrCast(owner), @intFromBool(state));
	}

	pub fn click(
		self: *GObj, glist: *GList,
		xpix: c_int, ypix: c_int,
		shift: bool, alt: bool, dblclk: bool, doit: bool,
	) bool {
		return c.gobj_click(
			@ptrCast(self), @ptrCast(glist),
			xpix, ypix,
			@intFromBool(shift), @intFromBool(alt),
			@intFromBool(dblclk), @intFromBool(doit),
		);
	}

	pub fn save(self: *GObj, b: *BinBuf) void {
		c.gobj_save(@ptrCast(self), @ptrCast(b));
	}

	pub fn shouldVis(self: *GObj, glist: *GList) bool {
		return (c.gobj_shouldvis(@ptrCast(self), @ptrCast(glist)) != 0);
	}
};


// ------------------------------- LineTraverser -------------------------------
// -----------------------------------------------------------------------------
pub const LineTraverser = extern struct {
	gl: *GList,
	ob: ?*Object = null,
	nout: c_uint = 0,
	outno: c_int = 0,
	ob2: *Object = undefined,
	outlet: ?*Outlet = null,
	inlet: ?*Inlet = null,
	nin: c_int = 0,
	inno: c_int = 0,
	p11: [2]c_int = .{ 0, 0 },
	p12: [2]c_int = .{ 0, 0 },
	p21: [2]c_int = .{ 0, 0 },
	p22: [2]c_int = .{ 0, 0 },
	l1: [2]c_int = .{ 0, 0 },
	l2: [2]c_int = .{ 0, 0 },
	nextoc: ?*OutConnect = null,
	nextoutno: c_int = 0,

	pub fn init(gl: *GList) LineTraverser {
		return .{ .gl = gl };
	}

	pub fn next(self: *LineTraverser) ?*OutConnect {
		return @ptrCast(c.linetraverser_next(@ptrCast(self)));
	}

	pub fn skipObject(self: *LineTraverser) void {
		c.linetraverser_skipobject(@ptrCast(self));
	}
};


// --------------------------------- LoadBang ----------------------------------
// -----------------------------------------------------------------------------
pub const LoadBang = enum(u2) {
	/// loaded and connected to parent patch
	load = 0,
	/// loaded but not yet connected to parent patch
	init = 1,
	/// about to close
	close = 2,
};


// --------------------------------- Template ----------------------------------
// -----------------------------------------------------------------------------
pub const PdStruct = opaque {};
pub const DataSlot = extern struct {
	type: c_int,
	name: *Symbol,
	arraytemplate: *Symbol,
};

pub const Template = extern struct {
	pdobj: Pd,
	list: *PdStruct,
	sym: *Symbol,
	n: c_uint,
	vec: *DataSlot,
	next: ?*Template,

	pub const Instance = opaque {};
};


// ---------------------------------- Widgets ----------------------------------
// -----------------------------------------------------------------------------
pub const GetRectFn = fn (
	*GObj, *GList,
	x1: *c_int, y1: *c_int,
	x2: *c_int, y2: *c_int,
) callconv(.c) void;

pub const DisplaceFn = fn (
	*GObj, *GList,
	dx: c_int, dy: c_int,
) callconv(.c) void;

pub const ClickFn = fn (
	*GObj, *GList,
	xpix: c_int, ypix: c_int,
	shift: c_int, alt: c_int, dbl_click: c_int, doit: c_int,
) callconv(.c) c_int;

pub const VisFn = fn (*GObj, *GList, state: c_int) callconv(.c) void;
pub const SelectFn = fn (*GObj, *GList, state: c_int) callconv(.c) void;
pub const ActivateFn = fn (*GObj, *GList, state: c_int) callconv(.c) void;
pub const DeleteFn = fn (*GObj, *GList) callconv(.c) void;

/// Functions used to define graphical behavior for `GObj`s.
/// We don't use Pd methods because Pd's typechecking can't specify the
/// types of pointer arguments. Also it's more convenient this way, since
/// every "patchable" object can just get the "text" behaviors.
pub const WidgetBehavior = extern struct {
	getrect: ?*const GetRectFn = null,
	displace: ?*const DisplaceFn = null,
	select: ?*const SelectFn = null,
	activate: ?*const ActivateFn = null,
	delete: ?*const DeleteFn = null,
	vis: ?*const VisFn = null,
	click: ?*const ClickFn = null,
};

pub const parent = struct {
	pub const GetRectFn = fn (
		*GObj, *GList, *Word, *Template, Float, Float, *c_int, *c_int, *c_int, *c_int,
	) callconv(.c) void;

	pub const DisplaceFn = fn (
		*GObj, *GList, *Word, *Template, Float, Float, c_int, c_int,
	) callconv(.c) void;

	pub const SelectFn = fn (
		*GObj, *GList, *Word, *Template, Float, Float, c_int,
	) callconv(.c) void;

	pub const ActivateFn = fn (
		*GObj, *GList, *Word, *Template, Float, Float, c_int,
	) callconv(.c) void;

	pub const VisFn = fn (
		*GObj, *GList, *Word, *Template, Float, Float, c_int,
	) callconv(.c) void;

	pub const ClickFn = fn (
		*GObj, *GList, *Word, *Template, *Scalar, *Array,
		Float, Float, c_int, c_int, c_int, c_int, c_int, c_int,
	) callconv(.c) c_int;

	pub const WidgetBehavior = extern struct {
		getrect: ?*const parent.GetRectFn = null,
		displace: ?*const parent.DisplaceFn = null,
		select: ?*const parent.SelectFn = null,
		activate: ?*const parent.ActivateFn = null,
		vis: ?*const parent.VisFn = null,
		click: ?*const parent.ClickFn = null,
	};
};
