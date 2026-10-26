// Goose Grove: a small arena game on honk. Foxes come out of the woods in
// waves; the goose honks them away. Everything is made by the program:
// sprites are drawn into images, the honk is a synthesized WAV, and the
// water and the vignette are shaders.
//
//   goose run examples/honk/goose_grove.goose
//
// WASD or arrows move, the mouse aims, click or Space honks, Esc or P
// pauses, F1 shows the debug overlay, F2 toggles the vignette. A gamepad
// works too: left stick, A to honk, Start to pause.
//
//   goose run examples/honk/goose_grove.goose -- --autoplay --frames 3000 --debug --fast
//
// lets a computer player press the same actions (honk::press), stops after
// 3000 frames, shows the debug overlay from the start, and runs as fast as
// it can rather than at 60 frames a second.
//
// Where the data lives:
//   * main's run block owns what every scene shares: the sprite sheets, the
//     sound and the high score table.
//   * the play scene owns the round: foxes and honks in reusable pools,
//     crumbs, the particles in a grow-shrink array, the decoration. When it
//     returns the next scene, all of it is freed in one store.
//   * the pause menu is a call from inside the play scene, so the round it
//     draws behind itself is still there, untouched, when it returns.

import std;
import os;
import rl from "../..";
import rl.honk;

// --- actions -------------------------------------------------------------------

let LEFT = 0;
let RIGHT = 1;
let UP = 2;
let DOWN = 3;
let HONK = 4;
let PAUSE = 5;
let CONFIRM = 6;
let VIGNETTE = 7;

fn bind_actions(eng: honk::Engine&) {
    honk::bind_key(eng, LEFT, rl::KEY_A);
    honk::bind_key(eng, LEFT, rl::KEY_LEFT);
    honk::bind_axis(eng, LEFT, rl::GAMEPAD_AXIS_LEFT_X, false);
    honk::bind_key(eng, RIGHT, rl::KEY_D);
    honk::bind_key(eng, RIGHT, rl::KEY_RIGHT);
    honk::bind_axis(eng, RIGHT, rl::GAMEPAD_AXIS_LEFT_X, true);
    honk::bind_key(eng, UP, rl::KEY_W);
    honk::bind_key(eng, UP, rl::KEY_UP);
    honk::bind_axis(eng, UP, rl::GAMEPAD_AXIS_LEFT_Y, false);
    honk::bind_key(eng, DOWN, rl::KEY_S);
    honk::bind_key(eng, DOWN, rl::KEY_DOWN);
    honk::bind_axis(eng, DOWN, rl::GAMEPAD_AXIS_LEFT_Y, true);
    honk::bind_key(eng, HONK, rl::KEY_SPACE);
    honk::bind_mouse(eng, HONK, rl::MOUSE_BUTTON_LEFT);
    honk::bind_pad(eng, HONK, rl::GAMEPAD_BUTTON_RIGHT_FACE_DOWN);
    honk::bind_key(eng, PAUSE, rl::KEY_ESCAPE);
    honk::bind_key(eng, PAUSE, rl::KEY_P);
    honk::bind_pad(eng, PAUSE, rl::GAMEPAD_BUTTON_MIDDLE_RIGHT);
    honk::bind_key(eng, CONFIRM, rl::KEY_ENTER);
    honk::bind_key(eng, CONFIRM, rl::KEY_SPACE);
    honk::bind_mouse(eng, CONFIRM, rl::MOUSE_BUTTON_LEFT);
    honk::bind_pad(eng, CONFIRM, rl::GAMEPAD_BUTTON_RIGHT_FACE_DOWN);
    honk::bind_key(eng, VIGNETTE, rl::KEY_F2);
}

// --- what every scene shares -----------------------------------------------------

struct Score { name: u8[..12], points: i32, wave: i32 }

let SCORES_FILE = "goose_grove_scores.bin";

// References to the run's data, passed to every scene.
struct Shared {
    goose: honk::Sheet,
    fox: honk::Sheet,
    honk_sound: rl::Sound,
    scores: Score[>..]&,
}

// Scenes: what runs next, and what it needs to know.
enum Scene { Title, Play, Over { points: i32, wave: i32 } }

// --- the round's data ------------------------------------------------------------

let ARENA = rl::Rectangle { 0.0, 0.0, 2400.0, 1600.0 };
let POND = rl::Vector2 { 1200.0, 800.0 };
let POND_RADIUS: f32 = 170.0;

struct Player { pos: rl::Vector2, facing: rl::Vector2, hearts: i32, hurt: f32, cooldown: f32, walked: f32 }
struct Fox { alive: bool, pos: rl::Vector2, vel: rl::Vector2, hp: i32, stun: f32, phase: f32 }
struct Honk { alive: bool, pos: rl::Vector2, vel: rl::Vector2, age: f32 }
struct Crumb { alive: bool, pos: rl::Vector2 }
struct Particle { pos: rl::Vector2, vel: rl::Vector2, life: f32, size: f32, color: rl::Color }
struct Flower { pos: rl::Vector2, size: f32, color: rl::Color }

// The round, as references to the play scene's locals: what drawing and the
// pause menu need to see.
struct Round {
    player: Player&,
    foxes: Fox[>..]&,
    honks: Honk[>..]&,
    crumbs: Crumb[>..]&,
    particles: Particle[>..<]&,
    flowers: Flower[>..]&,
    points: i32,
    wave: i32,
}

// --- small helpers ---------------------------------------------------------------

// The computer player: set by --autoplay.
var autoplay = false;

fn rnd(lo: f32, hi: f32) -> f32 { lo + (hi - lo)*(rl::GetRandomValue(0, 100000)/100000.0) }

fn v2(x: f32, y: f32) -> rl::Vector2 { rl::Vector2 { x, y } }

fn burst(particles: Particle[>..<]&, at: rl::Vector2, n: i64, color: rl::Color, speed: f32) {
    for i in n {
        let angle = rnd(0.0, 2.0*rl::PI);
        let v = rl::Vector2Scale(v2(cos(angle), sin(angle)), rnd(0.3, 1.0)*speed);
        particles.push(Particle { pos: at, vel: v, life: rnd(0.4, 0.9), size: rnd(2.0, 5.0), color: color });
    }
}

// --- drawing the round -----------------------------------------------------------

let WATER = """
    #version 330
    in vec4 fragColor;
    out vec4 finalColor;
    uniform float time;
    void main() {
        vec2 p = gl_FragCoord.xy/18.0;
        float w = sin(p.x + time*1.7) + sin(p.y*1.3 - time*1.1) + sin((p.x + p.y)*0.7 + time);
        vec3 deep = vec3(0.10, 0.32, 0.55);
        vec3 shallow = vec3(0.30, 0.62, 0.80);
        finalColor = vec4(mix(deep, shallow, 0.5 + w/6.0), 1.0)*fragColor;
    }
    """;

let VIGNETTE_SHADER = """
    #version 330
    in vec2 fragTexCoord;
    uniform sampler2D texture0;
    out vec4 finalColor;
    void main() {
        vec4 c = texture(texture0, fragTexCoord);
        vec2 d = fragTexCoord - 0.5;
        float v = smoothstep(0.85, 0.25, length(d));
        vec3 warm = c.rgb*vec3(1.05, 1.0, 0.92);
        finalColor = vec4(warm*mix(0.35, 1.0, v), 1.0);
    }
    """;

fn draw_round(f: honk::Frame&, r: Round&, s: Shared&, water: rl::Shader) {
    let t = f.time as f32;

    // The meadow and its decoration: most of it is outside the view and culled.
    f.layer = -10;
    f.rect(ARENA, rl::Color { 86, 140, 72, 255 });
    f.layer = -9;
    for fl in r.flowers { f.circle(fl.pos, fl.size, fl.color); }

    f.use_shader(water);
    f.circle(POND, POND_RADIUS, rl::WHITE);
    f.no_shader();
    f.ring(POND, POND_RADIUS - 4.0, POND_RADIUS + 6.0, rl::Color { 200, 190, 140, 255 });

    f.layer = 0;
    for c in r.crumbs {
        if c.alive { f.poly(c.pos, 6, 7.0 + sin(t*6.0), t*60.0, rl::Color { 222, 184, 110, 255 }); }
    }
    for h in r.honks {
        if h.alive {
            let k = h.age/0.6;
            f.ring(h.pos, 10.0 + 22.0*k, 14.0 + 26.0*k, rl::Fade(rl::Color { 255, 250, 210, 255 }, 1.0 - k));
        }
    }
    for x in r.foxes {
        if x.alive {
            let frame = honk::frame_at(honk::Anim { first: 0, count: 2, fps: 8.0 }, t + x.phase);
            let tint = if x.stun > 0.0 { rl::Color { 255, 200, 200, 255 } } else { rl::WHITE };
            f.sprite(s.fox, frame, x.pos, 2.0, 0.0, x.vel.x < 0.0, tint);
        }
    }
    let p = r.player;
    let walking = rl::Vector2Length(p.facing) > 0.0;
    let frame = if p.walked > 0.0 { honk::frame_at(honk::Anim { first: 0, count: 2, fps: 8.0 }, p.walked) } else { 0 };
    let blink = p.hurt > 0.0 && ((t*20.0) as! i32) % 2 == 0;
    if !blink { f.sprite(s.goose, frame, p.pos, 2.0, 0.0, p.facing.x < 0.0 && walking, rl::WHITE); }

    f.layer = 5;
    for q in r.particles { f.circle(q.pos, q.size, rl::Fade(q.color, min(q.life*2.0, 1.0))); }
}

fn draw_hud(f: honk::Frame&, r: Round&) {
    f.screen();
    f.layer = 100;
    for i in 3 {
        let color = if i < r.player.hearts { rl::Color { 230, 60, 70, 255 } } else { rl::Color { 60, 50, 50, 200 } };
        f.circle(v2(28.0 + i*34.0, 30.0), 13.0, color);
    }
    f.text(str("score ", r.points), v2(130.0, 16.0), 28.0, rl::RAYWHITE);
    f.text(str("wave ", r.wave), v2(f.width() - 130.0, 16.0), 28.0, rl::RAYWHITE);
    f.world();
    f.layer = 0;
}


// --- the title scene -------------------------------------------------------------

let SKY = """
    #version 330
    out vec4 finalColor;
    uniform float time;
    uniform vec2 resolution;
    void main() {
        vec2 uv = gl_FragCoord.xy/resolution;
        float hills = 0.25 + 0.05*sin(uv.x*9.0 + time*0.3) + 0.03*sin(uv.x*23.0 - time*0.5);
        vec3 sky = mix(vec3(0.98, 0.80, 0.55), vec3(0.45, 0.65, 0.90), uv.y);
        vec3 col = uv.y < hills ? vec3(0.30, 0.55, 0.28) : sky;
        finalColor = vec4(col, 1.0);
    }
    """;

fn title(eng: honk::Engine&, s: Shared&) -> Scene {
    let sky = honk::shader(eng, SKY);
    var shown = 0;
    honk::frames(eng) { f =>
        if f.pressed(CONFIRM) { return Scene.Play; }
        shown++;
        if autoplay && shown == 60 { honk::press(eng, CONFIRM); }
        let w = f.width();
        let h = f.height();
        honk::set_uniform(sky, "time", f.time as f32);
        honk::set_uniform(sky, "resolution", v2(w, h));

        f.screen();
        f.layer = -1;
        f.use_shader(sky);
        f.rect(rl::Rectangle { 0.0, 0.0, w, h }, rl::WHITE);
        f.no_shader();
        f.layer = 0;
        let bob = sin(f.time as f32*3.0)*6.0;
        f.sprite(s.goose, (f.time*4.0) as! i32 % 2, v2(w/2.0, h*0.62 + bob), 5.0, 0.0, false, rl::WHITE);
        f.text_centered("GOOSE GROVE", v2(w/2.0, h*0.18), 64.0, rl::Color { 60, 40, 30, 255 });
        f.text_centered("click or press Enter to play", v2(w/2.0, h*0.30), 24.0, rl::Color { 60, 40, 30, 255 });

        f.text("best honkers", v2(30.0, 30.0), 22.0, rl::Color { 60, 40, 30, 255 });
        var y: f32 = 60.0;
        for sc in s.scores {
            f.text(str(sc.name, "  ", sc.points, "  (wave ", sc.wave, ")"), v2(30.0, y), 20.0, rl::Color { 60, 40, 30, 255 });
            y += 24.0;
        }
    };
    return Scene.Title;
}

// --- the play scene --------------------------------------------------------------

fn play(eng: honk::Engine&, s: Shared&) -> Scene {
    let water = honk::shader(eng, WATER);
    let vignette = honk::shader(eng, VIGNETTE_SHADER);
    honk::post_process(eng, vignette);

    var player = Player { pos: v2(POND.x, POND.y + POND_RADIUS + 80.0), facing: v2(1.0, 0.0), hearts: 3,
                          hurt: 0.0, cooldown: 0.0, walked: 0.0 };
    reusable var foxes: Fox[>..] = [];
    reusable var honks: Honk[>..] = [];
    reusable var crumbs: Crumb[>..] = [];
    var particles: Particle[>..<] = [];
    var flowers: Flower[>..] = [];
    for i in 900 {
        let colors = [rl::Color { 250, 240, 120, 255 }, rl::Color { 250, 250, 250, 255 }, rl::Color { 230, 140, 180, 255 }];
        flowers.push(Flower { pos: v2(rnd(0.0, ARENA.width), rnd(0.0, ARENA.height)), size: rnd(2.0, 4.0),
                              color: colors[i % 3] });
    }
    var r = Round { player: player, foxes: foxes, honks: honks, crumbs: crumbs, particles: particles,
                    flowers: flowers, points: 0, wave: 0 };
    var to_spawn = 0;
    var spawn_timer: f32 = 0.0;
    eng.camera.target = player.pos;

    fn foxes_left() -> i64 {
        var n = 0;
        for x in foxes { if x.alive { n++; } }
        return n;
    }

    fn nearest_fox() -> rl::Vector2 {
        var best = rl::Vector2Add(player.pos, v2(1.0, 0.0));
        var best_d: f32 = 1.0e9;
        for x in foxes {
            let d = rl::Vector2Distance(x.pos, player.pos);
            if x.alive && d < best_d { best = x.pos; best_d = d; }
        }
        return best;
    }

    // The computer player walks around the pond honking at the nearest fox,
    // and pauses now and then. After 1500 frames it stands still and lets
    // the foxes win, so that a long enough run sees every scene and saves a
    // score.
    fn autopilot(f: honk::Frame&) {
        if f.index >= 1500 { return; }
        let away = rl::Vector2Normalize(rl::Vector2Subtract(player.pos, POND));
        let around = v2(-away.y, away.x);
        let want = rl::Vector2Add(around, rl::Vector2Scale(away, (POND_RADIUS + 120.0 - rl::Vector2Distance(player.pos, POND))/100.0));
        if want.x < -0.3 { honk::press(eng, LEFT); }
        if want.x > 0.3 { honk::press(eng, RIGHT); }
        if want.y < -0.3 { honk::press(eng, UP); }
        if want.y > 0.3 { honk::press(eng, DOWN); }
        if foxes_left() > 0 { honk::press(eng, HONK); }
        if f.index % 600 == 300 { honk::press(eng, PAUSE); }
    }

    fn spawn_fox() {
        // From a random edge of the arena.
        let side = rl::GetRandomValue(0, 3);
        let pos = match side as i64 {
            0 => v2(rnd(0.0, ARENA.width), -20.0),
            1 => v2(ARENA.width + 20.0, rnd(0.0, ARENA.height)),
            2 => v2(rnd(0.0, ARENA.width), ARENA.height + 20.0),
            _ => v2(-20.0, rnd(0.0, ARENA.height)),
        };
        foxes.alloc_ref(Fox { alive: true, pos: pos, vel: v2(0.0, 0.0), hp: 2, stun: 0.0, phase: rnd(0.0, 1.0) });
    }

    fn step(dt: f32, f: honk::Frame&) -> bool {
        // Waves: each one has more foxes, and they come faster.
        if to_spawn == 0 && foxes_left() == 0 {
            r.wave++;
            to_spawn = 2 + 2*r.wave;
            crumbs.alloc_ref(Crumb { alive: true, pos: v2(rnd(200.0, ARENA.width - 200.0), rnd(200.0, ARENA.height - 200.0)) });
        }
        spawn_timer -= dt;
        if to_spawn > 0 && spawn_timer <= 0.0 {
            spawn_fox();
            to_spawn--;
            spawn_timer = max(1.4 - 0.1*r.wave, 0.35);
        }

        // The goose.
        let dir = f.direction(LEFT, RIGHT, UP, DOWN);
        if rl::Vector2Length(dir) > 0.0 {
            player.facing = dir;
            player.walked += dt;
        } else {
            player.facing = v2(0.0, 0.0);
            player.walked = 0.0;
        }
        var next = rl::Vector2Add(player.pos, rl::Vector2Scale(dir, 260.0*dt));
        if rl::Vector2Distance(next, POND) < POND_RADIUS + 18.0 {
            next = rl::Vector2Add(POND, rl::Vector2Scale(rl::Vector2Normalize(rl::Vector2Subtract(next, POND)), POND_RADIUS + 18.0));
        }
        player.pos = rl::Vector2Clamp(next, v2(24.0, 24.0), v2(ARENA.width - 24.0, ARENA.height - 24.0));
        player.hurt = max(player.hurt - dt, 0.0);
        player.cooldown = max(player.cooldown - dt, 0.0);

        if f.down(HONK) && player.cooldown == 0.0 {
            var aim = rl::Vector2Subtract(f.mouse_world(), player.pos);
            if rl::IsGamepadAvailable(0) || rl::Vector2Length(aim) < 1.0 { aim = player.facing; }
            if autoplay { aim = rl::Vector2Subtract(nearest_fox(), player.pos); }
            if rl::Vector2Length(aim) < 0.1 { aim = v2(1.0, 0.0); }
            let v = rl::Vector2Scale(rl::Vector2Normalize(aim), 520.0);
            honks.alloc_ref(Honk { alive: true, pos: player.pos, vel: v, age: 0.0 });
            player.cooldown = 0.28;
            rl::SetSoundPitch(s.honk_sound, rnd(0.9, 1.15));
            rl::PlaySound(s.honk_sound);
        }

        // Honks fly, fade, and stun the foxes they reach.
        for &h in honks {
            if !h.alive { continue; }
            h.pos = rl::Vector2Add(h.pos, rl::Vector2Scale(h.vel, dt));
            h.age += dt;
            var spent = h.age >= 0.6;
            for &x in foxes {
                if x.alive && !spent && rl::Vector2Distance(h.pos, x.pos) < 34.0 {
                    x.hp--;
                    x.stun = 0.35;
                    x.vel = rl::Vector2Scale(rl::Vector2Normalize(h.vel), 420.0);
                    spent = true;
                    if x.hp <= 0 {
                        x.alive = false;
                        foxes.free(foxes.index_of(x));
                        r.points += 10*r.wave;
                        burst(particles, x.pos, 18, rl::Color { 230, 120, 40, 255 }, 220.0);
                        honk::shake(eng, 0.25);
                    }
                }
            }
            if spent {
                h.alive = false;
                honks.free(honks.index_of(h));
            }
        }

        // Foxes chase the goose, and bite.
        for &x in foxes {
            if !x.alive { continue; }
            if x.stun > 0.0 {
                x.stun -= dt;
                x.vel = rl::Vector2Scale(x.vel, 0.9);
            } else {
                let to = rl::Vector2Normalize(rl::Vector2Subtract(player.pos, x.pos));
                x.vel = rl::Vector2Scale(to, 120.0 + 12.0*r.wave);
            }
            x.pos = rl::Vector2Add(x.pos, rl::Vector2Scale(x.vel, dt));
            if rl::Vector2Distance(x.pos, POND) < POND_RADIUS + 20.0 {
                x.pos = rl::Vector2Add(POND, rl::Vector2Scale(rl::Vector2Normalize(rl::Vector2Subtract(x.pos, POND)), POND_RADIUS + 20.0));
            }
            if player.hurt == 0.0 && rl::Vector2Distance(x.pos, player.pos) < 36.0 {
                player.hearts--;
                player.hurt = 1.2;
                honk::shake(eng, 0.6);
                burst(particles, player.pos, 24, rl::RAYWHITE, 180.0);
                if player.hearts <= 0 { return false; }
            }
        }

        // Crumbs heal.
        for &c in crumbs {
            if c.alive && rl::Vector2Distance(c.pos, player.pos) < 30.0 {
                c.alive = false;
                crumbs.free(crumbs.index_of(c));
                player.hearts = min(player.hearts + 1, 3);
                r.points += 5;
                burst(particles, c.pos, 10, rl::Color { 222, 184, 110, 255 }, 120.0);
            }
        }

        // Particles move and fade; the dead ones are dropped by compacting
        // the array in place and shrinking it.
        var kept = 0;
        for i in particles.len {
            var q = particles[i];
            q.life -= dt;
            if q.life > 0.0 {
                q.pos = rl::Vector2Add(q.pos, rl::Vector2Scale(q.vel, dt));
                q.vel = rl::Vector2Scale(q.vel, 0.92);
                particles[kept] = q;
                kept++;
            }
        }
        particles.resize(kept);
        return true;
    }

    honk::frames(eng) { f =>
        if autoplay { autopilot(f); }
        if f.pressed(VIGNETTE) {
            if eng.has_post { honk::no_post_process(eng); } else { honk::post_process(eng, vignette); }
        }
        if f.pressed(PAUSE) {
            // The round stays where it is while the menu runs.
            if !pause(eng, r, s, water) { return Scene.Title; }
        }
        var alive = true;
        honk::fixed(f, 1.0/120.0) { if alive { alive = step(1.0/120.0, f); } };
        if !alive { return Scene.Over { points: r.points, wave: r.wave }; }

        honk::follow(eng, player.pos, 6.0);
        honk::clamp_camera(eng, ARENA);
        honk::set_uniform(water, "time", f.time as f32);
        draw_round(f, r, s, water);
        draw_hud(f, r);
    };
    return Scene.Title;
}

// --- the pause menu: an overlay is a call ---------------------------------------

// Returns whether to resume the round.
fn pause(eng: honk::Engine&, r: Round&, s: Shared&, water: rl::Shader) -> bool {
    var choice = 0;
    var shown = 0;
    honk::frames(eng) { f =>
        if f.pressed(PAUSE) { return true; }
        shown++;
        if autoplay && shown == 60 { honk::press(eng, PAUSE); }
        if f.pressed(UP) || f.pressed(DOWN) { choice = 1 - choice; }
        if f.pressed(CONFIRM) { return choice == 0; }

        draw_round(f, r, s, water);
        draw_hud(f, r);
        f.screen();
        f.layer = 200;
        let w = f.width();
        let h = f.height();
        f.rect(rl::Rectangle { 0.0, 0.0, w, h }, rl::Fade(rl::BLACK, 0.55));
        f.text_centered("PAUSED", v2(w/2.0, h*0.35), 56.0, rl::RAYWHITE);
        let items = ["resume", "back to title"];
        for i in 2 {
            let color = if i == choice { rl::GOLD } else { rl::LIGHTGRAY };
            f.text_centered(items[i], v2(w/2.0, h*0.5 + i*40.0), 30.0, color);
        }
    };
    return false;
}

// --- the game over scene ---------------------------------------------------------

fn over(eng: honk::Engine&, s: Shared&, points: i32, wave: i32) -> Scene {
    // Insert the score, keep the best five, and save them.
    var at = s.scores.len;
    for i in s.scores.len {
        if points > s.scores[i].points { at = i; break; }
    }
    if at < 5 {
        s.scores.push(Score { name: "goose", points: points, wave: wave });
        var i = s.scores.len - 1;
        while i > at { s.scores[i] = s.scores[i - 1]; i--; }
        s.scores[at] = Score { name: "goose", points: points, wave: wave };
        if s.scores.len > 5 { s.scores.resize(5); }
        honk::save(SCORES_FILE, s.scores);
    }
    honk::no_post_process(eng);

    var shown: f32 = 0.0;
    honk::frames(eng) { f =>
        shown += f.dt;
        if shown > 0.5 && f.pressed(CONFIRM) { return Scene.Title; }
        if autoplay && shown > 2.0 { honk::press(eng, CONFIRM); }
        let w = f.width();
        let h = f.height();
        f.screen();
        f.text_centered("THE FOXES WON", v2(w/2.0, h*0.3), 56.0, rl::Color { 230, 120, 40, 255 });
        f.text_centered(str(points, " points, wave ", wave), v2(w/2.0, h*0.45), 32.0, rl::RAYWHITE);
        if at < 5 { f.text_centered("a new best score!", v2(w/2.0, h*0.55), 26.0, rl::GOLD); }
        f.text_centered("press Enter", v2(w/2.0, h*0.7), 22.0, rl::LIGHTGRAY);
    };
    return Scene.Title;
}

// --- making the assets -----------------------------------------------------------

// A goose, two frames of 24x24 facing right.
fn goose_sheet(eng: honk::Engine&) -> honk::Sheet {
    var img = rl::GenImageColor(48, 24, rl::BLANK);
    let orange = rl::Color { 240, 150, 40, 255 };
    for i in 2 {
        let x: i32 = (i as i32)*24;
        let step: i32 = if i == 0 { 0 } else { 2 };
        rl::ImageDrawRectangle(img, x + 9 - step, 18, 2, 6, orange);
        rl::ImageDrawRectangle(img, x + 13 + step, 18, 2, 6, orange);
        rl::ImageDrawCircle(img, x + 11, 14, 7, rl::Color { 245, 245, 240, 255 });
        rl::ImageDrawCircle(img, x + 6, 12, 3, rl::Color { 220, 220, 215, 255 });
        rl::ImageDrawRectangle(img, x + 14, 4, 3, 9, rl::Color { 245, 245, 240, 255 });
        rl::ImageDrawCircle(img, x + 16, 4, 3, rl::Color { 245, 245, 240, 255 });
        rl::ImageDrawRectangle(img, x + 18, 3, 5, 2, orange);
        rl::ImageDrawPixel(img, x + 17, 3, rl::BLACK);
    }
    return honk::Sheet { texture: honk::bake(eng, img), cols: 2, rows: 1 };
}

// A fox, two frames of 24x18 facing right.
fn fox_sheet(eng: honk::Engine&) -> honk::Sheet {
    var img = rl::GenImageColor(48, 18, rl::BLANK);
    let fur = rl::Color { 225, 110, 35, 255 };
    for i in 2 {
        let x: i32 = (i as i32)*24;
        let step: i32 = if i == 0 { 0 } else { 2 };
        rl::ImageDrawCircle(img, x + 4, 9, 4, fur);
        rl::ImageDrawCircle(img, x + 2, 8, 2, rl::RAYWHITE);
        rl::ImageDrawRectangle(img, x + 6, 7, 11, 6, fur);
        rl::ImageDrawRectangle(img, x + 7 + step, 13, 2, 5, rl::Color { 60, 30, 20, 255 });
        rl::ImageDrawRectangle(img, x + 14 - step, 13, 2, 5, rl::Color { 60, 30, 20, 255 });
        rl::ImageDrawCircle(img, x + 18, 7, 4, fur);
        rl::ImageDrawTriangle(img, v2(x + 16.0, 4.0), v2(x + 19.0, 4.0), v2(x + 17.0, 0.0), fur);
        rl::ImageDrawRectangle(img, x + 20, 7, 4, 3, rl::RAYWHITE);
        rl::ImageDrawPixel(img, x + 19, 6, rl::BLACK);
    }
    return honk::Sheet { texture: honk::bake(eng, img), cols: 2, rows: 1 };
}

// A honk: a quarter second of two detuned sawtooth waves sliding down in
// pitch, as the bytes of a 16-bit mono WAV file.
fn honk_wav() -> u8[>..] {
    let rate = 22050;
    let n = rate/4;
    var wav: u8[>..] = [];
    fn u32le(v: i64) { for i in 4 { wav.push(((v >> (8*i)) & 255) as! u8); } }
    fn u16le(v: i64) { for i in 2 { wav.push(((v >> (8*i)) & 255) as! u8); } }
    wav.append("RIFF");
    u32le(36 + 2*n);
    wav.append("WAVEfmt ");
    u32le(16);
    u16le(1);
    u16le(1);
    u32le(rate);
    u32le(2*rate);
    u16le(2);
    u16le(16);
    wav.append("data");
    u32le(2*n);
    var phase1 = 0.0;
    var phase2 = 0.0;
    for i in n {
        let t = i/(rate as f64);
        let pitch = 330.0 - 120.0*t;
        phase1 += pitch/rate;
        phase2 += pitch*1.012/rate;
        let saw = (phase1 % 1.0) + (phase2 % 1.0) - 1.0;
        let envelope = min(t*40.0, 1.0)*(1.0 - t*4.0);
        u16le((saw*envelope*9000.0) as! i64);
    }
    return wav;
}

// --- main ------------------------------------------------------------------------

fn main() {
    var config = honk::Config { title: "Goose Grove", width: 1024, height: 600, audio: true,
                                clear: rl::Color { 40, 60, 40, 255 } };
    let argv = args();
    var debug = false;
    var a = 1;
    while a < argv.len {
        if argv[a] == "--autoplay" { autoplay = true; }
        else if argv[a] == "--debug" { debug = true; }
        else if argv[a] == "--fast" { config.fps = 0; }
        else if argv[a] == "--frames" && a + 1 < argv.len {
            a++;
            let n, ok = parse_int(argv[a]);
            if !ok || n <= 0 { abort("--frames needs a positive count"); }
            config.max_frames = n;
        } else { abort(str("unknown option: ", argv[a])); }
        a++;
    }
    honk::run(config) { eng =>
        bind_actions(eng);
        eng.debug = debug;
        if autoplay { rl::SetRandomSeed(42); }
        let wav = honk_wav();
        var scores, loaded = honk::load<Score>(SCORES_FILE);
        var s = Shared { goose: goose_sheet(eng), fox: fox_sheet(eng),
                         honk_sound: honk::sound(eng, ".wav", wav), scores: scores };
        honk::scenes(eng, Scene.Title) { scene =>
            match scene {
                Title => title(eng, s),
                Play => play(eng, s),
                Over o => over(eng, s, o.points, o.wave),
            }
        };
    };
}
