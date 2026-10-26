# raylib-goose

[raylib](https://www.raylib.com) 6.2 bindings for the
[Goose programming language](https://aardappel.github.io/goose/).

```goose
import rl from "github.com/alexxzz/raylib-goose@main";

fn main() {
    rl::InitWindow(800, 450, "raylib [core] example - basic window");
    rl::SetTargetFPS(60);

    while !rl::WindowShouldClose() {
        rl::BeginDrawing();
        rl::ClearBackground(rl::RAYWHITE);
        rl::DrawText("Congrats! You created your first window!", 190, 200, 20, rl::LIGHTGRAY);
        rl::EndDrawing();
    }

    rl::CloseWindow();
}
```

The package is called `rl`. Every raylib function, struct, enum value and
color keeps its C name, in the namespace `rl`, so raylib's examples and
cheatsheet carry over directly: `DrawCircleV` is `rl::DrawCircleV`,
`KEY_SPACE` is `rl::KEY_SPACE`.

* **606 of raylib's 619 functions**, generated from raylib's own API
  description (`tools/raylib_api.json`).
* **All 35 structs**, laid out exactly as C lays them out (checked
  against `raylib.h` by `tools/check_layout.py`).
* **All of raymath** (146 functions), ported to Goose, since raymath is a C
  header and not part of the library. Its results are bit-identical to the C
  header's (`tools/raymath_check.py`).
* **No C to compile.** The functions are bound from the raylib shared
  library when the program starts (Goose's `extern "raylib" { ... }`), so
  `goose run` works with no C toolchain installed.
* **honk, a 2D game engine** on top of the bindings (`import rl.honk;`).
  It provides scenes, input actions, a sorted and culled draw list, shaders
  and post-processing, sprites, asset lifetimes and saving, all built around
  Goose's memory model. See [HONK.md](HONK.md).

## Installing

You need a Goose compiler recent enough to have `extern "lib" { ... }`
blocks and the `ffi` module (Goose's `main` branch as of October 2026; the
v2026.3 release predates them), and the raylib 6.2 shared library:

* **Windows**: `raylib.dll` from a
  [raylib release](https://github.com/raysan5/raylib/releases), beside your
  program or on `PATH`.
* **macOS**: `brew install raylib` gives `libraylib.dylib`.
* **Linux**: build raylib with `-DBUILD_SHARED_LIBS=ON` and install it, or
  use your distribution's package if it has 6.2.

The program opens `raylib.dll`, `libraylib.dylib` or `libraylib.so`, found
the way the platform's loader finds libraries (`PATH`,
`DYLD_LIBRARY_PATH`, `LD_LIBRARY_PATH`, rpath, ...). If yours has another
name, map it in your program's sidecar (`yourprog.build` beside
`yourprog.goose`):

```goose
dylibs_linux = ["raylib=libraylib.so.620"];
dylibs_windows = ["raylib=bin/raylib.dll"];      // shipped beside the program
```

Then import the package in your program's root file. Pin a commit for a
reproducible build:

```goose
import rl from "github.com/alexxzz/raylib-goose@<commit>";
import rl from "../raylib-goose";                 // or a local checkout
```

## Examples

`examples/` holds ports of raylib examples. Run one from a checkout:

```sh
goose run examples/core_basic_window.goose
goose build examples/core_3d_camera.goose && ./examples/core_3d_camera
```

| Example | Shows |
|---|---|
| `core_basic_window` | The minimal window loop |
| `shapes_bouncing_ball` | Keyboard and mouse input, raymath, `str()` in place of `TextFormat` |
| `core_3d_camera` | `Camera3D`, `UpdateCamera(camera, ...)` through a reference, `GetWorldToScreen` |
| `textures_plasma` | Pixels computed in Goose and uploaded with `UpdateTexture` |
| `shaders_uniforms` | `LoadShaderFromMemory` with the default vertex shader, `SetShaderValue` |
| `honk/hello` | The honk engine in 40 lines |
| `honk/goose_grove` | A complete game on honk: scenes, a pause overlay, pools, particles, shaders, saved scores |

## How C types map to Goose

| C | Goose |
|---|---|
| `int`, `unsigned int`, `float`, `double`, `bool`, `unsigned char` | `i32`, `u32`, `f32`, `f64`, `bool`, `u8` |
| `Vector2`, `Color`, `Rectangle`, ... by value | `rl::Vector2`, `rl::Color`, `rl::Rectangle`, ... by value |
| `const char *` argument | `const u8[:]`: pass `"text"` or any `u8` array |
| `const char *` result | `u8[>..]`, a copy of the string |
| `const Vector2 *points, int pointCount` | one slice, `const rl::Vector2[:]` |
| `Camera *`, `Image *`, `int *` (in/out) | `rl::Camera&`, `rl::Image&`, `i32&`: pass a variable |
| pointers the library owns (`Image.data`, `LoadFileData`'s result, ...) | `u64` |
| enum values, `#define`d colors | named constants: `rl::KEY_SPACE`, `rl::RAYWHITE` |

Some details:

* **Strings.** A wrapper copies the slice into a NUL-terminated buffer and
  calls the C function, which is bound as `rl::c_Name` taking `const u8&`
  (a pointer to the first byte). A function returning a string the library
  allocates (`LoadFileText`, `LoadUTF8`, `TextReplaceAlloc`, ...) still
  returns the `u64`, to copy with `ffi::cstr(p)` and free with the matching
  `Unload*`. For `LoadShader`, `LoadShaderFromMemory` and
  `LoadDirectoryFilesEx`'s filter, an empty string passes `NULL`, so
  `rl::LoadShader("", "fx.fs")` keeps the default vertex shader.
* **Arrays.** A `(pointer, count)` pair becomes one slice argument, and an
  empty slice passes `NULL`: `rl::LoadFontEx("font.ttf", 32, [])` loads the
  default character set.
* **References.** Goose passes a reference to a variable, not to a
  literal: `var camera = rl::Camera3D { ... }; rl::UpdateCamera(camera, rl::CAMERA_FREE);`.
* **Integers.** raylib takes `int` where Goose's integer literals and
  untyped `let`s default to `i64`, so declare the type of a variable you
  pass (`let w: i32 = 800;`) or convert (`x as i32`). The enum values are
  untyped constants and fit either `int` or `unsigned int`.
* **Formatting.** `TextFormat` is variadic and cannot be bound; build the
  text with Goose's `str(...)`: `rl::DrawText(str("score: ", score), 10, 10, 20, rl::BLACK)`.
* **Typed data.** raylib's `const void *` parameters are `u64` in the
  generated bindings. `rl_extras.goose` adds typed overloads for the common
  ones: `SetShaderValue` with an `f32`, `i32` or vector variable,
  `SetShaderValueV` with a slice, `UpdateTexture`/`UpdateTextureRec` with
  `rl::Color` slices, `UpdateSound`/`UpdateAudioStream` with `i16` or `f32`
  samples, `UpdateMeshBuffer` with `f32` data, and `SaveFileData` with bytes.
* **raymath** follows `raymath.h`, except that the `*Equals` functions
  return `bool`, `Vector3ToFloatV`/`MatrixToFloatV` return `f32[3]`/`f32[16]`,
  and out-parameters are references.
* **Threads.** The package's sidecar sets `main_thread_only`, so the
  compiler rejects raylib calls from a `thread_fn`.

### Not bound

The 13 functions that cannot be called through a plain C prototype:

* the variadic `TraceLog` and `TextFormat` (use `print` and `str`);
* the ones taking C callbacks: `SetTraceLogCallback`,
  `SetLoadFileDataCallback`, `SetSaveFileDataCallback`,
  `SetLoadFileTextCallback`, `SetSaveFileTextCallback`,
  `SetAudioStreamCallback`, `AttachAudioStreamProcessor`,
  `DetachAudioStreamProcessor`, `AttachAudioMixedProcessor`,
  `DetachAudioMixedProcessor`;
* `GetFileModTime`, which returns a C `long`, 32 bits on Windows and 64
  elsewhere.

## Layout

```
rl.goose            the bindings, generated: structs, constants, externs, wrappers
rl_extras.goose     hand-written typed overloads for raylib's void * parameters
raymath.goose       raymath, ported to Goose
rl.build            the package's sidecar (no C; main_thread_only)
honk.goose, honk/   the honk engine, a module of the package (HONK.md)
examples/           ports of raylib examples; examples/honk/ for the engine
test/smoke.goose    calls a wide sample of the API against real raylib and checks the results
test/honk_test.goose  checks the engine, on rendered pixels
tools/              the generator and the checks
```

## Contributing

See [AGENTS.md](AGENTS.md) for how the generator works, setting up a
machine to run the tests, and the conventions to keep.

## Regenerating and testing

`rl.goose` is generated; change `tools/gen_bindings.py`, not the output.
For another raylib version, copy that version's
`tools/rlparser/output/raylib_api.json` over `tools/raylib_api.json` and
run:

```sh
python3 tools/gen_bindings.py
```

`tools/test.sh` checks that `rl.goose` matches the generator, that every
struct matches `raylib.h`, and that raymath matches `raymath.h`. It also
checks that the examples typecheck, runs the smoke test and the engine test,
and plays `goose_grove` through every scene. Those open a window, so use
`xvfb-run` without a display:

```sh
RAYLIB_SRC=path/to/raylib/src GOOSE=goose tools/test.sh
```

All of it passes on Linux x64 with raylib 6.2, under `goose run` (the
in-process TinyCC backend) and in executables built with gcc and clang.
Windows and macOS have not been tested yet.

## Credits

`tools/raylib_api.json` is from raylib, (c) Ramon Santamaria and
contributors, under the zlib license; `raymath.goose` is a port of raylib's
`raymath.h`, under the same license.
