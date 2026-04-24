const c = @import("cdef");
const m = @import("pd.zig");

const Float = m.Float;
const Sample = m.Sample;

pub const PrintHook = fn ([*:0]const u8) callconv(.c) void;

pub extern var sys_printtostderr: c_uint;
pub extern var sys_verbose: c_uint;

pub fn haveTkProc() bool {
	return (c.sys_havetkproc() != 0);
}

pub const NameList = extern struct {
	next: ?*NameList,
	string: [*:0]u8,

	/// Add a single item to a namelist. If `allow_dup` is true, duplicates
	/// may be added; otherwise they're dropped.
	pub fn append(
		self: *NameList,
		s: [*:0]const u8,
		allow_dup: bool,
	) error{OutOfMemory}!void {
		if (c.namelist_append(@ptrCast(self), s, @intFromBool(allow_dup))) |nl| {
			self.* = @as(*NameList, @ptrCast(nl)).*;
		} else {
			return error.OutOfMemory;
		}
	}

	/// Add a colon-separated list of names to a namelist
	pub fn appendFiles(self: *NameList, s: [*:0]const u8) error{OutOfMemory}!void {
		if (c.namelist_append_files(@ptrCast(self), s)) |nl| {
			self.* = @as(*NameList, @ptrCast(nl)).*;
		} else {
			return error.OutOfMemory;
		}
	}

	pub fn deinit(self: *NameList) void {
		c.namelist_free(@ptrCast(self));
	}

	pub fn get(self: *NameList, idx: usize) ?[*:0]const u8 {
		return c.namelist_get(@ptrCast(self), @intCast(idx));
	}
};

pub const Instance = extern struct {
	externlist: *NameList,
	searchpath: *NameList,
	staticpath: *NameList,
	helppath: *NameList,
	/// temp search paths ie. -path on commandline
	temppath: *NameList,
	/// audio block size for scheduler
	schedblocksize: c_uint,
	/// audio I/O block size in sample frames
	blocksize: c_uint,
	/// I/O sample rate
	dacsr: Float,
	inchannels: c_uint,
	outchannels: c_uint,
	soundout: [*]Sample,
	soundin: [*]Sample,
	/// obsolete - included for GEM??
	time_per_dsp_tick: f64,
	/// set this to override per-instance printing
	printhook: ?*const PrintHook,
	/// optional implementation-specific data for libpd, etc
	impdata: ?*anyopaque,
};
