pub const lib = [_][]const u8{
	"src/z_libpd.c",
	"src/z_hooks.c",
	"src/x_libpdreceive.c",
	"src/s_libpdmidi.c",
};

pub const util = [_][]const u8{
	"src/z_print_util.c",
	"src/z_queued.c",
	"src/z_ringbuffer.c"
};

pub const extra = [_][]const u8{
	"extra/bob~/bob~.c",
	"extra/bonk~/bonk~.c",
	"extra/choice/choice.c",
	"extra/fiddle~/fiddle~.c",
	"extra/loop~/loop~.c",
	"extra/lrshift~/lrshift~.c",
	"extra/pique/pique.c",
	"extra/pd~/pdsched.c",
	"extra/pd~/pd~.c",
	"extra/sigmund~/sigmund~.c",
	"extra/stdout/stdout.c",
};

pub const zig_extra = [_][]const u8{
	"sesom",
};

pub const fftw = [_][]const u8{
	"src/d_fft_fftw.c",
};

pub const fftsg = [_][]const u8{
	"src/d_fft_fftsg.c",
};

pub const entry = [_][]const u8{
	"src/s_entry.c",
};

pub const core = [_][]const u8{
	"src/d_arithmetic.c",
	"src/d_array.c",
	"src/d_ctl.c",
	"src/d_dac.c",
	"src/d_delay.c",
	"src/d_fft.c",
	"src/d_filter.c",
	"src/d_global.c",
	"src/d_math.c",
	"src/d_misc.c",
	"src/d_osc.c",
	"src/d_resample.c",
	"src/d_soundfile.c",
	"src/d_soundfile_aiff.c",
	"src/d_soundfile_caf.c",
	"src/d_soundfile_next.c",
	"src/d_soundfile_wave.c",
	"src/d_ugen.c",
	"src/g_all_guis.c",
	"src/g_array.c",
	"src/g_bang.c",
	"src/g_canvas.c",
	"src/g_clone.c",
	"src/g_editor.c",
	"src/g_editor_extras.c",
	"src/g_graph.c",
	"src/g_guiconnect.c",
	"src/g_io.c",
	"src/g_mycanvas.c",
	"src/g_numbox.c",
	"src/g_radio.c",
	"src/g_readwrite.c",
	"src/g_rtext.c",
	"src/g_scalar.c",
	"src/g_slider.c",
	"src/g_template.c",
	"src/g_text.c",
	"src/g_toggle.c",
	"src/g_traversal.c",
	"src/g_undo.c",
	"src/g_vumeter.c",
	"src/m_atom.c",
	"src/m_binbuf.c",
	"src/m_class.c",
	"src/m_conf.c",
	"src/m_glob.c",
	"src/m_memory.c",
	"src/m_obj.c",
	"src/m_pd.c",
	"src/m_sched.c",
	"src/s_audio.c",
	"src/s_inter.c",
	"src/s_inter_gui.c",
	"src/s_loader.c",
	"src/s_main.c",
	"src/s_net.c",
	"src/s_path.c",
	"src/s_print.c",
	"src/s_utf8.c",
	"src/x_acoustics.c",
	"src/x_arithmetic.c",
	"src/x_array.c",
	"src/x_connective.c",
	"src/x_file.c",
	"src/x_gui.c",
	"src/x_interface.c",
	"src/x_list.c",
	"src/x_midi.c",
	"src/x_misc.c",
	"src/x_net.c",
	"src/x_scalar.c",
	"src/x_text.c",
	"src/x_time.c",
	"src/x_vexp.c",
	"src/x_vexp_fun.c",
	"src/x_vexp_if.c",
};

pub const standalone = [_][]const u8{
	"src/s_file.c",
	"src/s_midi.c",
};

pub const alsa = [_][]const u8{
	"src/s_audio_alsa.c",
	"src/s_audio_alsamm.c",
	"src/s_midi_alsa.c",
};

pub const jack = [_][]const u8{
	"src/s_audio_jack.c",
};

pub const oss = [_][]const u8{
	"src/s_audio_oss.c",
	"src/s_midi_oss.c",
};

pub const portaudio = [_][]const u8{
	"src/s_audio_pa.c",
};

pub const dummy = [_][]const u8{
	"src/s_audio_dummy.c",
};

pub const paring = [_][]const u8{
	"src/s_audio_paring.c",
};

pub const watchdog = [_][]const u8{
	"src/s_watchdog.c",
};

pub const send = [_][]const u8{
	"src/u_pdsend.c",
	"src/s_net.c",
};

pub const receive = [_][]const u8{
	"src/u_pdreceive.c",
	"src/s_net.c",
};
