// honk: the window, the run, scenes and the frame loop.

namespace honk;

import std;
import math;
import rl;

// Draw passes, in drawing order. A command is drawn in the pass that was
// current when it was recorded (Frame.space). Pass 0 is kept for a 3D world,
// drawn under the 2D one, when the engine grows one.
let WORLD = 1;      // through the 2D camera, culled against its view
let SCREEN = 2;     // in screen pixels, over the world: HUD, menus

struct Config {
    width: i32 = 960,
    height: i32 = 540,
    title: u8[..64] = "honk",
    fps: i32 = 60,                      // 0: as fast as the display allows
    flags: u32 = 0,                     // rl::FLAG_* for rl::SetConfigFlags
    clear: rl::Color = rl::Color { 24, 26, 32, 255 },
    audio: bool = false,                // open the audio device
    exit_key: i32 = 0,                  // raylib closes the window on this key; 0: none
    debug_key: i32 = rl::KEY_F1,        // toggles the debug overlay; 0: none
    max_frames: i64 = 0,                // stop after this many frames (tests); 0: no limit
}

// What the last frame did, for the debug overlay and for tests.
struct Stats {
    commands: i64,          // commands recorded
    drawn: i64,
    culled: i64,            // world commands outside the camera's view
    command_bytes: i64,     // bytes of the packed command array
    index_bytes: i64,       // bytes of the index sorting it
}

// The engine: fixed-size state plus a reference to the asset stack, which is
// a local of honk::run. It is passed by reference to everything.
struct Engine {
    config: Config,
    assets: Asset[>..<]&,
    bindings: Binding[..64],            // input actions, inline: no allocation
    now: u64,                           // actions down this frame, one bit each
    before: u64,                        // actions down the frame before
    forced: u64,                        // actions honk::press holds down next frame
    camera: rl::Camera2D,
    trauma: f32,                        // camera shake, 0..1, decays
    time: f64,                          // seconds since the run started
    dt: f32,                            // seconds since the last frame, at most 0.1
    frame: i64,                         // frames since the run started
    accumulator: f32,                   // honk::fixed's unspent time
    quit: bool,
    debug: bool,
    post: rl::Shader,                   // post-processing of the world pass
    has_post: bool,
    target: rl::RenderTexture,          // the world pass, when post-processed
    has_target: bool,
    music: rl::Music,                   // streamed by the frame loop
    has_music: bool,
    capture: bool,                      // keep the next frame as an image
    captured: rl::Image,
    has_captured: bool,
    stats: Stats,
}

// Opens the window, runs body(eng), and closes everything. What body loads
// lasts for the whole run; scenes started from it unload their own.
//
//   honk::run(honk::Config { title: "Goose" }) { eng =>
//       var game = Game { .. };                  // outlives every scene
//       honk::scenes(eng, Scene.Title) { s => ... };
//   };
fn run<F>(config: Config) {
    rl::SetConfigFlags(config.flags);
    rl::InitWindow(config.width, config.height, config.title);
    rl::SetExitKey(config.exit_key);
    if config.fps > 0 { rl::SetTargetFPS(config.fps); }
    if config.audio { rl::InitAudioDevice(); }

    var assets: Asset[>..<] = [];
    var eng = Engine {
        config: config,
        assets: assets,
        bindings: [],
        now: 0, before: 0, forced: 0,
        camera: rl::Camera2D { rl::Vector2 { 0.0, 0.0 }, rl::Vector2 { 0.0, 0.0 }, 0.0, 1.0 },
        trauma: 0.0,
        time: 0.0, dt: 0.0, frame: 0, accumulator: 0.0,
        quit: false, debug: false,
        post: rl::Shader { .. }, has_post: false,
        target: rl::RenderTexture { .. }, has_target: false,
        music: rl::Music { .. }, has_music: false,
        capture: false, captured: rl::Image { .. }, has_captured: false,
        stats: Stats { 0, 0, 0, 0, 0 },
    };
    defer {
        release(eng, 0);
        if eng.has_captured { rl::UnloadImage(eng.captured); }
        if eng.has_target { rl::UnloadRenderTexture(eng.target); }
        if config.audio { rl::CloseAudioDevice(); }
        rl::CloseWindow();
    }
    F(&eng);       // the engine itself, not a copy
}

// Whether the run goes on: no honk::quit, the window open, frames left.
fn running(eng: Engine&) -> bool {
    !eng.quit && !rl::WindowShouldClose() &&
        (eng.config.max_frames == 0 || eng.frame < eng.config.max_frames)
}

// Ends the run after the current frame.
fn quit(eng: Engine&) { eng.quit = true; }

// Runs scenes until the run ends. body(scene) runs one scene and returns the
// one after it; S is the game's own scene type, usually an enum:
//
//   honk::scenes(eng, Scene.Title) { s =>
//       match s { Title => title(eng), Play p => play(eng, p.level), Over o => over(eng, o.score) }
//   };
//
// The scene's locals are freed when its function returns, and the assets it
// loaded are unloaded here, after it.
fn scenes<S, F>(eng: Engine&, first: S) {
    var scene = first;
    while running(eng) {
        let mark = eng.assets.len;
        scene = F(scene);
        release(eng, mark);
    }
}

// The frame loop of a scene: calls body(f) once per frame until the run
// ends, and draws what it recorded. The scene ends by returning from inside
// the body, which leaves the loop with the frame undrawn:
//
//   honk::frames(eng) { f =>
//       if f.pressed(START) { return Scene.Play { level: 1 }; }
//       f.text("Press Enter", rl::Vector2 { 40.0, 40.0 }, 20.0, rl::WHITE);
//   };
//
// Each frame's commands live in two arrays local to the iteration: the
// packed commands and the index that sorts them. Ending the iteration frees
// both in one store.
fn frames<F>(eng: Engine&) {
    while running(eng) {
        begin_frame(eng);
        var cmds: Cmd..[>..] = [];
        var order: Item[>..] = [];
        var f = Frame {
            eng: eng,
            dt: eng.dt, time: eng.time, index: eng.frame,
            layer: 0, space: WORLD, shader: 0, font: 0, seq: 0,
            shaders: [], fonts: [],
            cmds: cmds, order: order,
        };
        F(&f);     // the frame itself, not a copy: flush reads what the body set
        flush(f);
        eng.frame++;
    }
}

fn begin_frame(eng: Engine&) {
    eng.dt = min(rl::GetFrameTime(), 0.1);
    eng.time = rl::GetTime();
    if eng.config.debug_key != 0 && rl::IsKeyPressed(eng.config.debug_key) { eng.debug = !eng.debug; }
    if eng.has_music { rl::UpdateMusicStream(eng.music); }
    eng.trauma = max(eng.trauma - eng.dt*1.5, 0.0);
    poll(eng);
}

// Calls body() once per step of `step` seconds of frame time, carrying the
// remainder to the next frame: a fixed-rate simulation inside a frame.
fn fixed<F>(f: Frame&, step: f32) {
    let eng .= f.eng;
    eng.accumulator = min(eng.accumulator + f.dt, step*8.0);
    while eng.accumulator >= step {
        F();
        eng.accumulator -= step;
    }
}

// --- the camera ----------------------------------------------------------------

// Centers the camera on the screen and moves its target toward `target`,
// covering `rate` of the distance per second (a rate of 8 settles in about
// half a second).
fn follow(eng: Engine&, target: rl::Vector2, rate: f32) {
    eng.camera.offset = rl::Vector2 { rl::GetScreenWidth()/2.0, rl::GetScreenHeight()/2.0 };
    let t = 1.0 - rl::Clamp(exp(-rate*eng.dt), 0.0, 1.0);
    eng.camera.target = rl::Vector2Lerp(eng.camera.target, target, t);
}

// Keeps the camera's view inside `bounds`, a rectangle of the world.
fn clamp_camera(eng: Engine&, bounds: rl::Rectangle) {
    let half_w = eng.camera.offset.x/eng.camera.zoom;
    let half_h = eng.camera.offset.y/eng.camera.zoom;
    eng.camera.target.x = rl::Clamp(eng.camera.target.x, bounds.x + half_w, bounds.x + bounds.width - half_w);
    eng.camera.target.y = rl::Clamp(eng.camera.target.y, bounds.y + half_h, bounds.y + bounds.height - half_h);
}

// Shakes the camera: amount adds to a trauma level that decays over about a
// second. The shake moves the drawing only, not the camera mouse_world uses.
fn shake(eng: Engine&, amount: f32) { eng.trauma = min(eng.trauma + amount, 1.0); }

// The camera the world pass is drawn with: eng.camera plus the shake.
fn shaken_camera(eng: Engine&) -> rl::Camera2D {
    var camera = eng.camera;
    let s = eng.trauma*eng.trauma;
    if s > 0.0 {
        let t = eng.time as f32;
        camera.offset.x += 12.0*s*sin(t*53.0);
        camera.offset.y += 12.0*s*sin(t*61.0 + 1.3);
        camera.rotation += 2.0*s*sin(t*47.0 + 2.1);
    }
    return camera;
}

// The rectangle of the world the camera sees, rotation included, for culling.
fn view_bounds(camera: rl::Camera2D) -> rl::Rectangle {
    let w = rl::GetScreenWidth();
    let h = rl::GetScreenHeight();
    let a = rl::GetScreenToWorld2D(rl::Vector2 { 0.0, 0.0 }, camera);
    let b = rl::GetScreenToWorld2D(rl::Vector2 { w, 0.0 }, camera);
    let c = rl::GetScreenToWorld2D(rl::Vector2 { 0.0, h }, camera);
    let d = rl::GetScreenToWorld2D(rl::Vector2 { w, h }, camera);
    let lo = rl::Vector2Min(rl::Vector2Min(a, b), rl::Vector2Min(c, d));
    let hi = rl::Vector2Max(rl::Vector2Max(a, b), rl::Vector2Max(c, d));
    return rl::Rectangle { lo.x, lo.y, hi.x - lo.x, hi.y - lo.y };
}

// --- post-processing -------------------------------------------------------------

// Draws the world pass through `shader`, a fragment shader over the whole
// world image (its texture is texture0). The screen pass is drawn after it,
// unprocessed.
fn post_process(eng: Engine&, shader: rl::Shader) {
    eng.post = shader;
    eng.has_post = true;
}

fn no_post_process(eng: Engine&) { eng.has_post = false; }

// --- capturing frames ------------------------------------------------------------

// Keeps an image of the next frame drawn, for honk::captured: screenshots,
// thumbnails, tests.
fn capture_next(eng: Engine&) { eng.capture = true; }

// The image of the frame honk::capture_next asked for, and whether there is
// one. The engine owns it until the next capture or the end of the run.
fn captured(eng: Engine&) -> rl::Image, bool { return eng.captured, eng.has_captured; }
