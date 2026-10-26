// honk: sprite sheets and frame animation.

namespace honk;

import std;
import math;
import rl;

// A texture cut into a grid of equal frames, numbered left to right, top to
// bottom.
struct Sheet { texture: rl::Texture, cols: i32, rows: i32 }

fn frame_size(s: Sheet) -> rl::Vector2 {
    rl::Vector2 { s.texture.width/s.cols, s.texture.height/s.rows }
}

fn frame_rect(s: Sheet, frame: i32) -> rl::Rectangle {
    let size = frame_size(s);
    let i = frame % (s.cols*s.rows);
    return rl::Rectangle { (i % s.cols)*size.x, (i/s.cols)*size.y, size.x, size.y };
}

// Frames first .. first + count - 1 of a sheet, at `fps` frames a second.
struct Anim { first: i32, count: i32, fps: f32, looping: bool = true }

// The frame of `a` that shows `t` seconds after it started.
fn frame_at(a: Anim, t: f64) -> i32 {
    let n = (t*a.fps) as! i32;
    if a.looping { return a.first + n % a.count; }
    return a.first + min(n, a.count - 1);
}

// Whether a non-looping animation has shown its last frame for its time.
fn finished(a: Anim, t: f64) -> bool { !a.looping && t*a.fps >= a.count }

// Draws frame `frame` of a sheet centered on `pos`, scaled, rotated by
// `rotation` degrees, and mirrored left to right if `flip`.
fn sprite(f: Frame&, sheet: Sheet, frame: i32, pos: rl::Vector2, scale: f32, rotation: f32,
          flip: bool, tint: rl::Color) {
    var src = frame_rect(sheet, frame);
    if flip { src.width = -src.width; }
    let w = abs(src.width)*scale;
    let h = src.height*scale;
    f.sprite(sheet.texture, src, rl::Rectangle { pos.x, pos.y, w, h }, rl::Vector2 { w/2.0, h/2.0 },
             rotation, tint);
}
