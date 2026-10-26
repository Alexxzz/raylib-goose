// honk: a small 2D game engine on raylib, built around Goose's memory model.
//
//   import rl from "github.com/alexxzz/raylib-goose@<commit>";
//   import rl.honk;
//
// The engine owns the window, the frame loop, input actions, a sorted and
// culled draw list, shaders and post-processing, and the lifetime of loaded
// assets. Game state is never the engine's: it lives in the scopes of the
// game's own functions, and those scopes decide when it is freed.
//
//   * A run (honk::run) owns what lasts for the whole program.
//   * A scene is a function. Its state is its locals; when it returns the
//     next scene, all of it is freed in one store, and the textures, sounds
//     and shaders it loaded are unloaded (honk::scenes).
//   * An overlay, such as a pause menu, is a plain call from inside a scene:
//     the scene's data stays alive beneath it, as on any stack.
//   * A frame's draw commands are packed into one array of variable-size
//     commands, sorted through an index of references, drawn, and freed in
//     one store when the frame ends (honk::frames).
//
// HONK.md describes the design; examples/honk/ shows it in use.

namespace honk;

import .honk.engine;
import .honk.input;
import .honk.render;
import .honk.assets;
import .honk.sprite;
import .honk.store;
