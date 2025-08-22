const m = @import("pd.zig");

const Float = m.Float;
const Sample = m.Sample;

pub const PrintHook = fn ([*:0]const u8) callconv(.c) void;

pub extern var sys_printtostderr: c_uint;
pub extern var sys_verbose: c_uint;

pub fn haveTkProc() bool {
	return (sys_havetkproc() != 0);
}
extern fn sys_havetkproc() c_uint;

pub const NameList = extern struct {
	next: ?*NameList,
	string: [*:0]u8,

	pub fn append(self: *NameList, s: [*:0]const u8, allow_dup: bool) *NameList {
		namelist_append(self, s, @intFromBool(allow_dup));
	}
	extern fn namelist_append(*NameList, [*:0]const u8, c_uint) *NameList;

	pub const appendFiles = namelist_append_files;
	extern fn namelist_append_files(*NameList, [*:0]const u8) *NameList;

	pub const deinit = namelist_free;
	extern fn namelist_free(*NameList) void;

	pub const get = namelist_get;
	extern fn namelist_get(*NameList, c_uint) [*:0]const u8;
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
