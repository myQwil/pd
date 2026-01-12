# Pure Data

This is [Pd](https://puredata.info/)
packaged for [Zig](https://ziglang.org/).

## How to build

```sh
# Build the library (default)
zig build --release=fast
# Build the executable
zig build exe --release=fast
# Build and run the executable 
zig build run --release=fast
# System-wide installation
./install.sh exe --release=fast
```

### Build Options:
| Option | Description | Default |
| -------- | ------- | ------- |
| `-Dlinkage=[static,dynamic]` | Library linking method | `static` |
| `-Dutils=[bool]` | Lib: Enable utilities | `true` |
| `-Dextra=[bool]` | Lib: Include extra objects | `true` |
| `-Dmulti=[bool]` | Lib: Compile with multiple instance support | `false` |
| `-Dsetlocale=[bool]` | Lib: Set LC_NUMERIC automatically with setlocale() | `true` |
| `-Dfloat_size=[int]` | Size of a floating-point number | `32` |
| `-Dlocales=[bool]` | Compile localizations (requires gettext) | `true` |
| `-Dwatchdog=[bool]` | Build watchdog | `true` |
| `-Dfftw=[bool]` | Use FFTW package | `false` |
| `-Dportaudio=[bool]` | Use portaudio | `true` |
| `-Dlocal_portaudio=[bool]` | Use local portaudio | `false` |
| `-Dportmidi=[bool]` | Use portmidi | `true` |
| `-Dlocal_portmidi=[bool]` | Use local portmidi | `false` |
| `-Doss=[bool]` | Use OSS driver | `true` |
| `-Dalsa=[bool]` | Use ALSA audio driver | `true` |
| `-Djack=[bool]` | Use JACK audio server | `false` |
| `-Dmmio=[bool]` | Use MMIO driver | `true` |
| `-Dasio=[bool]` | Use ASIO audio driver | `true` |
| `-Dwasapi=[bool]` | Use WASAPI backend | `true` |


## How to add pd to a zig project
First, update your `build.zig.zon`:

```sh
zig fetch --save git+https://github.com/myQwil/pd#v0.56.2-3
```

Next, add this snippet to your `build.zig` script:

```zig
const pd_dep = b.dependency("pd", .{
    .target = target,
    .optimize = optimize,
});
// To link a module with libpd:
module.linkLibrary(pd_dep.artifact("pd"));
// To import the libpd module:
module.addImport("pd", pd_dep.module("libpd"));
// To import the pd module for externals
module.addImport("pd", pd_dep.module("pd"));
```
