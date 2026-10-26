// Tests of the honk engine against a real raylib: scenes and asset
// lifetimes, input actions, the draw list's order, culling and packing,
// shaders, post-processing, sprites, fixed steps and saving. Rendering is
// checked on the pixels of captured frames. Needs a display (xvfb-run on a
// headless machine):
//
//   goose run test/honk_test.goose

import rl from "..";
import rl.honk;

var checks = 0;
var failures = 0;

fn check(ok: bool, what: const u8[:]) {
    checks++;
    if !ok {
        failures++;
        print("FAILED: ", what);
    }
}

fn same(a: rl::Color, b: rl::Color) -> bool {
    let ok = a.r == b.r && a.g == b.g && a.b == b.b && a.a == b.a;
    if !ok { print("  got ", a, ", expected ", b); }
    return ok;
}

let W: i32 = 320;
let H: i32 = 240;

let LEFT = 0;
let RIGHT = 1;
let FIRE = 2;
let UP = 3;
let DOWN = 4;

// The color at (x, y) of the frame captured last.
fn pixel(eng: honk::Engine&, x: i32, y: i32) -> rl::Color {
    let image, ok = honk::captured(eng);
    if !ok { return rl::BLANK; }
    return rl::GetImageColor(image, x, y);
}

// Runs `body` for one frame, captures it, and runs one more frame so the
// test reads the capture after the frame was drawn.
fn draw_once<F>(eng: honk::Engine&) {
    var n = 0;
    honk::frames(eng) { f =>
        if n == 1 { return; }
        honk::capture_next(eng);
        F(f);
        n++;
    };
}

// --- scenes ------------------------------------------------------------------

enum Scene { Load, Check { n: i32, mark: i64 }, Done }

fn load_scene(eng: honk::Engine&) -> Scene {
    let mark = honk::mark(eng);
    honk::bake(eng, rl::GenImageColor(4, 4, rl::RED));
    honk::shader(eng, "#version 330\nout vec4 c; void main() { c = vec4(1.0); }\n");
    check(honk::mark(eng) == mark + 2, "loads push assets");
    var frames = 0;
    honk::frames(eng) { f =>
        frames++;
        if frames == 2 { return Scene.Check { n: 7, mark: mark }; }
    };
    return Scene.Done;
}

fn check_scene(eng: honk::Engine&, n: i32, mark: i64) -> Scene {
    check(n == 7, "a scene's payload reaches the next scene");
    check(honk::mark(eng) == mark, "a scene's assets are unloaded when it ends");
    return Scene.Done;
}

fn scenes(eng: honk::Engine&) {
    var visited: u8[>..] = [];
    honk::scenes(eng, Scene.Load) { s =>
        match s {
            Load => { visited.push('L'); load_scene(eng) },
            Check c => { visited.push('C'); check_scene(eng, c.n, c.mark) },
            Done => { visited.push('D'); honk::quit(eng); Scene.Done },
        }
    };
    check(visited == "LCD", str("scenes ran in order: ", visited));
}

// --- input -------------------------------------------------------------------

fn input(eng: honk::Engine&) {
    honk::bind_key(eng, LEFT, rl::KEY_A);
    honk::bind_key(eng, RIGHT, rl::KEY_D);
    honk::bind_key(eng, FIRE, rl::KEY_SPACE);
    honk::bind_key(eng, UP, rl::KEY_W);
    honk::bind_key(eng, DOWN, rl::KEY_S);
    var n = 0;
    honk::press(eng, FIRE);
    honk::press(eng, RIGHT);
    honk::frames(eng) { f =>
        if n == 0 {
            check(f.pressed(FIRE) && f.down(FIRE) && !f.released(FIRE), "a pressed action is pressed and down");
            check(f.axis(LEFT, RIGHT) == 1.0, "axis from two actions");
            check(f.direction(LEFT, RIGHT, UP, DOWN).x == 1.0, "direction");
            honk::press(eng, FIRE);
        } else if n == 1 {
            check(f.down(FIRE) && !f.pressed(FIRE), "an action held down is not pressed again");
        } else {
            check(f.released(FIRE) && !f.down(FIRE), "a let go action is released");
            return;
        }
        n++;
    };
    honk::unbind_all(eng);
}

// --- drawing -----------------------------------------------------------------

fn order(eng: honk::Engine&) {
    draw_once(eng) { f =>
        f.screen();
        f.layer = 1;
        f.rect(rl::Rectangle { 0.0, 0.0, 100.0, 100.0 }, rl::BLUE);
        f.layer = 0;
        f.rect(rl::Rectangle { 0.0, 0.0, 200.0, 100.0 }, rl::RED);   // recorded later, drawn first
        f.layer = 0;
        f.world();
        f.rect(rl::Rectangle { 0.0, 120.0, 100.0, 100.0 }, rl::GREEN);
        f.screen();
        f.rect(rl::Rectangle { 50.0, 120.0, 100.0, 100.0 }, rl::YELLOW);  // screen over world
    };
    check(same(pixel(eng, 50, 50), rl::BLUE), "a higher layer draws over a lower one");
    check(same(pixel(eng, 150, 50), rl::RED), "the lower layer shows where the higher does not cover it");
    check(same(pixel(eng, 20, 150), rl::GREEN), "world pass");
    check(same(pixel(eng, 70, 150), rl::YELLOW), "the screen pass draws over the world");
    check(eng.stats.commands == 4 && eng.stats.drawn == 4, "stats count the commands");
}

fn camera_and_culling(eng: honk::Engine&) {
    eng.camera.target = rl::Vector2 { 1000.0, 1000.0 };
    eng.camera.offset = rl::Vector2 { 0.0, 0.0 };
    draw_once(eng) { f =>
        f.rect(rl::Rectangle { 1000.0, 1000.0, 50.0, 50.0 }, rl::RED);     // at the camera
        f.rect(rl::Rectangle { 0.0, 0.0, 50.0, 50.0 }, rl::BLUE);          // far outside the view
        f.circle(rl::Vector2 { 5000.0, 5000.0 }, 10.0, rl::BLUE);
    };
    check(same(pixel(eng, 10, 10), rl::RED), "the camera moves the world");
    check(eng.stats.culled == 2 && eng.stats.drawn == 1, str("commands outside the view are culled: ", eng.stats.culled));
    eng.camera.target = rl::Vector2 { 0.0, 0.0 };
}

fn packing(eng: honk::Engine&) {
    draw_once(eng) { f => f.text("hello", rl::Vector2 { 0.0, 0.0 }, 10.0, rl::WHITE); };
    // tag 1 + pos 8 + size 4 + spacing 4 + font 1 + color 4 + length 1 + "hello" 5
    check(eng.stats.command_bytes == 28, str("a text command is packed with its text: ", eng.stats.command_bytes, " bytes"));
    draw_once(eng) { f =>
        f.lines([rl::Vector2 { 0.0, 0.0 }, rl::Vector2 { 10.0, 10.0 }, rl::Vector2 { 20.0, 0.0 }], 2.0, rl::WHITE);
        f.circle(rl::Vector2 { 0.0, 0.0 }, 1.0, rl::WHITE);
    };
    // lines: 1 + thick 4 + color 4 + length 1 + 3 points 24; circle: 1 + 8 + 4 + 4
    check(eng.stats.command_bytes == 34 + 17, str("commands take their own variant's size: ", eng.stats.command_bytes, " bytes"));
    check(eng.stats.index_bytes == 2*honk::ITEM_BYTES, "one index entry per command");
}

fn shaders(eng: honk::Engine&) {
    honk::scope(eng) {
        let green = honk::shader(eng, """
            #version 330
            out vec4 finalColor;
            void main() { finalColor = vec4(0.0, 1.0, 0.0, 1.0); }
            """);
        let tint = honk::shader(eng, """
            #version 330
            out vec4 finalColor;
            uniform vec4 tint;
            void main() { finalColor = tint; }
            """);
        honk::set_uniform(tint, "tint", rl::Vector4 { 1.0, 0.0, 1.0, 1.0 });
        draw_once(eng) { f =>
            f.screen();
            f.use_shader(green);
            f.rect(rl::Rectangle { 0.0, 0.0, 100.0, 100.0 }, rl::WHITE);
            f.use_shader(tint);
            f.rect(rl::Rectangle { 100.0, 0.0, 100.0, 100.0 }, rl::WHITE);
            f.no_shader();
            f.rect(rl::Rectangle { 200.0, 0.0, 100.0, 100.0 }, rl::WHITE);
        };
        check(same(pixel(eng, 50, 50), rl::Color { 0, 255, 0, 255 }), "a command's shader");
        check(same(pixel(eng, 150, 50), rl::Color { 255, 0, 255, 255 }), "a shader with a uniform");
        check(same(pixel(eng, 250, 50), rl::WHITE), "no shader after no_shader");

        let invert = honk::shader(eng, """
            #version 330
            in vec2 fragTexCoord;
            uniform sampler2D texture0;
            out vec4 finalColor;
            void main() { vec4 c = texture(texture0, fragTexCoord); finalColor = vec4(1.0 - c.rgb, 1.0); }
            """);
        honk::post_process(eng, invert);
        draw_once(eng) { f =>
            f.rect(rl::Rectangle { 0.0, 0.0, 100.0, 100.0 }, rl::WHITE);
            f.screen();
            f.rect(rl::Rectangle { 100.0, 0.0, 100.0, 100.0 }, rl::WHITE);
        };
        check(same(pixel(eng, 50, 50), rl::BLACK), "post-processing of the world pass");
        check(same(pixel(eng, 150, 50), rl::WHITE), "the screen pass is not post-processed");
    };
    check(!eng.has_post, "unloading the post shader turns post-processing off");
}

fn sprites(eng: honk::Engine&) {
    honk::scope(eng) {
        var image = rl::GenImageColor(8, 4, rl::RED);
        rl::ImageDrawRectangle(image, 4, 0, 4, 4, rl::BLUE);   // frame 1 is blue
        let sheet = honk::Sheet { texture: honk::bake(eng, image), cols: 2, rows: 1 };
        let r = honk::frame_rect(sheet, 1);
        check(r.x == 4.0 && r.y == 0.0 && r.width == 4.0 && r.height == 4.0, "frame_rect");
        let anim = honk::Anim { first: 0, count: 2, fps: 10.0 };
        check(honk::frame_at(anim, 0.05) == 0 && honk::frame_at(anim, 0.15) == 1 && honk::frame_at(anim, 0.25) == 0, "frame_at loops");
        let once = honk::Anim { first: 0, count: 2, fps: 10.0, looping: false };
        check(honk::frame_at(once, 5.0) == 1 && honk::finished(once, 5.0), "frame_at stops");
        draw_once(eng) { f =>
            f.screen();
            f.sprite(sheet, 1, rl::Vector2 { 40.0, 40.0 }, 10.0, 0.0, false, rl::WHITE);
            f.sprite(sheet, 1, rl::Vector2 { 140.0, 40.0 }, 10.0, 0.0, true, rl::WHITE);
            f.texture(sheet.texture, rl::Vector2 { 200.0, 0.0 }, rl::WHITE);
        };
        check(same(pixel(eng, 40, 40), rl::BLUE), "a sheet frame, scaled and centered");
        check(same(pixel(eng, 140, 40), rl::BLUE), "a flipped frame");
        check(same(pixel(eng, 201, 1), rl::RED) && same(pixel(eng, 206, 1), rl::BLUE), "a whole texture");
    };
}

fn fixed(eng: honk::Engine&) {
    var steps = 0;
    var frames = 0;
    eng.accumulator = 0.0;
    honk::frames(eng) { f =>
        f.dt = 0.05;
        honk::fixed(f, 0.01) { steps++; };
        frames++;
        if frames == 3 { return; }
    };
    check(steps >= 14 && steps <= 15, str("fixed steps: ", steps));
}

struct Score { name: u8[..12], points: i32 }

fn store() {
    let path = "honk_test_scores.bin";
    var scores: Score[>..] = [];
    scores.push(Score { name: "ada", points: 120 });
    scores.push(Score { name: "grace", points: 95 });
    check(honk::save(path, scores), "save");
    let loaded, ok = honk::load<Score>(path);
    check(ok && loaded.len == 2 && loaded[1].name == "grace" && loaded[0].points == 120, "load what save wrote");
    write_file(path, "not a save");
    let bad, bad_ok = honk::load<Score>(path);
    check(!bad_ok && bad.len == 0, "a damaged file does not load");
    let none, none_ok = honk::load<Score>("no such file.bin");
    check(!none_ok && none.len == 0, "a missing file does not load");
    delete_file(path);
}

fn main() {
    honk::run(honk::Config { width: W, height: H, title: "honk test", fps: 0, max_frames: 1000 }) { eng =>
        rl::SetTraceLogLevel(rl::LOG_WARNING);
        let base = honk::mark(eng);
        scenes(eng);
        eng.quit = false;
        input(eng);
        order(eng);
        camera_and_culling(eng);
        packing(eng);
        shaders(eng);
        sprites(eng);
        fixed(eng);
        store();
        check(honk::mark(eng) == base, "every scope unloaded what it loaded");
        check(honk::running(eng), "the run did not stop early");
    };
    print(checks - failures, " of ", checks, " checks passed");
    if failures > 0 { abort("honk test failed"); }
}
