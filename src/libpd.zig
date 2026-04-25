const c = @import("cdef");
pub const pd = @import("pd");

pub const ulong = @Int(.unsigned, @bitSizeOf(c_long) - 1);
const uint = pd.uint;
const Atom = pd.Atom;
const Instance = pd.Instance;

const std = @import("std");
const testing = std.testing;

// ------------------------------ initializing pd ------------------------------
// -----------------------------------------------------------------------------

pub const Base = struct {
	queued: bool,

	/// Initialize Pd and set up the audio processing.
	/// Note: sets `SIGFPE` handler to keep bad pd patches from crashing due to divide
	/// by 0, set any custom handling after calling this function.
	pub fn init(
		in_channels: uint,
		out_channels: uint,
		sample_rate: uint,
		is_queued: bool,
	) error{AlreadyInitialized, RingBufferFail, InitAudioFail}!Base {
		if (is_queued) {
			switch (c.libpd_queued_init()) {
				-1 => return error.AlreadyInitialized,
				-2 => return error.RingBufferFail,
				else => {},
			}
			errdefer c.libpd_queued_release();
			c.libpd_set_queued_printhook(c.libpd_print_concatenator);
		} else {
			if (c.libpd_init() != 0) {
				return error.AlreadyInitialized;
			}
			c.libpd_set_printhook(c.libpd_print_concatenator);
		}
		if (c.libpd_init_audio(in_channels, out_channels, sample_rate) != 0) {
			return error.InitAudioFail;
		}
		return Base{ .queued = is_queued };
	}

	test init {
		try init(0, 2, 48000, false);
		try testing.expectError(error.AlreadyInitialized, init(0, 2, 48000, false));
	}

	/// Free the ring buffer if we're using it
	pub fn close(self: *const Base) void {
		computeAudio(false);
		if (self.queued) {
			c.libpd_queued_release();
		}
	}
};

/// Clear the current pd search path.
pub const clearSearchPath = c.libpd_clear_search_path;

/// Add a path to the libpd search paths.
/// Relative paths are relative to the current working directory.
///
/// Unlike desktop pd, *no* search paths are set by default (ie. extra)
pub fn addToSearchPath(path: [*:0]const u8) void {
	c.libpd_add_to_search_path(path);
}


// ------------------------------ opening patches ------------------------------
// -----------------------------------------------------------------------------

pub const Patch = struct {
	/// Patch handle pointer.
	handle: ?*anyopaque = null,
	/// Unique $0 patch ID
	dollar_zero: c_uint = 0,

	/// Open a patch by filename and parent dir path.
	pub fn fromFile(name: [*:0]const u8, dir: [*:0]const u8) error{OpenFile}!Patch {
		return if (c.libpd_openfile(name, dir)) |file| Patch{
			.handle = file,
			.dollar_zero = @intCast(c.libpd_getdollarzero(file)),
		} else error.OpenFile;
	}

	/// Close a patch by patch handle pointer.
	pub fn close(self: *const Patch) void {
		if (self.handle) |h| {
			c.libpd_closefile(h);
		}
	}
};


// ----------------------------- audio processing ------------------------------
// -----------------------------------------------------------------------------

pub fn computeAudio(state: bool) void {
	_ = c.libpd_start_message(1);
	addFloat(@floatFromInt(@intFromBool(state)));
	_ = c.libpd_finish_message("pd", "dsp");
}

/// Return pd's fixed block size: the number of sample frames per 1 pd tick.
pub fn blockSize() uint {
	return @intCast(c.libpd_blocksize());
}

pub const ProcessError = error{ProcessError};

/// Process interleaved float samples from inBuffer -> libpd -> outBuffer
///
/// Buffer sizes are based on # of ticks and channels where:
///     `size = ticks * libpd_blocksize() * (in/out)channels`.
pub fn processFloat(
	ticks: uint,
	in_buffer: ?[*]const f32,
	out_buffer: ?[*]f32,
) ProcessError!void {
	if (c.libpd_process_float(ticks, in_buffer, out_buffer) != 0) {
		return error.ProcessError;
	}
}

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
	ticks: uint,
	in_buffer: ?[*]const c_short,
	out_buffer: ?[*]c_short,
) ProcessError!void {
	if (c.libpd_process_short(ticks, in_buffer, out_buffer) != 0) {
		return error.ProcessError;
	}
}

/// Process interleaved double samples from inBuffer -> libpd -> outBuffer.
///
/// Buffer sizes are based on # of ticks and channels where:
///     `size = ticks * libpd_blocksize() * (in/out)channels`.
///
/// Note: only full-precision when compiled with `PD_FLOATSIZE=64`
pub fn processDouble(
	ticks: uint,
	in_buffer: ?[*]const f64,
	out_buffer: ?[*]f64,
) ProcessError!void {
	if (c.libpd_process_double(ticks, in_buffer, out_buffer) != 0) {
		return error.ProcessError;
	}
}

/// Process non-interleaved float samples from inBuffer -> libpd -> outBuffer.
///
/// Copies buffer contents to/from libpd without striping.
///
/// Buffer sizes are based on a single tick and # of channels where:
///     `size = libpd_blocksize() * (in/out)channels`.
pub fn processRawFloat(
	in_buffer: ?[*]const f32,
	out_buffer: ?[*]f32,
) ProcessError!void {
	if (c.libpd_process_raw(in_buffer, out_buffer) != 0) {
		return error.ProcessError;
	}
}

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
pub fn processRawShort(
	in_buffer: ?[*]const c_short,
	out_buffer: ?[*]c_short,
) ProcessError!void {
	if (c.libpd_process_raw_short(in_buffer, out_buffer) != 0) {
		return error.ProcessError;
	}
}

/// Process non-interleaved double samples from inBuffer -> libpd -> outBuffer.
///
/// Copies buffer contents to/from libpd without striping.
///
/// Buffer sizes are based on a single tick and # of channels where:
///     `size = libpd_blocksize() * (in/out)channels`.
///
/// Note: only full-precision when compiled with `PD_FLOATSIZE=64`.
pub fn processRawDouble(
	in_buffer: ?[*]const f64,
	out_buffer: ?[*]f64,
) ProcessError!void {
	if (c.libpd_process_raw_double(in_buffer, out_buffer) != 0) {
		return error.ProcessError;
	}
}


// ------------------------------- array access --------------------------------
// -----------------------------------------------------------------------------

/// Get the size of an array by name.
pub fn arraySize(name: [*:0]const u8) error{ArrayNotFound}!uint {
	const size = c.libpd_arraysize(name);
	return if (size < 0) error.ArrayNotFound else @intCast(size);
}

/// (re)size an array by name; sizes <= 0 are clipped to 1.
pub fn resizeArray(name: [*:0]const u8, size: ulong) error{ArrayNotFound}!void {
	if (c.libpd_resize_array(name, size) != 0) {
		return error.ArrayNotFound;
	}
}

pub const ArrayError = error{ArrayNotFound, ArrayOutOfBounds};

/// Read values from named src array and write into `dest` starting at an offset.
///
/// Note: performs no bounds checking on `dest`.
pub fn readArray(name: [*:0]const u8, offset: uint, dest: []f32) ArrayError!void {
	return switch (c.libpd_read_array(dest.ptr, name, offset, @intCast(dest.len))) {
		-1 => error.ArrayNotFound,
		-2 => error.ArrayOutOfBounds,
		else => {},
	};
}

/// Read values from `src` and write into named dest array starting at an offset.
///
/// Note: performs no bounds checking on `src`.
pub fn writeArray(name: [*:0]const u8, offset: uint, src: []const f32) ArrayError!void {
	return switch (c.libpd_write_array(name, offset, src.ptr, @intCast(src.len))) {
		-1 => error.ArrayNotFound,
		-2 => error.ArrayOutOfBounds,
		else => {},
	};
}

/// Read values from named src array and write into `dest` starting at an offset.
///
/// Note: performs no bounds checking on `dest`.
///
/// Note: only full-precision when compiled with `PD_FLOATSIZE=64`.
///
/// Double-precision variant of libpd_read_array().
pub fn readArrayDouble(name: [*:0]const u8, offset: uint, dest: []f64) ArrayError!void {
	return switch (c.libpd_read_array_double(dest.ptr, name, offset, @intCast(dest.len))) {
		-1 => error.ArrayNotFound,
		-2 => error.ArrayOutOfBounds,
		else => {},
	};
}

/// Read values from `src` and write into named dest array starting at an offset.
///
/// Note: performs no bounds checking on `src`.
///
/// Note: only full-precision when compiled with `PD_FLOATSIZE=64`.
///
/// Double-precision variant of libpd_write_array().
pub fn writeArrayDouble(
	name: [*:0]const u8, offset: uint,
	src: []const f64,
) ArrayError!void {
	return switch (c.libpd_write_array_double(name, offset, src.ptr, @intCast(src.len))) {
		-1 => error.ArrayNotFound,
		-2 => error.ArrayOutOfBounds,
		else => {},
	};
}


// -------------------------- sending messages to pd ---------------------------
// -----------------------------------------------------------------------------

pub const SendError = error{ReceiverNotFound};

/// Send a bang to a destination receiver.
///
/// Ex: `sendBang("foo")` will send a bang to [s foo] on the next tick.
pub fn sendBang(recv: [*:0]const u8) SendError!void {
	if (c.libpd_bang(recv) != 0) {
		return error.ReceiverNotFound;
	}
}

/// Send a float to a destination receiver.
///
/// Ex: `sendFloat("foo", 1)` will send a 1.0 to [s foo] on the next tick.
pub fn sendFloat(recv: [*:0]const u8, x: f32) SendError!void {
	if (c.libpd_float(recv, x) != 0) {
		return error.ReceiverNotFound;
	}
}

/// Send a double to a destination receiver.
///
/// Ex: `sendDouble("foo", 1.1)` will send a 1.1 to [s foo] on the next tick
///
/// Note: only full-precision when compiled with `PD_FLOATSIZE=64`.
pub fn sendDouble(recv: [*:0]const u8, x: f64) SendError!void {
	if (c.libpd_double(recv, x) != 0) {
		return error.ReceiverNotFound;
	}
}

/// Send a symbol to a destination receiver.
/// Ex: `sendSymbol("foo", "bar")` will send "bar" to [s foo] on the next tick.
pub fn sendSymbol(recv: [*:0]const u8, s: [*:0]const u8) SendError!void {
	if (c.libpd_symbol(recv, s) != 0) {
		return error.ReceiverNotFound;
	}
}


// ------------ sending compound messages: sequenced function calls ------------
// -----------------------------------------------------------------------------

/// Start composition of a new list or typed message of up to max element length.
/// Messages can be of a smaller length as max length is only an upper bound.
///
/// Note: no cleanup is required for unfinished messages.
pub fn startMessage(maxlen: uint) error{MessageTooLong}!void {
	if (c.libpd_start_message(maxlen) != 0) {
		return error.MessageTooLong;
	}
}

test startMessage {
	try testing.expectError(error.MessageTooLong, startMessage(1234567890));
	try startMessage(1);
}

/// Add a float to the current message in progress.
pub const addFloat = c.libpd_add_float;

/// Add a double to the current message in progress.
///
/// Note: only full-precision when compiled with `PD_FLOATSIZE=64`.
pub const addDouble = c.libpd_add_double;

/// add a symbol to the current message in progress
pub const addSymbol = c.libpd_add_symbol;

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
pub fn finishList(recv: [*:0]const u8) SendError!void {
	if (c.libpd_finish_list(recv) != 0) {
		return error.ReceiverNotFound;
	}
}

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
pub fn finishMessage(recv: [*:0]const u8, msg: [*:0]const u8) SendError!void {
	if (c.libpd_finish_message(recv, msg) != 0) {
		return error.ReceiverNotFound;
	}
}


// ------------------- sending compound messages: atom array -------------------
// -----------------------------------------------------------------------------

/// Write a float value to the given atom.
pub fn setFloat(atom: *Atom, f: f32) void {
	c.libpd_set_float(@ptrCast(atom), f);
}

/// Write a double value to the given atom.
/// Note: only full-precision when compiled with `PD_FLOATSIZE=64`.
pub fn setDouble(atom: *Atom, f: f64) void {
	c.libpd_set_double(@ptrCast(atom), f);
}

/// Write a symbol value to the given atom.
pub fn setSymbol(atom: *Atom, s: [*:0]const u8) void {
	c.libpd_set_symbol(@ptrCast(atom), s);
}

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
pub fn sendList(recv: [*:0]const u8, av: []Atom) SendError!void {
	if (c.libpd_list(recv, @intCast(av.len), @ptrCast(av.ptr)) != 0) {
		return error.ReceiverNotFound;
	}
}

pub fn sendMessage(recv: [*:0]const u8, msg: [*:0]const u8, av: []Atom) SendError!void {
	if (c.libpd_message(recv, msg, @intCast(av.len), @ptrCast(av.ptr)) != 0) {
		return error.ReceiverNotFound;
	}
}


// ------------------------ receiving messages from pd -------------------------
// -----------------------------------------------------------------------------

/// Subscribe to messages sent to a source receiver.
///
/// Ex: `bind("foo")` adds a "virtual" `[r foo]` which forwards messages to
///     the libpd message hooks
/// returns an opaque receiver pointer or NULL on failure
pub fn bind(recv: [*:0]const u8) error{BindError}!*anyopaque {
	return c.libpd_bind(recv) orelse error.BindError;
}

/// Unsubscribe and free a source receiver object created by `libpd_bind()`.
pub const unbind = c.libpd_unbind;

/// check if a source receiver object exists with a given name
pub fn exists(recv: [*:0]const u8) bool {
	return (c.libpd_exists(recv) != 0);
}

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
/// Note: do not call before `libpd_init()`
pub fn setPrintHook(hook: ?*const PrintHook) void {
	c.libpd_set_concatenated_printhook(@ptrCast(hook));
}

/// Bang receive hook signature. 1st parameter is the source receiver name.
pub const BangHook = fn ([*:0]const u8) callconv(.c) void;

/// Set the bang receiver hook, NULL by default.
/// Note: do not call this while DSP is running
pub fn setBangHook(hook: ?*const BangHook) void {
	c.libpd_set_banghook(@ptrCast(hook));
}

/// Float receive hook signature. 1st parameter is the source receiver name.
pub const FloatHook = fn ([*:0]const u8, f32) callconv(.c) void;

/// Set the float receiver hook, NULL by default.
/// Note: avoid calling this while DSP is running.
/// Note: you can either have a float receiver hook, or a double receiver
///       hook (see below), but not both.
///       Calling this, will automatically unset the double receiver hook
pub fn setFloatHook(hook: ?*const FloatHook) void {
	c.libpd_set_floathook(@ptrCast(hook));
}

/// Double receive hook signature. 1st parameter is the source receiver name.
///
/// Note: only full-precision when compiled with `PD_FLOATSIZE=64`.
pub const DoubleHook = fn ([*:0]const u8, f64) callconv(.c) void;

/// Set the double receiver hook, NULL by default.
/// Note: avoid calling this while DSP is running.
/// Note: you can either have a double receiver hook, or a float receiver
///       hook (see above), but not both.
///       Calling this, will automatically unset the float receiver hook
pub fn setDoubleHook(hook: ?*const DoubleHook) void {
	c.libpd_set_doublehook(@ptrCast(hook));
}

/// Symbol receive hook signature. 1st parameter is the source receiver name.
pub const SymbolHook = fn ([*:0]const u8, [*:0]const u8) callconv(.c) void;

/// Set the symbol receiver hook, NULL by default.
/// Note: do not call this while DSP is running.
pub fn setSymbolHook(hook: ?*const SymbolHook) void {
	c.libpd_set_symbolhook(@ptrCast(hook));
}

/// List receive hook signature. 1st parameter is the source receiver name,
/// followed by list length and vector containing the list elements,
/// which can be accessed using the atom accessor functions.
pub const ListHook = fn ([*:0]const u8, c_uint, [*]Atom) callconv(.c) void;

/// Set the list receiver hook, NULL by default.
/// Note: do not call this while DSP is running.
pub fn setListHook(hook: ?*const ListHook) void {
	c.libpd_set_listhook(@ptrCast(hook));
}

/// Typed message hook signature. 1st parameter is the source receiver name and 2nd is
/// the typed message name.
///
/// A message like [; foo bar 1 2 a b( will trigger a
/// function call like `libpd_messagehook("foo", "bar", 4, argv)`
pub const MessageHook =
	fn ([*:0]const u8, [*:0]const u8, c_uint, [*]Atom) callconv(.c) void;

/// Set the message receiver hook, NULL by default.
/// Note: do not call this while DSP is running.
pub fn setMessageHook(hook: ?*const MessageHook) void {
	c.libpd_set_messagehook(@ptrCast(hook));
}

/// Check if an atom is a float type.
pub fn isFloat(atom: *Atom) bool {
	return (c.libpd_is_float(@ptrCast(atom)) != 0);
}

/// Check if an atom is a symbol type.
pub fn isSymbol(atom: *Atom) bool {
	return (c.libpd_is_symbol(@ptrCast(atom)) != 0);
}

/// Returns the float value of an atom.
pub fn getFloat(atom: *Atom) f32 {
	return c.libpd_get_float(@ptrCast(atom));
}

/// Returns the double value of an atom.
/// Note: only full-precision when compiled with `PD_FLOATSIZE=64`.
pub fn getDouble(atom: *Atom) f64 {
	return c.libpd_get_double(@ptrCast(atom));
}

/// Returns the symbol value of an atom.
pub fn getSymbol(atom: *Atom) [*:0]const u8 {
	return c.libpd_get_symbol(@ptrCast(atom));
}


// ------------------------ sending MIDI messages to pd ------------------------
// -----------------------------------------------------------------------------

/// Send a MIDI note on message to [notein] objects.
/// Channel is 0-indexed, pitch is 0-127, and velocity is 0-127.
/// Channels encode MIDI ports via: libpd_channel = pd_channel + 16 * pd_port.
/// Note: there is no note off message, send a note on with velocity = 0 instead.
pub fn sendNoteOn(channel: u32, pitch: u7, velocity: u7) void {
	_ = c.libpd_noteon(@intCast(channel), @intCast(pitch), @intCast(velocity));
}

/// Send a MIDI control change message to [ctlin] objects.
/// Channel is 0-indexed, controller is 0-127, and value is 0-127.
/// Channels encode MIDI ports via: libpd_channel = pd_channel + 16 * pd_port.
pub fn sendControlChange(channel: u32, controller: u7, value: u7) void {
	_ = c.libpd_controlchange(@intCast(channel), @intCast(controller), @intCast(value));
}

/// Send a MIDI program change message to [pgmin] objects.
/// Channel is 0-indexed and value is 0-127.
/// Channels encode MIDI ports via: libpd_channel = pd_channel + 16 * pd_port.
pub fn sendProgramChange(channel: u32, value: u7) void {
	_ = c.libpd_programchange(@intCast(channel), @intCast(value));
}

/// Send a MIDI pitch bend message to [bendin] objects.
/// Channel is 0-indexed and value is -8192-8192.
/// Channels encode MIDI ports via: libpd_channel = pd_channel + 16 * pd_port.
/// Note: [bendin] outputs 0-16383 while [bendout] accepts -8192-8192.
pub fn sendPitchBend(channel: u32, value: i14) void {
	_ = c.libpd_pitchbend(@intCast(channel), @intCast(value));
}

/// Send a MIDI after touch message to [touchin] objects.
/// Channel is 0-indexed and value is 0-127.
/// Channels encode MIDI ports via: libpd_channel = pd_channel + 16 * pd_port.
pub fn sendAftertouch(channel: u32, value: u7) void {
	_ = c.libpd_aftertouch(@intCast(channel), @intCast(value));
}

/// Send a MIDI poly after touch message to [polytouchin] objects.
/// Channel is 0-indexed, pitch is 0-127, and value is 0-127.
/// Channels encode MIDI ports via: libpd_channel = pd_channel + 16 * pd_port.
pub fn sendPolyAftertouch(channel: u32, pitch: u7, value: u7) void {
	_ = c.libpd_polyaftertouch(@intCast(channel), @intCast(pitch), @intCast(value));
}

/// Send a raw MIDI byte to [midiin] objects.
/// Port is 0-indexed and byte is 0-256.
pub fn sendMidiByte(port: u12, byte: u8) void {
	_ = c.libpd_midibyte(@intCast(port), @intCast(byte));
}

/// Send a raw MIDI byte to [sysexin] objects.
/// Port is 0-indexed and byte is 0-256.
pub fn sendSysex(port: u12, byte: u8) void {
	_ = c.libpd_sysex(@intCast(port), @intCast(byte));
}

/// Send a raw MIDI byte to [realtimein] objects.
/// Port is 0-indexed and byte is 0-256.
pub fn sendSysRealTime(port: u12, byte: u8) void {
	_ = c.libpd_sysrealtime(@intCast(port), @intCast(byte));
}


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
pub fn setNoteOnHook(hook: ?*const NoteOnHook) void {
	c.libpd_set_noteonhook(@ptrCast(hook));
}

/// MIDI control change receive hook signature.
/// Channel is 0-indexed, controller is 0-127, and value is 0-127.
/// Channels encode MIDI ports via: libpd_channel = pd_channel + 16 * pd_port.
/// Note: out of range values from pd are clamped.
pub const ControlChangeHook = fn (c_uint, c_uint, c_uint) callconv(.c) void;

/// Set the MIDI control change hook to receive from [ctlout] objects,
/// NULL by default.
/// Note: do not call this while DSP is running.
pub fn setControlChangeHook(hook: ?*const ControlChangeHook) void {
	c.libpd_set_controlchangehook(@ptrCast(hook));
}

/// MIDI program change receive hook signature.
/// Channel is 0-indexed and value is 0-127.
/// Channels encode MIDI ports via: libpd_channel = pd_channel + 16 * pd_port.
/// Note: out of range values from pd are clamped.
pub const ProgramChangeHook = fn (c_uint, c_uint) callconv(.c) void;

/// Set the MIDI program change hook to receive from [pgmout] objects,
/// NULL by default.
/// Note: do not call this while DSP is running.
pub fn setProgramChangeHook(hook: ?*const ProgramChangeHook) void {
	c.libpd_set_programchangehook(@ptrCast(hook));
}

/// MIDI pitch bend receive hook signature.
/// Channel is 0-indexed and value is -8192-8192.
/// Channels encode MIDI ports via: libpd_channel = pd_channel + 16 * pd_port.
/// Note: [bendin] outputs 0-16383 while [bendout] accepts -8192-8192.
/// Note: out of range values from pd are clamped.
pub const PitchBendHook = fn (c_uint, c_int) callconv(.c) void;

/// Set the MIDI pitch bend hook to receive from [bendout] objects,
/// NULL by default.
/// Note: do not call this while DSP is running.
pub fn setPitchBendHook(hook: ?*const PitchBendHook) void {
	c.libpd_set_pitchbendhook(@ptrCast(hook));
}

/// MIDI after touch receive hook signature.
/// Channel is 0-indexed and value is 0-127.
/// Channels encode MIDI ports via: libpd_channel = pd_channel + 16 * pd_port.
/// Note: out of range values from pd are clamped.
pub const AftertouchHook = fn (c_uint, c_uint) callconv(.c) void;

/// Set the MIDI after touch hook to receive from [touchout] objects,
/// NULL by default.
/// Note: do not call this while DSP is running.
pub fn setAftertouchHook(hook: ?*const AftertouchHook) void {
	c.libpd_set_aftertouchhook(@ptrCast(hook));
}

/// MIDI poly after touch receive hook signature.
/// Channel is 0-indexed, pitch is 0-127, and value is 0-127.
/// Channels encode MIDI ports via: libpd_channel = pd_channel + 16 * pd_port.
/// Note: out of range values from pd are clamped.
pub const PolyAftertouchHook = fn (c_uint, c_uint, c_uint) callconv(.c) void;

/// Set the MIDI poly after touch hook to receive from [polytouchout] objects,
/// NULL by default.
/// Note: do not call this while DSP is running.
pub fn setPolyAftertouchHook(hook: ?*const PolyAftertouchHook) void {
	c.libpd_set_polyaftertouchhook(@ptrCast(hook));
}

/// Raw MIDI byte receive hook signature.
/// Port is 0-indexed and byte is 0-256.
/// Note: out of range values from pd are clamped.
pub const MidiByteHook = fn (c_uint, c_uint) callconv(.c) void;

/// Set the raw MIDI byte hook to receive from [midiout] objects,
/// NULL by default.
/// Note: do not call this while DSP is running.
pub fn setMidiByteHook(hook: ?*const MidiByteHook) void {
	c.libpd_set_midibytehook(@ptrCast(hook));
}


// ------------------------------------ GUI ------------------------------------
// -----------------------------------------------------------------------------

/// Open the current patches within a pd vanilla GUI.
/// Requires the path to pd's main folder that contains bin/, tcl/, etc.
/// For a macOS .app bundle: /path/to/Pd-#.#-#.app/Contents/Resources.
pub fn startGui(path: [*:0]const u8) error{StartGui}!void {
	if (c.libpd_start_gui(path) != 0) {
		return error.StartGui;
	}
}

/// Stop the pd vanilla GUI.
pub const stopGui = c.libpd_stop_gui;

/// Manually update and handle any GUI messages.
/// This is called automatically when using a libpd_process function.
/// Note: this also facilitates network message processing, etc so it can be
///       useful to call repeatedly when idle for more throughput.
pub fn pollGui() bool {
	return (c.libpd_poll_gui() != 0);
}


// ---------------------------- multiple instances -----------------------------
// -----------------------------------------------------------------------------

/// Create a new pd instance and set as current.
/// Note: use this in place of pdinstance_new().
/// returns new instance or NULL when libpd is not compiled with PDINSTANCE.
pub fn newInstance() error{SingleInstanceMode, OutOfMemory}!*Instance {
	return if (pd.opt.multi)
		c.libpd_new_instance() orelse error.OutOfMemory
	else error.SingleInstanceMode;
}

/// Set the current pd instance.
/// Subsequent libpd calls will affect this instance only.
/// Note: use this in place of pd_setinstance().
/// Does nothing when libpd is not compiled with PDINSTANCE
pub fn setInstance(instance: *Instance) void {
	c.libpd_set_instance(@ptrCast(instance));
}

/// Free a pd instance and set main instance as current.
/// Note: use this in place of pdinstance_free().
/// Does nothing when libpd is not compiled with PDINSTANCE.
pub fn freeInstance(instance: *Instance) void {
	c.libpd_free_instance(@ptrCast(instance));
}

/// Get the current pd instance.
pub fn thisInstance() *Instance {
	return @ptrCast(c.libpd_this_instance());
}

/// Get the main pd instance.
pub fn mainInstance() *Instance {
	return @ptrCast(c.libpd_main_instance());
}

/// get the number of pd instances, including the main instance
/// returns number or 1 when libpd is not compiled with PDINSTANCE
pub fn numInstances() uint {
	return @intCast(c.libpd_num_instances());
}

/// per-instance data free hook signature
pub const FreeHook = fn (?*anyopaque) callconv(.c) void;

/// Set per-instance user data and optional free hook.
/// Note: if non-NULL, freehook is called by libpd_free_instance()
pub fn setInstanceData(data: *anyopaque, hook: ?*const FreeHook) void {
	c.libpd_set_instancedata(data, hook);
}

/// get per-instance user data
pub const getInstanceData = c.libpd_get_instancedata;


// --------------------------------- log level ---------------------------------
// -----------------------------------------------------------------------------

/// set verbose print state: 0 or 1
pub fn setVerbose(state: bool) void {
	c.libpd_set_verbose(@intFromBool(state));
}

/// get the verbose print state: 0 or 1
pub fn isVerbose() bool {
	return (c.libpd_get_verbose() != 0);
}
