// honk: input actions. A game names what the player can do (jump, fire,
// pause) as small integers, binds keys, mouse buttons and gamepad inputs to
// them, and asks about actions rather than keys:
//
//   let JUMP = 0;
//   honk::bind_key(eng, JUMP, rl::KEY_SPACE);
//   honk::bind_pad(eng, JUMP, rl::GAMEPAD_BUTTON_RIGHT_FACE_DOWN);
//   if f.pressed(JUMP) { ... }
//
// The bindings sit inline in the engine, and the state of all 64 possible
// actions is one u64 per frame, read once when the frame starts.

namespace honk;

import std;
import rl;

let KEY = 0;
let MOUSE = 1;
let PAD_BUTTON = 2;
let PAD_AXIS_POS = 3;           // an axis past +0.5
let PAD_AXIS_NEG = 4;           // an axis past -0.5

let ACTIONS = 64;

struct Binding { action: u8, device: u8, gamepad: u8, code: i32 }

fn bind(eng: Engine&, action: i64, device: i64, gamepad: i64, code: i32) {
    assert(action >= 0 && action < ACTIONS);
    assert(eng.bindings.len < 64);
    eng.bindings.push(Binding { action: action as! u8, device: device as! u8, gamepad: gamepad as! u8, code: code });
}

fn bind_key(eng: Engine&, action: i64, key: i32) { bind(eng, action, KEY, 0, key); }

fn bind_mouse(eng: Engine&, action: i64, button: i32) { bind(eng, action, MOUSE, 0, button); }

fn bind_pad(eng: Engine&, action: i64, button: i32, gamepad: i64 = 0) { bind(eng, action, PAD_BUTTON, gamepad, button); }

// The action is down while gamepad `axis` is past half way, toward the
// positive end if `positive`.
fn bind_axis(eng: Engine&, action: i64, axis: i32, positive: bool, gamepad: i64 = 0) {
    bind(eng, action, if positive { PAD_AXIS_POS } else { PAD_AXIS_NEG }, gamepad, axis);
}

// Removes every binding.
fn unbind_all(eng: Engine&) { eng.bindings.clear(); }

// Holds the action down for the next frame, as if a bound input were down:
// for tests, demos, replays and computer players.
fn press(eng: Engine&, action: i64) {
    assert(action >= 0 && action < ACTIONS);
    eng.forced |= (1 as u64) << action;
}

fn bit(action: i64) -> u64 {
    assert(action >= 0 && action < ACTIONS);
    (1 as u64) << action
}

fn binding_down(b: Binding) -> bool {
    let gamepad = b.gamepad as i32;
    match b.device as i64 {
        KEY => rl::IsKeyDown(b.code),
        MOUSE => rl::IsMouseButtonDown(b.code),
        PAD_BUTTON => rl::IsGamepadAvailable(gamepad) && rl::IsGamepadButtonDown(gamepad, b.code),
        PAD_AXIS_POS => rl::IsGamepadAvailable(gamepad) && rl::GetGamepadAxisMovement(gamepad, b.code) > 0.5,
        _ => rl::IsGamepadAvailable(gamepad) && rl::GetGamepadAxisMovement(gamepad, b.code) < -0.5,
    }
}

// Reads every binding once. Called when a frame starts.
fn poll(eng: Engine&) {
    var now = eng.forced;
    for b in eng.bindings {
        if binding_down(b) { now |= (1 as u64) << b.action; }
    }
    eng.before = eng.now;
    eng.now = now;
    eng.forced = 0;
}

// The action is down this frame.
fn down(f: Frame&, action: i64) -> bool { f.eng.now & bit(action) != 0 }

// The action went down this frame.
fn pressed(f: Frame&, action: i64) -> bool { f.eng.now & ~f.eng.before & bit(action) != 0 }

// The action went up this frame.
fn released(f: Frame&, action: i64) -> bool { ~f.eng.now & f.eng.before & bit(action) != 0 }

// -1, 0 or 1 from two actions, such as left and right.
fn axis(f: Frame&, negative: i64, positive: i64) -> f32 {
    var v: f32 = 0.0;
    if f.down(negative) { v -= 1.0; }
    if f.down(positive) { v += 1.0; }
    return v;
}

// A direction from four actions, of length 1 or 0: diagonals are as fast as
// straight moves.
fn direction(f: Frame&, left: i64, right: i64, up: i64, down: i64) -> rl::Vector2 {
    rl::Vector2Normalize(rl::Vector2 { f.axis(left, right), f.axis(up, down) })
}

// The mouse, in screen pixels.
fn mouse(f: Frame&) -> rl::Vector2 { rl::GetMousePosition() }

// The mouse, in the world: through the camera (without its shake).
fn mouse_world(f: Frame&) -> rl::Vector2 { rl::GetScreenToWorld2D(rl::GetMousePosition(), f.eng.camera) }
