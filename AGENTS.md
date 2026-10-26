# AGENTS.md

Notes for coding agents (and people) working on this repository: Goose
bindings for raylib 6.2, published as the package `rl`, and honk, a 2D game
engine on top of them that ships as a module of that package
(`import rl.honk;`). README.md and HONK.md are the user-facing
documentation; this file is about changing the code.

## Files

| File | What it is | Edit it? |
|---|---|---|
| `rl.goose` | Generated bindings: constants, structs, `extern "raylib"` block, wrappers | **Never by hand.** Change `tools/gen_bindings.py` and regenerate |
| `tools/gen_bindings.py` | The generator, reads `tools/raylib_api.json` | Yes |
| `tools/raylib_api.json` | raylib's API description, copied from raylib's `tools/rlparser/output/` | Only to change raylib version |
| `rl_extras.goose` | Hand-written typed overloads for raylib's `void *` parameters | Yes |
| `raymath.goose` | Hand port of `raymath.h` | Yes, but keep it bit-identical to C (see below) |
| `rl.build` | Package sidecar: no C, `main_thread_only = true` | Rarely |
| `examples/*.goose` | Ports of raylib examples, each a root file importing `rl from ".."` | Yes |
| `test/smoke.goose` | Self-checking test against a real raylib; exits by itself | Yes, add checks for new behavior |
| `tools/check_layout.py` | Compares struct sizes/offsets with `raylib.h` via a C compiler | Yes |
| `tools/raymath_check.py` | Runs every raymath function in C and Goose, compares f32 bits | Yes |
| `tools/test.sh` | Runs all checks | Yes |
| `honk.goose` | The engine's entry: imports its modules | When adding a module |
| `honk/*.goose` | The engine: `engine` (run, scenes, frames, camera), `render` (draw list), `input`, `assets`, `sprite`, `store` | Yes |
| `examples/honk/*.goose` | Engine examples; `goose_grove` is a full game with an `--autoplay` computer player, `goose_galaxy` a stress test with `--bench` | Yes |
| `test/honk_test.goose` | Engine checks, on pixels of captured frames | Yes, add checks for new behavior |
| `HONK.md` | The engine's guide and API reference | Keep in step with the API |

After changing the generator: `python3 tools/gen_bindings.py`, and commit
the regenerated `rl.goose` with it (`tools/test.sh` fails if it is stale).

## Setting up a machine

None of this is installed by default. On Linux:

1. **Goose compiler from `main`**, not a release: v2026.3 lacks
   `extern "lib" { }` blocks and the `ffi` module.
   ```sh
   git clone --depth 1 --recurse-submodules --shallow-submodules https://github.com/aardappel/goose
   cmake -S goose -B goose/build -DCMAKE_BUILD_TYPE=Release && cmake --build goose/build -j8
   # compiler: goose/build/goose
   ```
2. **raylib 6.2 as a shared library** (needs `libxrandr-dev libxinerama-dev
   libxcursor-dev libxi-dev libgl1-mesa-dev` on Debian/Ubuntu):
   ```sh
   git clone --depth 1 --branch 6.2 https://github.com/raysan5/raylib
   cmake -S raylib -B raylib/build -DBUILD_SHARED_LIBS=ON -DBUILD_EXAMPLES=OFF -DCMAKE_BUILD_TYPE=Release
   cmake --build raylib/build -j8
   export LD_LIBRARY_PATH=$PWD/raylib/build/raylib
   ```
3. **A display**: on a headless machine run anything that opens a window
   under `xvfb-run -a`.

Then:

```sh
RAYLIB_SRC=path/to/raylib/src GOOSE=path/to/goose xvfb-run -a tools/test.sh
```

Expected: 202/202 layouts, 3268/3268 raymath results, examples typecheck,
54/54 smoke checks, 40/40 honk checks, goose_grove played to game over, and
goose_galaxy's screenshot saved. `goose check file.goose` typechecks without running.
`goose build --cc clang file.goose` checks a native build too.

To look at an example, run it in the background under Xvfb and grab the
screen with ImageMagick (`import -window root shot.png`), then kill it;
examples only exit when the window closes.

## How the bindings work (and why)

- Functions are members of `extern "raylib" { ... }`: bound from the shared
  library at startup, no C to compile, so `goose run` needs no toolchain.
  Keep it that way; don't add a C sidecar for convenience.
- Goose structs are **packed**. Every byte of C padding is an explicit
  field `_padN: u8[k] = [0, ...]` (with a default so literals can omit it).
  Not `pad`: a struct with `pad` cannot cross an extern by value.
  The generator refuses a padded struct of 16 bytes or less containing
  floats, because the filler could change its register class.
- Pointer fields and library-owned pointers are `u64`. Pointers to
  Goose-owned data are `T&` / `const T&`.
- A function taking `const char *` or a `(const T *, int count)` pair is
  bound as `c_Name` and wrapped by `Name` taking `const u8[:]` / `const T[:]`.
  Empty slices pass NULL through extra bindings of the same symbol
  (`c_Name_null_<param>`); an extern block may bind one symbol several
  times under different signatures. Strings get NULL only for functions
  listed in `NULLABLE_STRINGS`.
- Returned `const char *` / `char *` is copied with `ffi::cstr` unless the
  function allocates (name starts `Load`, ends `Alloc`, or is
  `EncodeDataBase64`); those return the `u64` for the caller to unload.
- Any pointer parameter of an `Unload*` function is `u64`.
- Callbacks, variadics and `long` are skipped and listed at the end of
  `rl.goose`; update README's "Not bound" list if that changes.
- Enum values are **untyped** `let`s so they fit `i32` and `u32` params.

## Goose gotchas met while writing this

- An untyped `let x = 800;` is `i64` and won't pass as `i32`: write
  `let x: i32 = 800;`. Literals in calls adapt fine.
- The compiler warns on redundant `as` casts; keep the tree warning-free.
  Float to int is `as!` (`label.x as! i32`).
- `assert(cond)` takes parentheses.
- `math` is in the global namespace: `sqrt(x)`, not `math::sqrt(x)`.
- Parameters are immutable; copy into a `var` to modify.
- A reference argument must be a variable, not a literal or temporary.
- Globals initialize in declaration order, so aliases of enum values are
  emitted after the enums.
- Goose keywords used as C names get a trailing `_` (`type` -> `type_`).
- `Matrix` fields are declared `m0, m4, m8, m12, m1, ...` as in C, so a
  positional `Matrix { ... }` fills it row by row, like a C initializer.
- A `return` in a block returns from the **function** the block is written
  in, even through other blocks: a `return` in a `honk::frames` body
  written inside a `honk::run` body ends the whole run body. Put a frame
  loop that should end on its own in a function of its own.
- When a generic parameter's type comes from an enum variant with a payload
  (`Scene.Play { .. }`), it is inferred as the variant type; pass the enum
  explicitly (`honk::scenes<Scene>(...)`).
- **Calling a block with a local `var` passes a copy.** In a HOF,
  `F(x)` with `var x` hands the block its own copy, and changes made in the
  block are lost. Write `F(&x)` (or `for &e in xs` then `F(e)`) to pass a
  reference.
- `pad` and the type names (`f32`, `i64`, ...) are keywords: they cannot
  name parameters, fields or functions.
- `for &e in xs { ... }` iterates by reference; `for e in xs` copies.
- A block may `return` from the function it is written in, through the HOF
  running it; `defer` in the HOF still runs. honk's scene exits rely on it.
- raylib batches 2D draws until a state change or `EndDrawing`; read the
  screen (`LoadImageFromScreen`) only after `rl::EndMode2D()` or a similar
  flush, or the last batch is missing.
- Newer compilers print nothing on success and have no `-q`; `--stats`
  shows what the compile did.

## honk: design rules

The engine is built on Goose's memory model. Keep it that way:

- **The engine owns no game state.** Game data lives in the scopes of the
  game's functions: the `honk::run` body for the whole program, a scene
  function for a scene, a frame iteration for draw commands. Don't add a
  registry, entity store or scene stack to the engine; a scene is a
  function, an overlay is a call.
- **Nothing allocates outside a scope.** Fixed-size state is inline
  (`Binding[..64]`, the frame's `rl::Shader[..15]` table, action bits in a
  `u64`). Per-frame data is in arrays local to the `honk::frames`
  iteration.
- **The draw list is a packed variable-mode `Cmd..` array plus an index of
  `Item`s** (sort key, shader slot, reference). A new drawing primitive is
  a new `Cmd` variant with a `draw` arm and a `bounds` arm (culling), a
  `Frame` method that records it, and a check in `test/honk_test.goose`.
  `ITEM_BYTES` must stay the size of `Item`.
- **Sort key** = pass << 56 | (layer + 32768) << 40 | sequence. Passes:
  `BACKGROUND` = 0, 1 kept for a future 3D world, `WORLD` = 2, `SCREEN` = 3.
  Post-processing covers the passes up to `WORLD`.
- **Measure before optimizing.** `goose_galaxy --bench --fast --plain` and
  `eng.stats` (sort/draw/present ms) split the frame. On this project's
  headless machines raylib draws through llvmpipe, so "draw" is CPU
  rasterizing, not honk. Circles once cost 18 quads each (raylib's fixed 36
  segments) and made the galaxy 7x slower; `segments()` now sizes them.
- **Non-Goose resources go on the asset stack** (`Asset` enum) so scopes
  unload them; a new resource kind is a new `Asset` variant and an
  `unload` arm.
- Pixel tests read frames with `honk::capture_next`/`honk::captured`. Its
  readback flushes raylib's batch first (see the gotchas).

## raymath must stay bit-identical

`tools/raymath_check.py` compares f32 bits, not approximately. When porting
or changing a function, do the same float operations in the same order as
`raymath.h`, including quirks: `Vector3Unproject` transposes through C's
positional initializers, and `MatrixCompose` multiplies `0*scale` so that
signed zeros match. Intentional API differences (`bool` for `*Equals`,
`f32[N]` arrays, references for out-params) are documented at the top of
`raymath.goose` and in README.

## Conventions

- Keep raylib's C names for anything raylib defines; the README promises
  raylib code ports directly.
- Comments are sentences, matching the existing files; generated
  declarations carry raylib's own descriptions.
- New behavior in the bindings gets a check in `test/smoke.goose` that
  verifies a result, not just that a call returns.
- Anything not yet tested (Windows, macOS) is said to be untested in README.
