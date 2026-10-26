# honk

A small 2D game engine for [Goose](https://aardappel.github.io/goose/), on
the raylib bindings in this repository. It runs the window and the frame
loop, scenes, input actions, a sorted and culled draw list with shaders and
post-processing, sprite sheets, the lifetime of loaded assets, and saving.

It is designed around Goose's memory model, which has no heap and frees a
scope's data in one store when the scope ends. Where data lives in a honk
game follows from where the game's code declares it. Nothing in honk
allocates, and the engine never owns game state.

```goose
import rl from "github.com/alexxzz/raylib-goose@<commit>";
import rl.honk;

let JUMP = 0;

fn main() {
    honk::run(honk::Config { title: "hello", width: 800, height: 450 }) { eng =>
        honk::bind_key(eng, JUMP, rl::KEY_SPACE);
        honk::frames(eng) { f =>
            if f.pressed(JUMP) { honk::shake(eng, 0.5); }
            f.circle(rl::Vector2 { 0.0, 0.0 }, 40.0, rl::GOLD);      // the world, through the camera
            f.screen();
            f.text("Space shakes the camera", rl::Vector2 { 10.0, 10.0 }, 20.0, rl::WHITE);
        };
    };
}
```

`honk` is a module of the `rl` package, so a program that imports `rl` has
it: `import rl.honk;`, and everything is in the namespace `honk`.

Examples:

* [`examples/honk/hello.goose`](examples/honk/hello.goose) shows a camera,
  input and text in 40 lines.
* [`examples/honk/goose_galaxy.goose`](examples/honk/goose_galaxy.goose)
  is a stress test: up to a million geese orbit in a spiral galaxy. You can
  zoom from the whole galaxy down to one goose flapping its wings, with level
  of detail chosen by the zoom, and click to send honk shockwaves through the
  flock. `-- --bench --fast` prints frame times for 4 000 to 256 000 geese.
* [`examples/honk/goose_grove.goose`](examples/honk/goose_grove.goose) is a
  complete game. It has title, play and game-over scenes and a pause overlay.
  Foxes and honks live in reusable pools, and there are particles. Its sprites
  are drawn in code and its sound is synthesized. It uses a water shader, a
  vignette post-process, and a saved high score table. Run it with
  `-- --autoplay` to watch a computer player.

## Where data lives

| Scope | Lives as long as | Holds |
|---|---|---|
| `honk::run(config) { eng => ... }` | the program | the engine, and what every scene shares: sprite sheets, sounds, settings, high scores |
| a scene function | the scene | the scene's world: entities, particles, decoration, the textures and shaders it loaded |
| a call inside a scene (an overlay) | the overlay | the overlay's own state; the scene's world stays alive beneath it |
| one iteration of `honk::frames` | one frame | the frame's draw commands and their sort index |

**A scene is a function.** `honk::scenes` calls one scene function at a
time. When the first scene is a variant with a payload, name the enum:
`honk::scenes<Scene>(eng, Scene.Play { level: 1 })`. The function returns the next scene, a value of the game's own enum.
Its locals are the scene's state, so returning frees all of it in one store.
The engine then unloads the GPU and audio resources the scene loaded.

```goose
enum Scene { Title, Play { level: i32 }, Over { score: i32 } }

honk::scenes(eng, Scene.Title) { s =>
    match s {
        Title => title(eng),
        Play p => play(eng, p.level),
        Over o => over(eng, o.score),
    }
};

fn play(eng: honk::Engine&, level: i32) -> Scene {
    reusable var enemies: Enemy[>..] = [];         // the scene's state: its locals
    let tiles = honk::load_texture(eng, "tiles.png");   // unloaded when the scene ends
    honk::frames(eng) { f =>
        if lost() { return Scene.Over { score: score }; }   // ends the scene
        ...
    };
    return Scene.Title;                            // the window was closed
}
```

**An overlay is a call.** A pause menu, an inventory, or a dialog is a function
the scene calls from inside its frame loop. It runs its own frame loop and
returns a result. The scene's data is still alive beneath it, so the overlay
can draw the scene's world behind itself through a struct of references,
with no copy and no scene stack to manage:

```goose
if f.pressed(PAUSE) {
    if !pause(eng, round) { return Scene.Title; }   // round: references to play's locals
}
```

The compiler checks that the scene's functions do not call each other in a
cycle (an overlay that opened the scene that opened it). Such a cycle would
be recursion that holds growable data across the call, which Goose rejects.

**A frame's draw list is two arrays local to the frame.** The first holds
the commands. They are variable-mode enum values, so each takes the bytes of
its own variant, and a text or a polyline is stored inside its command at its
exact length: drawing the text `hello` takes 28 bytes. That array can only
be walked, so the second array is the index the tutorial describes: one
17-byte entry per command, holding a sort key, a shader slot and a reference
to the command. Sorting moves only the entries. When the iteration ends, both
arrays are freed in one store. A scene that `return`s from the middle of a
frame leaves nothing half drawn, because nothing is drawn until the body
has finished.

**Entities live in the scene, in whatever shape suits them.** `goose_grove`
keeps foxes and honks in `reusable` pools. A reference to a fox stays valid
while more foxes are pushed, and killing one hands its slot back with
`free`. Particles live in a grow-shrink array that is compacted in place each
frame. Decoration lives in a plain grow-only array. Code that needs several
of these tables at once (drawing, the pause menu) gets a struct of references
to them:

```goose
struct Round { player: Player&, foxes: Fox[>..]&, particles: Particle[>..<]&, points: i32 }
```

**Fixed-size state stays inline.** The engine's 64 input bindings are a
`Binding[..64]` inside the engine struct, and the state of every action is
one `u64` a frame. A frame's shader and font tables are fixed-capacity
arrays inside the frame struct.

**Assets follow the scopes.** GPU textures and audio buffers are not Goose
memory, so no scope frees them. honk keeps every loaded resource on a stack
instead. The end of a scene, the end of a `honk::scope { }`, and the end of
the run each unload what was loaded since that scope began, latest first.
Load functions return raylib's own values (`rl::Texture`, `rl::Shader`), which
commands copy. Using one after its scope has ended draws nothing; it never
touches freed memory.

**Saved data is the data.** An array of flat values (fixed structs, inline
strings, self-relative links) contains no pointers. `honk::save` writes its
bytes, and `honk::load` reads them back through `from_bytes`. That verifies
every length, tag and link, so a damaged file loads as `false` rather than
as a bad value.

## The API

### Running

| | |
|---|---|
| `honk::run(config) { eng => ... }` | opens the window, runs the body, closes everything |
| `honk::Config { ... }` | `width`, `height`, `title`, `fps` (0: uncapped), `flags`, `clear`, `audio`, `exit_key` (0: none), `debug_key` (F1), `max_frames` (0: no limit) |
| `honk::scenes(eng, first) { s => ... }` | runs scene functions until the run ends |
| `honk::frames(eng) { f => ... }` | a frame loop: the body records, honk draws |
| `honk::running(eng)`, `honk::quit(eng)` | whether the run goes on; end it after this frame |
| `honk::fixed(f, step) { ... }` | the body once per `step` seconds of frame time |
| `eng.dt`, `eng.time`, `eng.frame`, `eng.camera`, `eng.debug`, `eng.stats` | engine state; `f.dt`, `f.time`, `f.index` per frame |

### Drawing

Commands are drawn in passes. The background comes first, in screen pixels
(skies, backdrops). Then the world, through `eng.camera`. Then the screen,
in pixels on top (HUD, menus). Within a pass they are drawn by `f.layer`
(higher layers on top), then in the order they were recorded. World commands
outside the camera's view are culled. Circles and rings get as many segments
as their size on the screen needs, so a dot costs a few triangles rather than
raylib's fixed 36.

| | |
|---|---|
| `f.background()`, `f.world()`, `f.screen()` | the pass for the commands recorded next |
| `f.layer = n` | the layer for the commands recorded next, -32768..32767 |
| `f.use_shader(s)`, `f.no_shader()` | a fragment shader for the commands recorded next |
| `f.use_font(font)`, `f.default_font()` | the font for text recorded next |
| `f.rect(r, color)`, `f.rect(center, size, degrees, color)`, `f.rect_lines(r, thick, color)` | rectangles |
| `f.circle`, `f.circle_lines`, `f.ring`, `f.poly`, `f.triangle` | shapes |
| `f.line(a, b, thick, color)`, `f.lines(points, thick, color)` | lines; `lines` copies the points into the command |
| `f.texture(t, pos, tint)`, `f.sprite(t, src, dst, origin, degrees, tint)` | textures |
| `f.sprite(sheet, frame, center, scale, degrees, flip, tint)` | a frame of a sprite sheet |
| `f.text(s, pos, size, color)`, `f.text_centered(s, center, size, color)`, `f.measure(s, size)` | text, copied into the command |
| `f.width()`, `f.height()` | the screen's size |
| `honk::follow(eng, target, rate)`, `honk::clamp_camera(eng, bounds)`, `honk::shake(eng, amount)` | the camera |
| `honk::zoom_at(eng, screen_point, factor)`, `honk::pan(eng, screen_delta)` | zoom keeping a point (the mouse) in place; drag the world |
| `f.view()` | the world rectangle the camera shows, to skip recording what is off screen |
| `honk::post_process(eng, shader)`, `honk::no_post_process(eng)` | a fragment shader over the drawn background and world passes |
| `honk::capture_next(eng)`, `honk::captured(eng)` | an `rl::Image` of the next frame |

F1 shows a debug overlay: frame rate, commands drawn and culled, the draw
list's bytes, assets loaded, and the time spent sorting, drawing and
presenting. The same numbers are in `eng.stats`.

### Input

A game names its actions as integers 0..63 and binds inputs to them. Several
inputs can drive one action.

| | |
|---|---|
| `honk::bind_key`, `bind_mouse`, `bind_pad`, `bind_axis(eng, action, axis, positive)`, `unbind_all` | bindings |
| `f.down(a)`, `f.pressed(a)`, `f.released(a)` | an action's state this frame |
| `f.axis(neg, pos)`, `f.direction(left, right, up, down)` | -1..1, and a normalized direction |
| `f.mouse()`, `f.mouse_world()`, `f.mouse_delta()`, `f.wheel()` | the mouse on the screen and in the world, its movement, the wheel |
| `honk::press(eng, a)` | holds an action down next frame: tests, replays, computer players |

### Assets

| | |
|---|---|
| `honk::load_texture`, `honk::bake(eng, image)` | textures; `bake` uploads an `rl::Image` and frees it |
| `honk::shader(eng, fragment)`, `honk::shader(eng, vertex, fragment)`, `honk::load_shader` | shaders from source or files; empty for raylib's default |
| `honk::set_uniform(shader, name, value)` | `f32`, `rl::Vector2` or `rl::Vector4` |
| `honk::load_font`, `honk::render_texture` | fonts, render targets |
| `honk::load_sound`, `honk::sound(eng, ".wav", bytes)`, `honk::load_music`, `honk::play_music`, `honk::stop_music` | audio; music streams in the frame loop |
| `honk::mark`, `honk::release`, `honk::scope(eng) { ... }` | unload what a part of a scene loaded |

### Sprites and saving

| | |
|---|---|
| `honk::Sheet { texture, cols, rows }`, `honk::frame_rect(sheet, i)` | a texture cut into a grid |
| `honk::Anim { first, count, fps, looping }`, `honk::frame_at(anim, t)`, `honk::finished(anim, t)` | frame animation |
| `honk::save(path, array)`, `honk::load<T>(path) -> T[>..], bool` | arrays of flat values to and from files |

## Toward 3D

3D is not there yet, but the design leaves room for it:

* Passes are numbers in the sort key, and pass 1 is kept free for a 3D world
  drawn between the background and the 2D world. A 3D pass would begin and end `BeginMode3D` with an
  `rl::Camera3D` kept in the engine, as the world pass does with the 2D
  camera.
* Commands are an enum, so models, meshes, billboards and 3D primitives are
  new variants with their own draw and bounds cases. Culling becomes a
  frustum test for that pass.
* The asset stack gains `Model` and `Mesh` variants and unloads them like
  textures.
* Scenes, frames, input, assets and saving do not depend on the
  dimension.

## Performance

`goose_galaxy --bench --fast --plain` measures frame times. These are from a
native build (`goose build`) on a Linux machine with no GPU: raylib draws
through Mesa's llvmpipe, which rasterizes on the CPU. A real GPU makes the
draw column much smaller; the update and record columns are Goose's.

| geese | zoomed out: ms per frame | update + record | zoomed in, game culls |
|---:|---:|---:|---:|
| 4 000 | 5.5 | 0.3 | 6.6 |
| 16 000 | 17.3 | 1.0 | 4.5 |
| 64 000 | 66.2 | 4.5 | 8.2 |
| 256 000 | 135.6 | 18.1 | 21.6 |

Notes:

* honk's own cost is small. Sorting is almost free, because the index is
  nearly in order already. Drawing 64 000 rectangles through honk measured
  the same as calling raylib directly.
* With very many objects, skip what is off screen before recording it
  (`f.view()`). honk culls anything it is given, but recording costs about
  70 ns a command. Zoomed in on 256 000 geese, game-side culling takes 23 ms
  a frame where honk-side culling takes 42 ms (`--honk-culls`).
* Pick a cheaper primitive for small things: the galaxy draws geese as
  rectangles below 6 pixels, dots up to 14, sprites above.
* The flock lives in the galaxy scene, so `+` and `-` return a new scene.
  The old flock (36 bytes a goose, 37 MB at the most) is freed in one store,
  and the new one is built in milliseconds.

## Tests

`test/honk_test.goose` checks the engine against real raylib, reading
rendered pixels back from captured frames. It covers scenes and asset
lifetimes, input, draw order, the screen pass, the camera, culling counts,
command packing, shaders, uniforms, post-processing, sprites, fixed steps,
and save/load (including damaged files). `tools/test.sh` runs it, then plays
`goose_grove` through every scene with the computer player and checks that
it reached game over and saved the score. It also draws `goose_galaxy` with
50 000 geese and checks that its screenshot was saved.
