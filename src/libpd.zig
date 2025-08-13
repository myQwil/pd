pub const pd = @import("pd");
const Atom = pd.Atom;
const Instance = pd.Instance;

const std = @import("std");
const testing = std.testing;

const Error = error {
	AlreadyInitialized,
	RingBuffer,
	InitAudio,
	OpenFile,
	ProcessFloat,
	ProcessShort,
	ProcessDouble,
	ProcessRawFloat,
	ProcessRawShort,
	ProcessRawDouble,
	ArrayNotFound,
	ArrayOutOfBounds,
	ReceiverNotFound,
	MessageTooLong,
	Bind,
	StartGui,
	NewInstance,
};


// ------------------------------ initializing pd ------------------------------
// -----------------------------------------------------------------------------

pub const Base = struct {
	queued: bool,

	/// Initialize Pd and set up the audio processing.
	/// Note: sets `SIGFPE` handler to keep bad pd patches from crashing due to divide
	/// by 0, set any custom handling after calling this function.
	pub fn init(
		in_channels: c_uint,
		out_channels: c_uint,
		sample_rate: c_uint,
		is_queued: bool,
	) Error!Base {
		if (is_queued) {
			switch (libpd_queued_init()) {
				-1 => return Error.AlreadyInitialized,
				-2 => return Error.RingBuffer,
				else => {},
			}
			errdefer libpd_queued_release();
			libpd_set_queued_printhook(libpd_print_concatenator);
		} else {
			if (libpd_init() != 0) {
				return Error.AlreadyInitialized;
			}
			libpd_set_printhook(libpd_print_concatenator);
		}
		if (libpd_init_audio(in_channels, out_channels, sample_rate) != 0) {
			return Error.InitAudio;
		}
		return Base{ .queued = is_queued };
	}
	extern fn libpd_init() c_int;
	extern fn libpd_queued_init() c_int;
	extern fn libpd_set_printhook(?*const PrintHook) void;
	extern fn libpd_set_queued_printhook(?*const PrintHook) void;
	extern fn libpd_print_concatenator([*:0]const u8) void;
	extern fn libpd_init_audio(c_uint, c_uint, c_uint) c_int;

	test init {
		try init(0, 2, 48000, false);
		try testing.expectError(Error.AlreadyInitialized, init(0, 2, 48000, false));
	}

	/// Free the ring buffer if we're using it
	pub fn close(self: *const Base) void {
		computeAudio(false);
		if (self.queued) {
			libpd_queued_release();
		}
	}
	extern fn libpd_queued_release() void;
};

/// Clear the current pd search path.
extern fn libpd_clear_search_path() void;
pub const clearSearchPath = libpd_clear_search_path;

/// Add a path to the libpd search paths.
/// Relative paths are relative to the current working directory.
///
/// Unlike desktop pd, *no* search paths are set by default (ie. extra)
pub fn addToSearchPath(path: [*:0]const u8) void {
	libpd_add_to_search_path(path);
}
extern fn libpd_add_to_search_path([*:0]const u8) void;


// ------------------------------ opening patches ------------------------------
// -----------------------------------------------------------------------------

pub const Patch = struct {
	/// Patch handle pointer.
	handle: *anyopaque,
	/// Unique $0 patch ID
	dollar_zero: c_uint,

	/// Open a patch by filename and parent dir path.
	pub fn fromFile(name: [*:0]const u8, dir: [*:0]const u8) Error!Patch {
		return if (libpd_openfile(name, dir)) |file| Patch{
			.handle = file,
			.dollar_zero = libpd_getdollarzero(file),
		} else Error.OpenFile;
	}
	extern fn libpd_openfile([*:0]const u8, [*:0]const u8) ?*anyopaque;
	extern fn libpd_getdollarzero(*anyopaque) c_uint;

	/// Close a patch by patch handle pointer.
	pub fn close(self: *const Patch) void {
		libpd_closefile(self.handle);
	}
	extern fn libpd_closefile(*anyopaque) void;
};


// ----------------------------- audio processing ------------------------------
// -----------------------------------------------------------------------------

pub fn computeAudio(state: bool) void {
	_ = libpd_start_message(1);
	addFloat(@floatFromInt(@intFromBool(state)));
	_ = libpd_finish_message("pd", "dsp");
}

/// Return pd's fixed block size: the number of sample frames per 1 pd tick.
pub const blockSize = libpd_blocksize;
extern fn libpd_blocksize() c_uint;

/// Process interleaved float samples from inBuffer -> libpd -> outBuffer
///
/// Buffer sizes are based on # of ticks and channels where:
///     `size = ticks * libpd_blocksize() * (in/out)channels`.
pub fn processFloat(
	ticks: c_uint,
	in_buffer: ?[*]const f32,
	out_buffer: ?[*]f32,
) Error!void {
	if (libpd_process_float(ticks, in_buffer, out_buffer) != 0) {
		return Error.ProcessFloat;
	}
}
extern fn libpd_process_float(c_uint, ?[*]const f32, ?[*]f32) c_int;

/// Process interleaved short samples from inBuffer -> libpd -> outBuffer.
///
/// Buffer sizes are based on # of ticks and channels where:
///     `size = ticks * libpd_blocksize() * (in/out)channels`.
///
/// Float samples are converted to short by multiplying by 32767 and casting,
/// so any values received from pd patches beyond -1 to 1 will result in garbage.
///
/// Note: for efficiency, does *not* clip input
pub fn processShort(
	ticks: c_uint,
	in_buffer: ?[*]const i16,
	out_buffer: ?[*]i16,
) Error!void {
	if (libpd_process_short(ticks, in_buffer, out_buffer) != 0) {
		return Error.ProcessShort;
	}
}
extern fn libpd_process_short(c_uint, ?[*]const c_short, ?[*]c_short) c_int;

/// Process interleaved double samples from inBuffer -> libpd -> outBuffer.
///
/// Buffer sizes are based on # of ticks and channels where:
///     `size = ticks * libpd_blocksize() * (in/out)channels`.
///
/// Note: only full-precision when compiled with `PD_FLOATSIZE=64`
pub fn processDouble(
	ticks: c_uint,
	in_buffer: ?[*]const f64,
	out_buffer: ?[*]f64,
) Error!void {
	if (libpd_process_short(ticks, in_buffer, out_buffer) != 0) {
		return Error.ProcessDouble;
	}
}
extern fn libpd_process_double(c_uint, ?[*]const f64, ?[*]f64) c_int;

/// Process non-interleaved float samples from inBuffer -> libpd -> outBuffer.
///
/// Copies buffer contents to/from libpd without striping.
///
/// Buffer sizes are based on a single tick and # of channels where:
///     `size = libpd_blocksize() * (in/out)channels`.
pub fn processRawFloat(in_buffer: ?[*]const f32, out_buffer: ?[*]f32) Error!void {
	if (libpd_process_raw(in_buffer, out_buffer) != 0) {
		return Error.ProcessRawFloat;
	}
}
extern fn libpd_process_raw(?[*]const f32, ?[*]f32) c_int;

/// Process non-interleaved short samples from inBuffer -> libpd -> outBuffer.
///
/// Copies buffer contents to/from libpd without striping.
///
/// Buffer sizes are based on a single tick and # of channels where:
///     `size = libpd_blocksize() * (in/out)channels`.
///
/// Float samples are converted to short by multiplying by 32767 and casting,
/// so any values received from pd patches beyond -1 to 1 will result in garbage.
///
/// Note: for efficiency, does *not* clip input.
pub fn processRawShort(in_buffer: ?[*]const i16, out_buffer: ?[*]i16) Error!void {
	if (libpd_process_raw_short(in_buffer, out_buffer) != 0) {
		return Error.ProcessRawShort;
	}
}
extern fn libpd_process_raw_short(?[*]const i16, ?[*]i16) c_int;

/// Process non-interleaved double samples from inBuffer -> libpd -> outBuffer.
///
/// Copies buffer contents to/from libpd without striping.
///
/// Buffer sizes are based on a single tick and # of channels where:
///     `size = libpd_blocksize() * (in/out)channels`.
///
/// Note: only full-precision when compiled with `PD_FLOATSIZE=64`.
pub fn processRawDouble(in_buffer: ?[*]const f64, out_buffer: ?[*]f64) Error!void {
	if (libpd_process_raw_double(in_buffer, out_buffer) != 0) {
		return Error.ProcessRawDouble;
	}
}
extern fn libpd_process_raw_double(?[*]const f64, ?[*]f64) c_int;


// ------------------------------- array access --------------------------------
// -----------------------------------------------------------------------------

/// Get the size of an array by name.
pub fn arraySize(name: [*:0]const u8) Error!c_uint {
	const size = libpd_arraysize(name);
	return if (size < 0) Error.ArrayNotFound else @intCast(size);
}
extern fn libpd_arraysize([*:0]const u8) c_int;

/// (re)size an array by name; sizes <= 0 are clipped to 1.
pub fn resizeArray(name: [*:0]const u8, size: c_ulong) Error!void {
	if (libpd_resize_array(name, size) != 0) {
		return Error.ArrayNotFound;
	}
}
extern fn libpd_resize_array([*:0]const u8, c_ulong) c_int;

/// Read values from named src array and write into `dest` starting at an offset.
///
/// Note: performs no bounds checking on `dest`.
pub fn readArray(dest: []f32, name: [*:0]const u8, offset: c_uint) Error!void {
	return switch (libpd_read_array(dest.ptr, name, offset, @intCast(dest.len))) {
		-1 => Error.ArrayNotFound,
		-2 => Error.ArrayOutOfBounds,
		else => {},
	};
}
extern fn libpd_read_array([*]f32, [*:0]const u8, c_uint, c_uint) c_int;

/// Read values from `src` and write into named dest array starting at an offset.
///
/// Note: performs no bounds checking on `src`.
pub fn writeArray(name: [*:0]const u8, offset: c_uint, src: []const f32) Error!void {
	return switch (libpd_write_array(name, offset, src.ptr, @intCast(src.len))) {
		-1 => Error.ArrayNotFound,
		-2 => Error.ArrayOutOfBounds,
		else => {},
	};
}
extern fn libpd_write_array([*:0]const u8, c_uint, [*]const f32, c_uint) c_int;

/// Read values from named src array and write into `dest` starting at an offset.
///
/// Note: performs no bounds checking on `dest`.
///
/// Note: only full-precision when compiled with `PD_FLOATSIZE=64`.
///
/// Double-precision variant of libpd_read_array().
pub fn readArrayDouble(dest: []f64, name: [*:0]const u8, offset: c_uint) Error!void {
	const res = libpd_read_array_double(dest.ptr, name, offset, @intCast(dest.len));
	return switch (res) {
		-1 => Error.ArrayNotFound,
		-2 => Error.ArrayOutOfBounds,
		else => {},
	};
}
extern fn libpd_read_array_double([*]f64, [*:0]const u8, c_uint, c_uint) c_int;

/// Read values from `src` and write into named dest array starting at an offset.
///
/// Note: performs no bounds checking on `src`.
///
/// Note: only full-precision when compiled with `PD_FLOATSIZE=64`.
///
/// Double-precision variant of libpd_write_array().
pub fn writeArrayDouble(name: [*:0]const u8, offset: c_uint, src: []const f64) Error!void {
	const res = libpd_write_array_double(name, offset, src.ptr, @intCast(src.len));
	return switch (res) {
		-1 => Error.ArrayNotFound,
		-2 => Error.ArrayOutOfBounds,
		else => {},
	};
}
extern fn libpd_write_array_double([*:0]const u8, c_uint, [*]const f64, c_uint) c_int;


// -------------------------- sending messages to pd ---------------------------
// -----------------------------------------------------------------------------

/// Send a bang to a destination receiver.
///
/// Ex: `sendBang("foo")` will send a bang to [s foo] on the next tick.
pub fn sendBang(recv: [*:0]const u8) Error!void {
	if (libpd_bang(recv) != 0) {
		return Error.ReceiverNotFound;
	}
}
extern fn libpd_bang([*:0]const u8) c_int;

/// Send a float to a destination receiver.
///
/// Ex: `sendFloat("foo", 1)` will send a 1.0 to [s foo] on the next tick.
pub fn sendFloat(recv: [*:0]const u8, x: f32) Error!void {
	if (libpd_float(recv, x) != 0) {
		return Error.ReceiverNotFound;
	}
}
extern fn libpd_float([*:0]const u8, f32) c_int;

/// Send a double to a destination receiver.
///
/// Ex: `sendDouble("foo", 1.1)` will send a 1.1 to [s foo] on the next tick
///
/// Note: only full-precision when compiled with `PD_FLOATSIZE=64`.
pub fn sendDouble(recv: [*:0]const u8, x: f64) Error!void {
	if (libpd_double(recv, x) != 0) {
		return Error.ReceiverNotFound;
	}
}
extern fn libpd_double([*:0]const u8, f64) c_int;

/// Send a symbol to a destination receiver.
/// Ex: `sendSymbol("foo", "bar")` will send "bar" to [s foo] on the next tick.
pub fn sendSymbol(recv: [*:0]const u8, s: [*:0]const u8) Error!void {
	if (libpd_symbol(recv, s) != 0) {
		return Error.ReceiverNotFound;
	}
}
extern fn libpd_symbol([*:0]const u8, [*:0]const u8) c_int;


// ------------ sending compound messages: sequenced function calls ------------
// -----------------------------------------------------------------------------

/// Start composition of a new list or typed message of up to max element length.
/// Messages can be of a smaller length as max length is only an upper bound.
///
/// Note: no cleanup is required for unfinished messages.
pub fn startMessage(maxlen: c_uint) Error!void {
	if (libpd_start_message(maxlen) != 0) {
		return Error.MessageTooLong;
	}
}
extern fn libpd_start_message(maxlen: c_uint) c_int;

test startMessage {
	try testing.expectError(Error.MessageTooLong, startMessage(1234567890));
	try startMessage(1);
}

/// Add a float to the current message in progress.
pub const addFloat = libpd_add_float;
extern fn libpd_add_float(f32) void;

/// Add a double to the current message in progress.
///
/// Note: only full-precision when compiled with `PD_FLOATSIZE=64`.
pub const addDouble = libpd_add_double;
extern fn libpd_add_double(f64) void;

/// add a symbol to the current message in progress
pub const addSymbol = libpd_add_symbol;
extern fn libpd_add_symbol([*:0]const u8) void;

/// Finish current message and send as a list to a destination receiver
///
/// Ex: send `[list 1 2 bar(` to `[s foo]` on the next tick with:
/// ```
///     startMessage(3);
///     addFloat(1);
///     addFloat(2);
///     addSymbol("bar");
///     finishList("foo");
/// ```
pub fn finishList(recv: [*:0]const u8) Error!void {
	if (libpd_finish_list(recv) != 0) {
		return Error.ReceiverNotFound;
	}
}
extern fn libpd_finish_list([*:0]const u8) c_int;

/// Finish current message and send as a typed message to a destination receiver.
///
/// Note: typed message handling currently only supports up to 4 elements.
/// Internally, additional elements may be ignored
///
/// Ex: send `[; pd dsp 1(` on the next tick with:
/// ```
///     startMessage(1);
///     addFloat(1);
///     finishMessage("pd", "dsp");
/// ```
pub fn finishMessage(recv: [*:0]const u8, msg: [*:0]const u8) Error!void {
	if (libpd_finish_message(recv, msg) != 0) {
		return Error.ReceiverNotFound;
	}
}
extern fn libpd_finish_message([*:0]const u8, [*:0]const u8) c_int;


// ------------------- sending compound messages: atom array -------------------
// -----------------------------------------------------------------------------

/// Write a float value to the given atom.
pub const setFloat = libpd_set_float;
extern fn libpd_set_float(*Atom, f32) void;

/// Write a double value to the given atom.
/// Note: only full-precision when compiled with `PD_FLOATSIZE=64`.
pub const setDouble = libpd_set_double;
extern fn libpd_set_double(*Atom, f64) void;

/// Write a symbol value to the given atom.
pub fn setSymbol(a: *Atom, s: [*:0]const u8) void {
	libpd_set_symbol(a, s);
}
extern fn libpd_set_symbol(*Atom, [*:0]const u8) void;

/// Send an atom array of a given length as a list to a destination receiver.
///
/// Ex: send [list 1 2 bar( to [r foo] on the next tick with:
/// ```
///     var v: [3]Atom = undefined;
///     setFloat(&v[0], 1);
///     setFloat(&v[1], 2);
///     setSymbol(&v[2], "bar");
///     sendList("foo", &v);
/// ```
pub fn sendList(recv: [*:0]const u8, av: []Atom) Error!void {
	if (libpd_list(recv, av.len, av.ptr) != 0) {
		return Error.ReceiverNotFound;
	}
}
extern fn libpd_list([*:0]const u8, c_uint, [*]Atom) c_int;


pub fn sendMessage(recv: [*:0]const u8, msg: [*:0]const u8, av: []Atom) Error!void {
	if (libpd_message(recv, msg, @intCast(av.len), av.ptr) != 0) {
		return Error.ReceiverNotFound;
	}
}
extern fn libpd_message([*:0]const u8, [*:0]const u8, c_uint, [*]Atom) c_int;


// ------------------------ receiving messages from pd -------------------------
// -----------------------------------------------------------------------------

/// Subscribe to messages sent to a source receiver.
///
/// Ex: `bind("foo")` adds a "virtual" `[r foo]` which forwards messages to
///     the libpd message hooks
/// returns an opaque receiver pointer or NULL on failure
pub fn bind(recv: [*:0]const u8) Error!*anyopaque {
	return libpd_bind(recv) orelse Error.Bind;
}
extern fn libpd_bind([*:0]const u8) ?*anyopaque;

/// Unsubscribe and free a source receiver object created by `libpd_bind()`.
pub const unbind = libpd_unbind;
extern fn libpd_unbind(*anyopaque) void;

/// check if a source receiver object exists with a given name
pub fn exists(recv: [*:0]const u8) bool {
	return (libpd_exists(recv) != 0);
}
extern fn libpd_exists([*:0]const u8) c_int;

/// Print receive hook signature. 1st parameter is the source receiver name.
///
/// Note: default behavior returns individual words and spaces:
///     line "hello 123" is received in 3 parts -> "hello", " ", "123\n"
pub const PrintHook = fn ([*:0]const u8) callconv(.c) void;
/// Set the print receiver hook, prints to stdout by default
/// Note: do not call this while DSP is running.
///
/// Assign the pointer to your print line handler.
/// Concatenates print messages into single lines before returning them to the
/// print hook.
///
///   Ex: line "hello 123\n" is received in 1 part -> "hello 123".
/// For comparison, the default behavior may receive messages in chunks.
///
///   Ex: line "hello 123" could be sent in 3 parts -> "hello", " ", "123\n".
///
/// Call with NULL pointer to free internal buffer.
///
/// Note: do not call before libpd_init()
pub const setPrintHook = libpd_set_concatenated_printhook;
extern fn libpd_set_concatenated_printhook(?*const PrintHook) void;

/// Bang receive hook signature. 1st parameter is the source receiver name.
pub const BangHook = fn ([*:0]const u8) callconv(.c) void;
/// Set the bang receiver hook, NULL by default.
/// Note: do not call this while DSP is running
pub const setBangHook = libpd_set_banghook;
extern fn libpd_set_banghook(?*const BangHook) void;

/// Float receive hook signature. 1st parameter is the source receiver name.
pub const FloatHook = fn ([*:0]const u8, f32) callconv(.c) void;
/// Set the float receiver hook, NULL by default.
/// Note: avoid calling this while DSP is running.
/// Note: you can either have a float receiver hook, or a double receiver
///       hook (see below), but not both.
///       Calling this, will automatically unset the double receiver hook
pub const setFloatHook = libpd_set_floathook;
extern fn libpd_set_floathook(?*const FloatHook) void;

/// Double receive hook signature. 1st parameter is the source receiver name.
///
/// Note: only full-precision when compiled with `PD_FLOATSIZE=64`.
pub const DoubleHook = fn ([*:0]const u8, f64) callconv(.c) void;
/// Set the double receiver hook, NULL by default.
/// Note: avoid calling this while DSP is running.
/// Note: you can either have a double receiver hook, or a float receiver
///       hook (see above), but not both.
///       Calling this, will automatically unset the float receiver hook
pub const setDoubleHook = libpd_set_doublehook;
extern fn libpd_set_doublehook(?*const DoubleHook) void;

/// Symbol receive hook signature. 1st parameter is the source receiver name.
pub const SymbolHook = fn ([*:0]const u8, [*:0]const u8) callconv(.c) void;
/// Set the symbol receiver hook, NULL by default.
/// Note: do not call this while DSP is running.
pub const setSymbolHook = libpd_set_symbolhook;
extern fn libpd_set_symbolhook(?*const SymbolHook) void;

/// List receive hook signature. 1st parameter is the source receiver name,
/// followed by list length and vector containing the list elements,
/// which can be accessed using the atom accessor functions.
pub const ListHook = fn ([*:0]const u8, c_uint, [*]Atom) callconv(.c) void;
/// Set the list receiver hook, NULL by default.
/// Note: do not call this while DSP is running.
pub const setListHook = libpd_set_listhook;
extern fn libpd_set_listhook(?*const ListHook) void;

/// Typed message hook signature. 1st parameter is the source receiver name and 2nd is
/// the typed message name.
///
/// A message like [; foo bar 1 2 a b( will trigger a
/// function call like `libpd_messagehook("foo", "bar", 4, argv)`
pub const MessageHook = fn ([*:0]const u8, [*:0]const u8, c_uint, [*]Atom) callconv(.c) void;
/// Set the message receiver hook, NULL by default.
/// Note: do not call this while DSP is running.
pub const setMessageHook = libpd_set_messagehook;
extern fn libpd_set_messagehook(?*const MessageHook) void;

/// Check if an atom is a float type.
pub fn isFloat(a: *Atom) bool {
	return (libpd_is_float(a) != 0);
}
extern fn libpd_is_float(*Atom) c_int;

/// Check if an atom is a symbol type.
pub fn isSymbol(a: *Atom) bool {
	return (libpd_is_symbol(a) != 0);
}
extern fn libpd_is_symbol(*Atom) c_int;

/// Returns the float value of an atom.
pub const getFloat = libpd_get_float;
extern fn libpd_get_float(*Atom) f32;

/// Returns the double value of an atom.
/// Note: only full-precision when compiled with `PD_FLOATSIZE=64`.
pub const getDouble = libpd_get_double;
extern fn libpd_get_double(*Atom) f64;

/// Returns the symbol value of an atom.
pub const getSymbol = libpd_get_symbol;
extern fn libpd_get_symbol(*Atom) [*:0]const u8;


// ------------------------ sending MIDI messages to pd ------------------------
// -----------------------------------------------------------------------------

/// Send a MIDI note on message to [notein] objects.
/// Channel is 0-indexed, pitch is 0-127, and velocity is 0-127.
/// Channels encode MIDI ports via: libpd_channel = pd_channel + 16 * pd_port.
/// Note: there is no note off message, send a note on with velocity = 0 instead.
pub fn sendNoteOn(channel: c_uint, pitch: u7, velocity: u7) void {
	_ = libpd_noteon(channel, @intCast(pitch), @intCast(velocity));
}
extern fn libpd_noteon(channel: c_uint, pitch: c_uint, velocity: c_uint) c_int;

/// Send a MIDI control change message to [ctlin] objects.
/// Channel is 0-indexed, controller is 0-127, and value is 0-127.
/// Channels encode MIDI ports via: libpd_channel = pd_channel + 16 * pd_port.
pub fn sendControlChange(channel: c_uint, controller: u7, value: u7) void {
	_ = libpd_controlchange(channel, @intCast(controller), @intCast(value));
}
extern fn libpd_controlchange(channel: c_uint, controller: c_uint, value: c_uint) c_int;

/// Send a MIDI program change message to [pgmin] objects.
/// Channel is 0-indexed and value is 0-127.
/// Channels encode MIDI ports via: libpd_channel = pd_channel + 16 * pd_port.
pub fn sendProgramChange(channel: c_uint, value: u7) void {
	_ = libpd_programchange(channel, @intCast(value));
}
extern fn libpd_programchange(channel: c_uint, value: c_uint) c_int;

/// Send a MIDI pitch bend message to [bendin] objects.
/// Channel is 0-indexed and value is -8192-8192.
/// Channels encode MIDI ports via: libpd_channel = pd_channel + 16 * pd_port.
/// Note: [bendin] outputs 0-16383 while [bendout] accepts -8192-8192.
pub fn sendPitchBend(channel: c_uint, value: i14) void {
	_ = libpd_pitchbend(channel, @intCast(value));
}
extern fn libpd_pitchbend(channel: c_uint, value: c_int) c_int;

/// Send a MIDI after touch message to [touchin] objects.
/// Channel is 0-indexed and value is 0-127.
/// Channels encode MIDI ports via: libpd_channel = pd_channel + 16 * pd_port.
pub fn sendAftertouch(channel: c_uint, value: u7) void {
	_ = libpd_aftertouch(channel, @intCast(value));
}
extern fn libpd_aftertouch(channel: c_uint, value: c_uint) c_int;

/// Send a MIDI poly after touch message to [polytouchin] objects.
/// Channel is 0-indexed, pitch is 0-127, and value is 0-127.
/// Channels encode MIDI ports via: libpd_channel = pd_channel + 16 * pd_port.
pub fn sendPolyAftertouch(channel: c_uint, pitch: u7, value: u7) void {
	_ = libpd_polyaftertouch(channel, @intCast(pitch), @intCast(value));
}
extern fn libpd_polyaftertouch(channel: c_uint, pitch: c_uint, value: c_uint) c_int;

/// Send a raw MIDI byte to [midiin] objects.
/// Port is 0-indexed and byte is 0-256.
pub fn sendMidiByte(port: u12, byte: u8) void {
	_ = libpd_midibyte(@intCast(port), @intCast(byte));
}
extern fn libpd_midibyte(port: c_uint, byte: c_uint) c_int;

/// Send a raw MIDI byte to [sysexin] objects.
/// Port is 0-indexed and byte is 0-256.
pub fn sendSysex(port: u12, byte: u8) void {
	_ = libpd_sysex(@intCast(port), @intCast(byte));
}
extern fn libpd_sysex(port: c_uint, byte: c_uint) c_int;

/// Send a raw MIDI byte to [realtimein] objects.
/// Port is 0-indexed and byte is 0-256.
pub fn sendSysRealTime(port: u12, byte: u8) void {
	_ = libpd_sysrealtime(@intCast(port), @intCast(byte));
}
extern fn libpd_sysrealtime(port: c_uint, byte: c_uint) c_int;


// ---------------------- receiving MIDI messages from pd ----------------------
// -----------------------------------------------------------------------------

/// MIDI note on receive hook signature.
/// Channel is 0-indexed, pitch is 0-127, and value is 0-127.
/// Channels encode MIDI ports via: libpd_channel = pd_channel + 16 * pd_port.
/// Note: there is no note off message, note on w/ velocity = 0 is used instead.
/// Note: out of range values from pd are clamped.
pub const NoteOnHook = fn (c_uint, c_uint, c_uint) callconv(.c) void;
/// Set the MIDI note on hook to receive from [noteout] objects, NULL by default.
/// Note: do not call this while DSP is running.
pub const setNoteOnHook = libpd_set_noteonhook;
pub extern fn libpd_set_noteonhook(?*const NoteOnHook) void;

/// MIDI control change receive hook signature.
/// Channel is 0-indexed, controller is 0-127, and value is 0-127.
/// Channels encode MIDI ports via: libpd_channel = pd_channel + 16 * pd_port.
/// Note: out of range values from pd are clamped.
pub const ControlChangeHook = fn (c_uint, c_uint, c_uint) callconv(.c) void;
/// Set the MIDI control change hook to receive from [ctlout] objects,
/// NULL by default.
/// Note: do not call this while DSP is running.
pub const setControlChangeHook = libpd_set_controlchangehook;
pub extern fn libpd_set_controlchangehook(?*const ControlChangeHook) void;

/// MIDI program change receive hook signature.
/// Channel is 0-indexed and value is 0-127.
/// Channels encode MIDI ports via: libpd_channel = pd_channel + 16 * pd_port.
/// Note: out of range values from pd are clamped.
pub const ProgramChangeHook = fn (c_uint, c_uint) callconv(.c) void;
/// Set the MIDI program change hook to receive from [pgmout] objects,
/// NULL by default.
/// Note: do not call this while DSP is running.
pub const setProgramChangeHook = libpd_set_programchangehook;
pub extern fn libpd_set_programchangehook(?*const ProgramChangeHook) void;

/// MIDI pitch bend receive hook signature.
/// Channel is 0-indexed and value is -8192-8192.
/// Channels encode MIDI ports via: libpd_channel = pd_channel + 16 * pd_port.
/// Note: [bendin] outputs 0-16383 while [bendout] accepts -8192-8192.
/// Note: out of range values from pd are clamped.
pub const PitchBendHook = fn (c_uint, c_int) callconv(.c) void;
/// Set the MIDI pitch bend hook to receive from [bendout] objects,
/// NULL by default.
/// Note: do not call this while DSP is running.
pub const setPitchBendHook = libpd_set_pitchbendhook;
pub extern fn libpd_set_pitchbendhook(?*const PitchBendHook) void;

/// MIDI after touch receive hook signature.
/// Channel is 0-indexed and value is 0-127.
/// Channels encode MIDI ports via: libpd_channel = pd_channel + 16 * pd_port.
/// Note: out of range values from pd are clamped.
pub const AftertouchHook = fn (c_uint, c_uint) callconv(.c) void;
/// Set the MIDI after touch hook to receive from [touchout] objects,
/// NULL by default.
/// Note: do not call this while DSP is running.
pub const setAftertouchHook = libpd_set_aftertouchhook;
pub extern fn libpd_set_aftertouchhook(?*const AftertouchHook) void;

/// MIDI poly after touch receive hook signature.
/// Channel is 0-indexed, pitch is 0-127, and value is 0-127.
/// Channels encode MIDI ports via: libpd_channel = pd_channel + 16 * pd_port.
/// Note: out of range values from pd are clamped.
pub const PolyAftertouchHook = fn (c_uint, c_uint, c_uint) callconv(.c) void;
/// Set the MIDI poly after touch hook to receive from [polytouchout] objects,
/// NULL by default.
/// Note: do not call this while DSP is running.
pub const setPolyAftertouchHook = libpd_set_polyaftertouchhook;
pub extern fn libpd_set_polyaftertouchhook(?*const PolyAftertouchHook) void;

/// Raw MIDI byte receive hook signature.
/// Port is 0-indexed and byte is 0-256.
/// Note: out of range values from pd are clamped.
pub const MidiByteHook = fn (c_uint, c_uint) callconv(.c) void;
/// Set the raw MIDI byte hook to receive from [midiout] objects,
/// NULL by default.
/// Note: do not call this while DSP is running.
pub const setMidiByteHook = libpd_set_midibytehook;
pub extern fn libpd_set_midibytehook(?*const MidiByteHook) void;


// ------------------------------------ GUI ------------------------------------
// -----------------------------------------------------------------------------

/// Open the current patches within a pd vanilla GUI.
/// Requires the path to pd's main folder that contains bin/, tcl/, etc.
/// For a macOS .app bundle: /path/to/Pd-#.#-#.app/Contents/Resources.
pub fn startGui(path: [*:0]const u8) Error!void {
	if (libpd_start_gui(path) != 0) {
		return Error.StartGui;
	}
}
extern fn libpd_start_gui([*:0]const u8) c_int;

/// Stop the pd vanilla GUI.
pub const stopGui = libpd_stop_gui;
extern fn libpd_stop_gui() void;

/// Manually update and handle any GUI messages.
/// This is called automatically when using a libpd_process function.
/// Note: this also facilitates network message processing, etc so it can be
///       useful to call repeatedly when idle for more throughput.
pub fn pollGui() bool {
	return (libpd_poll_gui() != 0);
}
extern fn libpd_poll_gui() c_int;


// ---------------------------- multiple instances -----------------------------
// -----------------------------------------------------------------------------

/// Create a new pd instance and set as current.
/// Note: use this in place of pdinstance_new().
/// returns new instance or NULL when libpd is not compiled with PDINSTANCE.
pub fn newInstance() Error!*Instance {
	return libpd_new_instance() orelse Error.NewInstance;
}
extern fn libpd_new_instance() ?*Instance;

/// Set the current pd instance.
/// Subsequent libpd calls will affect this instance only.
/// Note: use this in place of pd_setinstance().
/// Does nothing when libpd is not compiled with PDINSTANCE
pub const setInstance = libpd_set_instance;
extern fn libpd_set_instance(*Instance) void;

/// Free a pd instance and set main instance as current.
/// Note: use this in place of pdinstance_free().
/// Does nothing when libpd is not compiled with PDINSTANCE.
pub const freeInstance = libpd_free_instance;
extern fn libpd_free_instance(*Instance) void;

/// Get the current pd instance.
pub const thisInstance = libpd_this_instance;
extern fn libpd_this_instance() *Instance;

/// Get the main pd instance.
pub const mainInstance = libpd_main_instance;
extern fn libpd_main_instance() *Instance;

/// get the number of pd instances, including the main instance
/// returns number or 1 when libpd is not compiled with PDINSTANCE
pub const numInstances = libpd_num_instances;
extern fn libpd_num_instances() c_uint;

/// per-instance data free hook signature
pub const FreeHook = fn (?*anyopaque) callconv(.c) void;
/// Set per-instance user data and optional free hook.
/// Note: if non-NULL, freehook is called by libpd_free_instance()
pub const setInstanceData = libpd_set_instancedata;
extern fn libpd_set_instancedata(*anyopaque, ?*const FreeHook) void;

/// get per-instance user data
pub const getInstanceData = libpd_get_instancedata;
extern fn libpd_get_instancedata() ?*anyopaque;


// --------------------------------- log level ---------------------------------
// -----------------------------------------------------------------------------

/// set verbose print state: 0 or 1
pub fn setVerbose(state: bool) void {
	libpd_set_verbose(@intFromBool(state));
}
extern fn libpd_set_verbose(c_uint) void;

/// get the verbose print state: 0 or 1
pub fn isVerbose() bool {
	return (libpd_get_verbose() != 0);
}
extern fn libpd_get_verbose() c_int;
