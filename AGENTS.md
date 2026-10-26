# AGENTS.md

Notes for coding agents (and people) working on this repository: Goose
bindings for raylib 6.2, published as the package `rl`. README.md is the
user-facing documentation; this file is about changing the code.

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
54/54 smoke checks. `goose check -q file.goose` typechecks without running.
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
