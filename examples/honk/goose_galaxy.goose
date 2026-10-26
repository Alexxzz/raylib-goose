// Goose Galaxy: a stress test. Tens to hundreds of thousands of geese orbit
// a nest in a spiral galaxy. Zoom from the whole galaxy down to a single
// goose flapping its wings; click to honk, and a shockwave ripples through
// the flock.
//
//   goose run examples/honk/goose_galaxy.goose
//   goose run examples/honk/goose_galaxy.goose -- --count 200000
//   goose run examples/honk/goose_galaxy.goose -- --bench --fast
//
// Wheel zooms at the mouse, right or middle drag (or WASD) pans, click or H
// honks, + and - double and halve the flock, C switches who culls, Space
// pauses time, R resets the view, F1 shows the engine's overlay.
//
// --bench flies a fixed path through galaxies of 4 000 to 256 000 geese and
// prints frame times, zoomed out and zoomed in; --fast uncaps the frame rate;
// --plain leaves out the sky and the glow, for a slow GPU; --honk-culls
// records every goose and lets honk cull them.
//
//   goose run examples/honk/goose_galaxy.goose -- --zoom 3 --at 900 -300 --screenshot close.png
//
// starts zoomed in at a world point and saves the 90th frame (through
// honk::capture_next) before quitting.
//
// What it exercises:
//   * the draw list: every goose the game records is a command in the
//     frame's packed array, sorted through its index and freed with the
//     frame. Zoomed out, that is every goose.
//   * culling, two ways: honk culls world commands against the view when it
//     draws them; with C the game skips recording the geese outside f.view()
//     instead, which saves the recording too.
//   * level of detail from the zoom: a pixel, a dot, or an animated sprite
//     turned along its orbit.
//   * scenes as scopes: the flock is a local of the galaxy scene. Changing
//     its size returns a new scene, which frees the old flock in one store,
//     however big, and builds the new one.

import std;
import os;
import math;
import rl from "../..";
import rl.honk;

// --- actions -------------------------------------------------------------------

let PAN_LEFT = 0;
let PAN_RIGHT = 1;
let PAN_UP = 2;
let PAN_DOWN = 3;
let HONK = 4;
let DRAG = 5;
let MORE = 6;
let FEWER = 7;
let CULL = 8;
let PAUSE = 9;
let RESET = 10;

fn bind_actions(eng: honk::Engine&) {
    honk::bind_key(eng, PAN_LEFT, rl::KEY_A);
    honk::bind_key(eng, PAN_LEFT, rl::KEY_LEFT);
    honk::bind_key(eng, PAN_RIGHT, rl::KEY_D);
    honk::bind_key(eng, PAN_RIGHT, rl::KEY_RIGHT);
    honk::bind_key(eng, PAN_UP, rl::KEY_W);
    honk::bind_key(eng, PAN_UP, rl::KEY_UP);
    honk::bind_key(eng, PAN_DOWN, rl::KEY_S);
    honk::bind_key(eng, PAN_DOWN, rl::KEY_DOWN);
    honk::bind_mouse(eng, HONK, rl::MOUSE_BUTTON_LEFT);
    honk::bind_key(eng, HONK, rl::KEY_H);
    honk::bind_mouse(eng, DRAG, rl::MOUSE_BUTTON_RIGHT);
    honk::bind_mouse(eng, DRAG, rl::MOUSE_BUTTON_MIDDLE);
    honk::bind_key(eng, MORE, rl::KEY_EQUAL);
    honk::bind_key(eng, MORE, rl::KEY_KP_ADD);
    honk::bind_key(eng, FEWER, rl::KEY_MINUS);
    honk::bind_key(eng, FEWER, rl::KEY_KP_SUBTRACT);
    honk::bind_key(eng, CULL, rl::KEY_C);
    honk::bind_key(eng, PAUSE, rl::KEY_SPACE);
    honk::bind_key(eng, RESET, rl::KEY_R);
}

// --- the galaxy ------------------------------------------------------------------

let ARMS = 3;
// The galaxy's scale radius: it grows with the square root of the flock, so
// the geese are as far apart in every galaxy and a close zoom always finds
// single geese. Set by the galaxy scene before it builds its flock.
var radius: f32 = 2600.0;

fn radius_for(count: i64) -> f32 { (1400.0*sqrt(count/16000.0)) as f32 }
let TILT: f32 = 0.62;           // the disc seen at an angle: y is squashed
let GOOSE_SIZE: f32 = 24.0;     // a goose's length in the world, in pixels at zoom 1
let MIN_COUNT = 1000;
let MAX_COUNT = 1024000;

// 36 bytes a goose: its orbit, its displacement by honks, its wing beat and
// its color. Positions are computed when drawn.
struct Goose {
    r: f32,                     // orbit radius
    angle: f32,
    omega: f32,                 // radians per second
    ox: f32, oy: f32,           // displacement by shockwaves, springing back
    vx: f32, vy: f32,
    phase: f32,                 // wing beat offset, 0..1
    color: rl::Color,
}

struct Shockwave { center: rl::Vector2, radius: f32 }

fn rnd() -> f32 { rl::GetRandomValue(0, 1000000)/1000000.0 }

// Roughly normal noise, mean 0 and spread 1.
fn noise() -> f32 { (rnd() + rnd() + rnd() + rnd() - 2.0)*1.7 }

// Gold in the core, blue-white in the arms, rose at the rim; the geese
// between the arms are dimmer.
fn star_color(t: f32, in_arm: bool) -> rl::Color {
    let core = rl::Vector3 { 1.0, 0.86, 0.55 };
    let arms = rl::Vector3 { 0.70, 0.84, 1.0 };
    let rim = rl::Vector3 { 1.0, 0.62, 0.72 };
    let c = if t < 0.25 { rl::Vector3Lerp(core, arms, t/0.25) } else { rl::Vector3Lerp(arms, rim, min((t - 0.25)/0.75, 1.0)) };
    let j = (0.8 + 0.3*rnd())*(if in_arm { 1.0 } else { 0.55 });
    return rl::Color { (min(c.x*j, 1.0)*255.0) as! u8, (min(c.y*j, 1.0)*255.0) as! u8, (min(c.z*j, 1.0)*255.0) as! u8, 255 };
}

// The flock, built straight into the caller's variable: n geese, most on
// ARMS logarithmic spiral arms, the rest scattered over the disc, thinning
// out exponentially from the nest.
fn make_flock(n: i64) -> Goose[>..] {
    var flock: Goose[>..] = [];
    for i in n {
        let in_arm = rnd() < 0.72;
        var r = 60.0 - radius*log(1.0 - rnd());
        while r > 4.0*radius { r = 60.0 - radius*log(1.0 - rnd()); }   // no hard rim
        let t = r/(4.0*radius);
        let arm = (i % ARMS)*2.0*rl::PI/ARMS;
        let spread = if in_arm { 0.16 + 0.10*t } else { 3.14 };
        let angle = arm + 1.6*log(r/60.0) + noise()*spread;
        // A flat rotation curve: the same speed at every radius, so the
        // inside turns faster and the arms wind.
        let omega = 150.0/(r + 120.0);
        flock.push(Goose { r: r, angle: angle, omega: omega, ox: 0.0, oy: 0.0, vx: 0.0, vy: 0.0,
                           phase: rnd(), color: star_color(t, in_arm) });
    }
    return flock;
}

fn position(g: Goose) -> rl::Vector2 {
    rl::Vector2 { cos(g.angle)*g.r + g.ox, sin(g.angle)*g.r*TILT + g.oy }
}

// Four frames of a goose seen from above, flying right, wings up to down.
fn goose_sheet(eng: honk::Engine&) -> honk::Sheet {
    // Light so that a tint shows: a pale body, white swept-back wings with
    // grey tips, a dark neck and head, an orange bill.
    var img = rl::GenImageColor(96, 24, rl::BLANK);
    let spans: f32[4] = [11.0, 7.0, 3.0, 7.0];
    let wing = rl::Color { 250, 250, 250, 255 };
    let tip = rl::Color { 150, 150, 155, 255 };
    let body = rl::Color { 215, 215, 210, 255 };
    let dark = rl::Color { 60, 60, 65, 255 };
    for i in 4 {
        let x: f32 = i*24.0;
        let span = spans[i];
        // Each wing: a triangle from the shoulders back to the tip.
        rl::ImageDrawTriangle(img, rl::Vector2 { x + 13.0, 11.0 }, rl::Vector2 { x + 7.0, 11.0 - span }, rl::Vector2 { x + 9.0, 11.0 }, wing);
        rl::ImageDrawTriangle(img, rl::Vector2 { x + 9.0, 13.0 }, rl::Vector2 { x + 7.0, 13.0 + span }, rl::Vector2 { x + 13.0, 13.0 }, wing);
        rl::ImageDrawTriangle(img, rl::Vector2 { x + 8.0, 11.0 - span*0.6 }, rl::Vector2 { x + 7.0, 11.0 - span }, rl::Vector2 { x + 7.0, 11.0 - span*0.6 }, tip);
        rl::ImageDrawTriangle(img, rl::Vector2 { x + 7.0, 13.0 + span*0.6 }, rl::Vector2 { x + 7.0, 13.0 + span }, rl::Vector2 { x + 8.0, 13.0 + span*0.6 }, tip);
        let xi = x as! i32;
        rl::ImageDrawRectangle(img, xi + 3, 10, 13, 5, body);          // body, tail to chest
        rl::ImageDrawRectangle(img, xi + 1, 11, 3, 3, tip);             // tail
        rl::ImageDrawRectangle(img, xi + 15, 11, 5, 3, dark);           // neck
        rl::ImageDrawCircle(img, xi + 20, 12, 2, dark);                 // head
        rl::ImageDrawRectangle(img, xi + 22, 12, 2, 1, rl::Color { 255, 160, 40, 255 });
    }
    return honk::Sheet { texture: honk::bake(eng, img), cols: 4, rows: 1 };
}

let NEBULA = """
    #version 330
    out vec4 finalColor;
    uniform vec2 resolution;
    uniform vec2 camera;        // the camera's target, in the world
    uniform float zoom;
    float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7)))*43758.5453); }
    float smooth_noise(vec2 p) {
        vec2 i = floor(p), f = fract(p);
        f = f*f*(3.0 - 2.0*f);
        return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
    }
    void main() {
        // A far layer: it moves a tenth as fast as the world.
        vec2 p = ((gl_FragCoord.xy - resolution*0.5)/zoom*0.1 + vec2(camera.x, -camera.y)*0.1)/300.0;
        float n = 0.0, a = 0.5;
        for (int i = 0; i < 5; i++) { n += a*smooth_noise(p); p *= 2.03; a *= 0.5; }
        vec3 col = mix(vec3(0.01, 0.01, 0.04), vec3(0.20, 0.06, 0.28), smoothstep(0.35, 0.9, n));
        col += vec3(0.02, 0.07, 0.14)*smoothstep(0.55, 1.0, n);
        float star = step(0.9985, hash(floor(gl_FragCoord.xy)));
        finalColor = vec4(col + star*0.6, 1.0);
    }
    """;

// A glow over the world: each pixel picks up some of its neighbours' light.
let GLOW = """
    #version 330
    in vec2 fragTexCoord;
    uniform sampler2D texture0;
    uniform vec2 resolution;
    out vec4 finalColor;
    void main() {
        vec2 px = 1.0/resolution;
        vec3 c = texture(texture0, fragTexCoord).rgb;
        vec3 glow = vec3(0.0);
        for (int i = -2; i <= 2; i++)
            for (int j = -2; j <= 2; j++)
                glow += texture(texture0, fragTexCoord + vec2(i, j)*px*2.0).rgb;
        finalColor = vec4(c + glow/25.0*0.9, 1.0);
    }
    """;

// --- the scene -------------------------------------------------------------------

// --zoom, --at and --screenshot.
struct Start { zoom: f32, at: rl::Vector2, has_view: bool, screenshot: u8[..256] }

// No sky and no glow: --plain, for machines whose GPU is slow at full-screen
// shaders (or has none, such as a software renderer).
var plain = false;

enum Scene { Galaxy { count: i64 }, Done }

// The benchmark's path: for each flock size, frames zoomed out on the whole
// galaxy, then frames zoomed in on one arm.
struct Bench { on: bool, sizes: i64[8], step: i64, frame: i64,
               out_ms: f64, out_n: i64, in_ms: f64, in_n: i64,
               out_cmds: i64, in_cmds: i64, in_culled: i64,
               out_update: f64, out_record: f64, in_update: f64, in_record: f64,
               out_sort: f64, out_draw: f64, out_present: f64 }

let BENCH_FRAMES = 120;
let BENCH_WARMUP = 10;

fn reset_view(eng: honk::Engine&) {
    eng.camera.offset = rl::Vector2 { rl::GetScreenWidth()/2.0, rl::GetScreenHeight()/2.0 };
    eng.camera.target = rl::Vector2 { 0.0, 0.0 };
    eng.camera.zoom = rl::GetScreenHeight()/(7.0*radius*TILT);
    eng.camera.rotation = 0.0;
}

fn galaxy(eng: honk::Engine&, count: i64, sheet: honk::Sheet, bench: Bench&, game_culls: bool&, start: Start) -> Scene {
    // A bigger or smaller flock: scale the view with the galaxy, so that it
    // shows the same part of it.
    let scale = radius_for(count)/radius;
    radius = radius_for(count);
    eng.camera.target = rl::Vector2Scale(eng.camera.target, scale);
    eng.camera.zoom /= scale;
    let built_at = rl::GetTime();
    var flock = make_flock(count);
    let build_ms = (rl::GetTime() - built_at)*1000.0;
    var waves: Shockwave[>..<] = [];
    var paused = false;
    var zoom_goal = eng.camera.zoom;
    var update_ms: f64 = 0.0;
    var record_ms: f64 = 0.0;
    var last_update: f64 = 0.0;
    var last_record: f64 = 0.0;
    let nebula = honk::shader(eng, NEBULA);
    let glow = honk::shader(eng, GLOW);
    if !plain { honk::post_process(eng, glow); }

    if start.has_view {
        eng.camera.target = start.at;
        eng.camera.zoom = start.zoom;
        zoom_goal = start.zoom;
    }
    var shown = 0;
    honk::frames(eng) { f =>
        let w = f.width();
        let h = f.height();
        shown++;
        if start.screenshot.len > 0 {
            if shown == 90 { honk::capture_next(eng); }
            if shown == 91 {
                let image, ok = honk::captured(eng);
                if ok { rl::ExportImage(image, start.screenshot); }
                return Scene.Done;
            }
        }

        // --- input, or the benchmark's path ---
        if bench.on {
            let k = bench.frame;
            if k == 0 { reset_view(eng); zoom_goal = eng.camera.zoom; }
            if k == BENCH_FRAMES/2 {
                // Zoom in on a point on an arm, near enough to see wings.
                eng.camera.target = rl::Vector2 { 0.9*radius, -0.3*radius };
                eng.camera.zoom = 2.5;
                zoom_goal = 2.5;
            }
            if k % 40 == 10 { waves.push(Shockwave { center: eng.camera.target, radius: 0.0 }); }
            bench.frame++;
            if bench.frame == BENCH_FRAMES { return next_bench(bench); }
        } else {
            if f.pressed(MORE) && count < MAX_COUNT { return Scene.Galaxy { count: count*2 }; }
            if f.pressed(FEWER) && count > MIN_COUNT { return Scene.Galaxy { count: count/2 }; }
            if f.pressed(CULL) { game_culls = !game_culls; }
            if f.pressed(PAUSE) { paused = !paused; }
            if f.pressed(RESET) { reset_view(eng); zoom_goal = eng.camera.zoom; }
            if f.pressed(HONK) { waves.push(Shockwave { center: f.mouse_world(), radius: 0.0 }); }
            if f.down(DRAG) { honk::pan(eng, f.mouse_delta()); }
            let keys = f.direction(PAN_LEFT, PAN_RIGHT, PAN_UP, PAN_DOWN);
            honk::pan(eng, rl::Vector2Scale(keys, -700.0*f.dt));
            let wheel = f.wheel();
            if wheel != 0.0 { zoom_goal = rl::Clamp(zoom_goal*pow(1.25 as f32, wheel), 0.02, 12.0); }
            // Ease toward the wanted zoom, around the mouse.
            let step = pow(zoom_goal/eng.camera.zoom, min(f.dt*12.0, 1.0));
            if abs(step - 1.0) > 0.0001 { honk::zoom_at(eng, f.mouse(), step); }
        }

        // --- the simulation: one pass over the flock ---
        let t0 = rl::GetTime();
        let dt = if paused { 0.0 } else { f.dt };
        for &s in waves { s.radius += 1400.0*dt; }
        var kept = 0;
        for i in waves.len {
            if waves[i].radius < 6.0*radius { waves[kept] = waves[i]; kept++; }
        }
        waves.resize(kept);
        for &g in flock {
            g.angle += g.omega*dt;
            g.phase += dt*(2.5 + g.omega*10.0);
            if g.phase >= 1.0 { g.phase -= 1.0; }
            let p = position(g);
            for s in waves {
                let d = rl::Vector2Distance(p, s.center);
                if abs(d - s.radius) < 60.0 && d > 1.0 {
                    let push = 900.0*dt*(1.0 - s.radius/(6.0*radius));
                    g.vx += (p.x - s.center.x)/d*push*10.0;
                    g.vy += (p.y - s.center.y)/d*push*10.0;
                }
            }
            // A damped spring back to the orbit.
            g.vx += (-6.0*g.ox - 2.5*g.vx)*dt;
            g.vy += (-6.0*g.oy - 2.5*g.vy)*dt;
            g.ox += g.vx*dt;
            g.oy += g.vy*dt;
        }
        let t1 = rl::GetTime();

        // --- recording: the level of detail follows the zoom ---
        let zoom = eng.camera.zoom;
        let px = GOOSE_SIZE*zoom;           // a goose's length on the screen
        let view = f.view();
        let margin = GOOSE_SIZE;
        let culled = rl::Rectangle { view.x - margin, view.y - margin, view.width + 2.0*margin, view.height + 2.0*margin };
        f.layer = 0;
        for g in flock {
            let p = position(g);
            if game_culls && !rl::CheckCollisionPointRec(p, culled) { continue; }
            if px < 6.0 {
                let size = 2.0/zoom;
                f.rect(rl::Rectangle { p.x, p.y, size, size }, g.color);
            } else if px < 14.0 {
                f.circle(p, GOOSE_SIZE*0.3, g.color);
            } else {
                // Turned along its orbit: the tangent of the tilted circle.
                let heading = atan2(cos(g.angle)*TILT + g.vy*0.002, -sin(g.angle) + g.vx*0.002)*rl::RAD2DEG;
                let frame = (g.phase*4.0) as! i32;
                f.sprite(sheet, frame, p, 1.0, heading, false, g.color);
            }
        }
        // The nest, and the shockwaves.
        f.layer = 1;
        f.circle(rl::Vector2 { 0.0, 0.0 }, 30.0, rl::Color { 255, 240, 200, 255 });
        for s in waves {
            f.ring(s.center, s.radius - 6.0/zoom, s.radius, rl::Fade(rl::Color { 255, 250, 220, 255 }, 0.5*(1.0 - s.radius/(6.0*radius))));
        }
        let t2 = rl::GetTime();
        last_update = 1000.0*(t1 - t0);
        last_record = 1000.0*(t2 - t1);
        update_ms = 0.9*update_ms + 0.1*last_update;
        record_ms = 0.9*record_ms + 0.1*last_record;

        // The sky behind, the numbers in front.
        honk::set_uniform(nebula, "resolution", rl::Vector2 { w, h });
        honk::set_uniform(nebula, "camera", eng.camera.target);
        honk::set_uniform(nebula, "zoom", zoom);
        honk::set_uniform(glow, "resolution", rl::Vector2 { w, h });
        if !plain {
            f.background();
            f.use_shader(nebula);
            f.rect(rl::Rectangle { 0.0, 0.0, w, h }, rl::WHITE);
            f.no_shader();
        }
        f.screen();
        f.layer = 10;
        let s = eng.stats;
        let lod = if px < 6.0 { "pixels" } else if px < 14.0 { "dots" } else { "sprites" };
        f.rect(rl::Rectangle { 0.0, h - 64.0, w, 64.0 }, rl::Fade(rl::BLACK, 0.55));
        f.text(str("GOOSE GALAXY   ", count, " geese   zoom ", (zoom*100.0) as! i64, "%  (", lod, ")   ",
                   rl::GetFPS(), " fps"), rl::Vector2 { 12.0, h - 58.0 }, 20.0, rl::RAYWHITE);
        f.text(str("update ", (update_ms*100.0) as! i64/100.0, " ms   record ", (record_ms*100.0) as! i64/100.0,
                   " ms   draw list ", s.commands, " commands, ", (s.command_bytes + s.index_bytes)/1024,
                   " KB, ", s.culled, " culled by honk   ", if game_culls { "game culls" } else { "honk culls" },
                   "   flock built in ", build_ms as! i64, " ms"),
               rl::Vector2 { 12.0, h - 32.0 }, 16.0, rl::LIGHTGRAY);
        f.text("wheel zoom  drag pan  click honk  +/- flock  C cull  space pause  R reset",
               rl::Vector2 { 12.0, 12.0 }, 16.0, rl::Fade(rl::RAYWHITE, 0.6));

        // The benchmark's measurements, after a warmup in each half.
        if bench.on {
            let k = bench.frame - 1;
            let ms = rl::GetFrameTime()*1000.0;
            if k >= BENCH_WARMUP && k < BENCH_FRAMES/2 {
                bench.out_ms += ms; bench.out_n++; bench.out_cmds = s.commands;
                bench.out_update += last_update; bench.out_record += last_record;
                bench.out_sort += s.sort_ms; bench.out_draw += s.draw_ms; bench.out_present += s.present_ms;
            }
            if k >= BENCH_FRAMES/2 + BENCH_WARMUP {
                bench.in_ms += ms; bench.in_n++; bench.in_cmds = s.commands; bench.in_culled = s.culled;
                bench.in_update += last_update; bench.in_record += last_record;
            }
        }
    };
    return Scene.Done;
}

// Prints the finished flock size's numbers and moves to the next size.
fn next_bench(b: Bench&) -> Scene {
    let n = b.sizes[b.step];
    print(n, " geese");
    print("  zoomed out: ", fmt_ms(b.out_ms/b.out_n), " ms/frame = update ", fmt_ms(b.out_update/b.out_n),
          " + record ", fmt_ms(b.out_record/b.out_n), " + draw ", fmt_ms((b.out_ms - b.out_update - b.out_record)/b.out_n),
          "  (", b.out_cmds, " commands)");
    print("    honk: sort ", fmt_ms(b.out_sort/b.out_n), ", draw ", fmt_ms(b.out_draw/b.out_n), ", present ", fmt_ms(b.out_present/b.out_n));
    print("  zoomed in:  ", fmt_ms(b.in_ms/b.in_n), " ms/frame = update ", fmt_ms(b.in_update/b.in_n),
          " + record ", fmt_ms(b.in_record/b.in_n), " + draw ", fmt_ms((b.in_ms - b.in_update - b.in_record)/b.in_n),
          "  (", b.in_cmds, " commands, ", b.in_culled, " culled by honk)");
    b.step++;
    b.frame = 0;
    b.out_ms = 0.0; b.out_n = 0; b.in_ms = 0.0; b.in_n = 0;
    b.out_update = 0.0; b.out_record = 0.0; b.in_update = 0.0; b.in_record = 0.0;
    b.out_sort = 0.0; b.out_draw = 0.0; b.out_present = 0.0;
    if b.step == b.sizes.len || b.sizes[b.step] == 0 { return Scene.Done; }
    return Scene.Galaxy { count: b.sizes[b.step] };
}

fn fmt_ms(ms: f64) -> f64 { (ms*100.0) as! i64/100.0 }

// --- main ------------------------------------------------------------------------

fn main() {
    var config = honk::Config { title: "Goose Galaxy", width: 1280, height: 720,
                                clear: rl::Color { 4, 4, 12, 255 }, flags: rl::FLAG_WINDOW_RESIZABLE };
    var count: i64 = 40000;
    var bench = Bench { on: false, sizes: [4000, 16000, 64000, 256000, 0, 0, 0, 0], step: 0, frame: 0,
                        out_ms: 0.0, out_n: 0, in_ms: 0.0, in_n: 0, out_cmds: 0, in_cmds: 0, in_culled: 0,
                        out_update: 0.0, out_record: 0.0, in_update: 0.0, in_record: 0.0,
                        out_sort: 0.0, out_draw: 0.0, out_present: 0.0 };
    var game_culls = true;
    var start = Start { zoom: 1.0, at: rl::Vector2 { 0.0, 0.0 }, has_view: false, screenshot: "" };
    let argv = args();
    var a = 1;
    while a < argv.len {
        if argv[a] == "--bench" { bench.on = true; }
        else if argv[a] == "--fast" { config.fps = 0; }
        else if argv[a] == "--honk-culls" { game_culls = false; }
        else if argv[a] == "--plain" { plain = true; }
        else if argv[a] == "--zoom" && a + 1 < argv.len {
            a++;
            let z, ok = parse_flt(argv[a]);
            if !ok || z <= 0.0 { abort("--zoom needs a positive number"); }
            start.zoom = z as f32;
            start.has_view = true;
        } else if argv[a] == "--at" && a + 2 < argv.len {
            let x, xok = parse_flt(argv[a + 1]);
            let y, yok = parse_flt(argv[a + 2]);
            if !xok || !yok { abort("--at needs two numbers"); }
            start.at = rl::Vector2 { x as f32, y as f32 };
            start.has_view = true;
            a += 2;
        } else if argv[a] == "--screenshot" && a + 1 < argv.len {
            a++;
            start.screenshot.append(argv[a]);
        }
        else if argv[a] == "--frames" && a + 1 < argv.len {
            a++;
            let n, ok = parse_int(argv[a]);
            if !ok || n <= 0 { abort("--frames needs a positive count"); }
            config.max_frames = n;
        } else if argv[a] == "--count" && a + 1 < argv.len {
            a++;
            let n, ok = parse_int(argv[a]);
            if !ok || n < MIN_COUNT || n > MAX_COUNT { abort(str("--count needs ", MIN_COUNT, "..", MAX_COUNT)); }
            count = n;
        } else { abort(str("unknown option: ", argv[a])); }
        a++;
    }
    if bench.on { count = bench.sizes[0]; print("benchmark: ", if game_culls { "the game culls" } else { "honk culls" }); }

    honk::run(config) { eng =>
        rl::SetTraceLogLevel(rl::LOG_WARNING);
        rl::SetRandomSeed(7);
        bind_actions(eng);
        let sheet = goose_sheet(eng);
        radius = radius_for(count);
        reset_view(eng);
        honk::scenes<Scene>(eng, Scene.Galaxy { count: count }) { s =>
            match s {
                Galaxy g => galaxy(eng, g.count, sheet, bench, game_culls, start),
                Done => { honk::quit(eng); Scene.Done },
            }
        };
    };
}
