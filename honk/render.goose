// honk: the draw list. Drawing records commands; the frame loop sorts them
// by pass, layer and order of recording, culls the world ones against the
// camera's view, and draws them.
//
// The commands of a frame are one array of variable-mode values: each takes
// the bytes of its own variant, and a text or a polyline is stored inside
// its command, at its length. The array is walked, never indexed, so a
// second array holds a 17-byte entry per command: its sort key, its shader
// and a reference to it. Sorting moves the entries; the commands stay where
// they were built. Both arrays belong to the frame's iteration and are freed
// with it.

namespace honk;

import std;
import math;
import rl;

enum Cmd {
    Rect { r: rl::Rectangle, origin: rl::Vector2, rotation: f32, color: rl::Color },
    RectLines { r: rl::Rectangle, thick: f32, color: rl::Color },
    Circle { center: rl::Vector2, radius: f32, color: rl::Color },
    CircleLines { center: rl::Vector2, radius: f32, color: rl::Color },
    Ring { center: rl::Vector2, inner: f32, outer: f32, color: rl::Color },
    Line { a: rl::Vector2, b: rl::Vector2, thick: f32, color: rl::Color },
    Triangle { a: rl::Vector2, b: rl::Vector2, c: rl::Vector2, color: rl::Color },
    Poly { center: rl::Vector2, sides: i32, radius: f32, rotation: f32, color: rl::Color },
    Sprite { texture: rl::Texture, src: rl::Rectangle, dst: rl::Rectangle, origin: rl::Vector2,
             rotation: f32, tint: rl::Color },
    Lines { thick: f32, color: rl::Color, points: rl::Vector2[varint] },
    Text { pos: rl::Vector2, size: f32, spacing: f32, font: u8, color: rl::Color, text: u8[varint] },
}

// An index entry, 17 bytes: the sort key (pass, layer, order of
// recording), the shader's slot in the frame (0: none) and the command.
struct Item { key: i64, shader: u8, cmd: Cmd..& }
let ITEM_BYTES = 17;

// One frame: its time, the drawing state for the commands recorded next,
// and the two arrays, which are locals of honk::frames.
struct Frame {
    eng: Engine&,
    dt: f32,
    time: f64,
    index: i64,
    layer: i32,                 // higher layers draw over lower ones, -32768..32767
    space: i32,                 // BACKGROUND, WORLD or SCREEN
    shader: u8,                 // slot in shaders + 1, 0: none
    font: u8,                   // slot in fonts + 1, 0: raylib's default font
    seq: i64,
    shaders: rl::Shader[..15],  // the shaders this frame uses
    fonts: rl::Font[..15],      // the fonts this frame uses
    cmds: Cmd..[>..]&,
    order: Item[>..]&,
}

fn record(f: Frame&, c: Cmd..&) {
    let layer = (clamp(f.layer, -32768, 32767) + 32768) as i64;
    f.order.push(Item { key: (f.space as i64) << 56 | layer << 40 | f.seq, shader: f.shader, cmd: c });
    f.seq++;
}

// The screen's size in pixels, as floats for drawing.
fn width(f: Frame&) -> f32 { rl::GetScreenWidth() }
fn height(f: Frame&) -> f32 { rl::GetScreenHeight() }

// --- drawing state -------------------------------------------------------------

// Commands recorded after this are drawn in screen pixels, over the world.
fn screen(f: Frame&) { f.space = SCREEN; }

// Commands recorded after this are drawn in screen pixels, under the world:
// a sky, a backdrop.
fn background(f: Frame&) { f.space = BACKGROUND; }

// Commands recorded after this are drawn through the camera (the default).
fn world(f: Frame&) { f.space = WORLD; }

// Commands recorded after this are drawn with `shader` (a fragment shader;
// raylib's default vertex shader if it was loaded with an empty one).
fn use_shader(f: Frame&, shader: rl::Shader) {
    for i in f.shaders.len {
        if f.shaders[i].id == shader.id { f.shader = (i + 1) as! u8; return; }
    }
    assert(f.shaders.len < 15);
    f.shaders.push(shader);
    f.shader = f.shaders.len as! u8;
}

// Commands recorded after this are drawn without a shader (the default).
fn no_shader(f: Frame&) { f.shader = 0; }

// Text recorded after this uses `font`.
fn use_font(f: Frame&, font: rl::Font) {
    for i in f.fonts.len {
        if f.fonts[i].texture.id == font.texture.id { f.font = (i + 1) as! u8; return; }
    }
    assert(f.fonts.len < 15);
    f.fonts.push(font);
    f.font = f.fonts.len as! u8;
}

// Text recorded after this uses raylib's default font (the default).
fn default_font(f: Frame&) { f.font = 0; }

// --- shapes --------------------------------------------------------------------

fn rect(f: Frame&, r: rl::Rectangle, color: rl::Color) {
    f.record(f.cmds.push(Cmd.Rect { r: r, origin: rl::Vector2 { 0.0, 0.0 }, rotation: 0.0, color: color }));
}

// A rectangle of `size` centered on `center`, rotated by `rotation` degrees.
fn rect(f: Frame&, center: rl::Vector2, size: rl::Vector2, rotation: f32, color: rl::Color) {
    let r = rl::Rectangle { center.x, center.y, size.x, size.y };
    let origin = rl::Vector2 { size.x/2.0, size.y/2.0 };
    f.record(f.cmds.push(Cmd.Rect { r: r, origin: origin, rotation: rotation, color: color }));
}

fn rect_lines(f: Frame&, r: rl::Rectangle, thick: f32, color: rl::Color) {
    f.record(f.cmds.push(Cmd.RectLines { r: r, thick: thick, color: color }));
}

fn circle(f: Frame&, center: rl::Vector2, radius: f32, color: rl::Color) {
    f.record(f.cmds.push(Cmd.Circle { center: center, radius: radius, color: color }));
}

fn circle_lines(f: Frame&, center: rl::Vector2, radius: f32, color: rl::Color) {
    f.record(f.cmds.push(Cmd.CircleLines { center: center, radius: radius, color: color }));
}

fn ring(f: Frame&, center: rl::Vector2, inner: f32, outer: f32, color: rl::Color) {
    f.record(f.cmds.push(Cmd.Ring { center: center, inner: inner, outer: outer, color: color }));
}

fn line(f: Frame&, a: rl::Vector2, b: rl::Vector2, thick: f32, color: rl::Color) {
    f.record(f.cmds.push(Cmd.Line { a: a, b: b, thick: thick, color: color }));
}

// A polyline through `points`, copied into the command.
fn lines(f: Frame&, points: const rl::Vector2[:], thick: f32, color: rl::Color) {
    if points.len < 2 { return; }
    f.record(f.cmds.push(Cmd.Lines { thick: thick, color: color, points: points }));
}

// A filled triangle; a, b and c go counterclockwise on screen.
fn triangle(f: Frame&, a: rl::Vector2, b: rl::Vector2, c: rl::Vector2, color: rl::Color) {
    f.record(f.cmds.push(Cmd.Triangle { a: a, b: b, c: c, color: color }));
}

// A regular polygon, rotated by `rotation` degrees.
fn poly(f: Frame&, center: rl::Vector2, sides: i32, radius: f32, rotation: f32, color: rl::Color) {
    f.record(f.cmds.push(Cmd.Poly { center: center, sides: sides, radius: radius, rotation: rotation, color: color }));
}

// --- textures ------------------------------------------------------------------

// The whole texture with its top left corner at `pos`.
fn texture(f: Frame&, texture: rl::Texture, pos: rl::Vector2, tint: rl::Color) {
    let src = rl::Rectangle { 0.0, 0.0, texture.width, texture.height };
    let dst = rl::Rectangle { pos.x, pos.y, texture.width, texture.height };
    f.sprite(texture, src, dst, rl::Vector2 { 0.0, 0.0 }, 0.0, tint);
}

// The `src` part of a texture drawn into `dst`, rotated by `rotation` degrees
// around `origin` (relative to dst's corner). A negative src width or height
// flips it.
fn sprite(f: Frame&, texture: rl::Texture, src: rl::Rectangle, dst: rl::Rectangle,
          origin: rl::Vector2, rotation: f32, tint: rl::Color) {
    f.record(f.cmds.push(Cmd.Sprite { texture: texture, src: src, dst: dst, origin: origin,
                                      rotation: rotation, tint: tint }));
}

// --- text ----------------------------------------------------------------------

// Text with its top left corner at `pos`, `size` pixels high, copied into
// the command.
fn text(f: Frame&, text: const u8[:], pos: rl::Vector2, size: f32, color: rl::Color) {
    let spacing = size/10.0;
    f.record(f.cmds.push(Cmd.Text { pos: pos, size: size, spacing: spacing, font: f.font,
                                    color: color, text: text }));
}

// Text centered on `center`.
fn text_centered(f: Frame&, text: const u8[:], center: rl::Vector2, size: f32, color: rl::Color) {
    let extent = f.measure(text, size);
    f.text(text, rl::Vector2 { center.x - extent.x/2.0, center.y - extent.y/2.0 }, size, color);
}

// The width and height text takes in the current font.
fn measure(f: Frame&, text: const u8[:], size: f32) -> rl::Vector2 {
    let font = if f.font == 0 { rl::GetFontDefault() } else { f.fonts[f.font - 1] };
    return rl::MeasureTextEx(font, text, size, size/10.0);
}

// --- drawing the list ----------------------------------------------------------

// A rectangle around everything the command draws; rotated shapes get a
// square around every rotation.
fn bounds(c: Cmd..&) -> rl::Rectangle {
    match c {
        Rect r => if r.rotation == 0.0 { r.r } else { around(rl::Vector2 { r.r.x, r.r.y }, abs(r.r.width) + abs(r.r.height)) },
        RectLines r => r.r,
        Circle c => around(c.center, c.radius),
        CircleLines c => around(c.center, c.radius),
        Ring r => around(r.center, r.outer),
        Line l => span(l.a, l.b, l.thick),
        Triangle t => span(rl::Vector2Min(t.a, rl::Vector2Min(t.b, t.c)), rl::Vector2Max(t.a, rl::Vector2Max(t.b, t.c)), 0.0),
        Poly p => around(p.center, p.radius),
        Sprite s => if s.rotation == 0.0 && s.origin.x == 0.0 && s.origin.y == 0.0 { s.dst }
                    else { around(rl::Vector2 { s.dst.x, s.dst.y }, abs(s.dst.width) + abs(s.dst.height)) },
        Lines l => points_bounds(l.points, l.thick),
        Text t => rl::Rectangle { t.pos.x, t.pos.y, t.size*t.text.len, t.size },
    }
}

fn around(center: rl::Vector2, r: f32) -> rl::Rectangle {
    rl::Rectangle { center.x - r, center.y - r, 2.0*r, 2.0*r }
}

fn span(a: rl::Vector2, b: rl::Vector2, margin: f32) -> rl::Rectangle {
    let lo = rl::Vector2Min(a, b);
    let hi = rl::Vector2Max(a, b);
    rl::Rectangle { lo.x - margin, lo.y - margin, hi.x - lo.x + 2.0*margin, hi.y - lo.y + 2.0*margin }
}

fn points_bounds(points: const rl::Vector2[:], margin: f32) -> rl::Rectangle {
    var lo = points[0];
    var hi = points[0];
    for p in points {
        lo = rl::Vector2Min(lo, p);
        hi = rl::Vector2Max(hi, p);
    }
    return span(lo, hi, margin);
}

// The segments a circle of `radius` needs to look round at `scale` screen
// pixels per unit: a few for a dot, up to 72 for a big circle. raylib's own
// DrawCircleV always uses 36, eighteen quads even for a speck.
fn segments(radius: f32, scale: f32) -> i32 {
    clamp((sqrt(radius*scale)*4.0) as! i32, 6, 72)
}

// Draws one command; `scale` is screen pixels per unit in its pass.
fn draw(f: Frame&, c: Cmd..&, scale: f32) {
    match c {
        Rect r => rl::DrawRectanglePro(r.r, r.origin, r.rotation, r.color),
        RectLines r => rl::DrawRectangleLinesEx(r.r, r.thick, r.color),
        Circle c => rl::DrawCircleSector(c.center, c.radius, 0.0, 360.0, segments(c.radius, scale), c.color),
        CircleLines c => rl::DrawCircleSectorLines(c.center, c.radius, 0.0, 360.0, segments(c.radius, scale), c.color),
        Ring r => rl::DrawRing(r.center, r.inner, r.outer, 0.0, 360.0, segments(r.outer, scale), r.color),
        Line l => rl::DrawLineEx(l.a, l.b, l.thick, l.color),
        Triangle t => rl::DrawTriangle(t.a, t.b, t.c, t.color),
        Poly p => rl::DrawPoly(p.center, p.sides, p.radius, p.rotation, p.color),
        Sprite s => rl::DrawTexturePro(s.texture, s.src, s.dst, s.origin, s.rotation, s.tint),
        Lines l => rl::DrawSplineLinear(l.points, l.thick, l.color),
        Text t => {
            let font = if t.font == 0 { rl::GetFontDefault() } else { f.fonts[t.font - 1] };
            rl::DrawTextEx(font, t.text, t.pos, t.size, t.spacing, t.color);
        },
    }
}

// Sorts and draws the frame's commands. Called by honk::frames.
fn flush(f: Frame&) {
    let eng .= f.eng;
    let t0 = rl::GetTime();
    stable_sort(f.order) { a, b => a.key < b.key };
    let t1 = rl::GetTime();
    let camera = shaken_camera(eng);
    let view = view_bounds(camera);
    let width = rl::GetScreenWidth();
    let height = rl::GetScreenHeight();
    let post = eng.has_post;
    if post && (!eng.has_target || eng.target.texture.width != width || eng.target.texture.height != height) {
        if eng.has_target { rl::UnloadRenderTexture(eng.target); }
        eng.target = rl::LoadRenderTexture(width, height);
        eng.has_target = true;
    }

    var drawn = 0;
    var culled = 0;
    var pass = -1;
    var shader: u8 = 0;

    rl::BeginDrawing();
    rl::ClearBackground(eng.config.clear);
    for it in f.order {
        let p = it.key >> 56;
        if p != pass {
            if shader != 0 { rl::EndShaderMode(); shader = 0; }
            if pass == WORLD { rl::EndMode2D(); }
            // The background and the world go into the post-processing
            // target together; the screen pass is drawn over the result.
            // Passes come in ascending order.
            if post && pass >= 0 && pass <= WORLD && p > WORLD { end_target(eng); }
            if post && pass < 0 && p <= WORLD { begin_target(eng); }
            if p == WORLD { rl::BeginMode2D(camera); }
            pass = p;
        }
        if it.shader != shader {
            if shader != 0 { rl::EndShaderMode(); }
            if it.shader != 0 { rl::BeginShaderMode(f.shaders[it.shader - 1]); }
            shader = it.shader;
        }
        if p == WORLD && !rl::CheckCollisionRecs(bounds(it.cmd), view) {
            culled++;
            continue;
        }
        draw(f, it.cmd, if p == WORLD { camera.zoom } else { 1.0 });
        drawn++;
    }
    if shader != 0 { rl::EndShaderMode(); }
    if pass == WORLD { rl::EndMode2D(); }
    if post && pass >= 0 && pass <= WORLD { end_target(eng); }
    let t2 = rl::GetTime();

    eng.stats = Stats {
        commands: f.order.len,
        drawn: drawn,
        culled: culled,
        command_bytes: bytes_of(f.cmds).len,
        index_bytes: f.order.len*ITEM_BYTES,
        sort_ms: (t1 - t0)*1000.0,
        draw_ms: (t2 - t1)*1000.0,
        present_ms: eng.stats.present_ms,       // the frame before's: this one's is not over
    };
    if eng.debug { draw_debug(eng); }
    if eng.capture {
        // Read before the buffers swap, while the frame is still there.
        // raylib batches drawing until a state change or EndDrawing;
        // EndMode2D outside a 2D mode only draws the batch out and resets
        // the transform to the screen's.
        rl::EndMode2D();
        if eng.has_captured { rl::UnloadImage(eng.captured); }
        eng.captured = rl::LoadImageFromScreen();
        eng.has_captured = true;
        eng.capture = false;
    }
    let t3 = rl::GetTime();
    rl::EndDrawing();
    eng.stats.present_ms = (rl::GetTime() - t3)*1000.0;
}

fn begin_target(eng: Engine&) {
    rl::BeginTextureMode(eng.target);
    rl::ClearBackground(eng.config.clear);
}

fn end_target(eng: Engine&) {
    rl::EndTextureMode();
    // A render texture is upside down: draw it with a negative height.
    let t = eng.target.texture;
    rl::BeginShaderMode(eng.post);
    rl::DrawTextureRec(t, rl::Rectangle { 0.0, 0.0, t.width, -t.height }, rl::Vector2 { 0.0, 0.0 }, rl::WHITE);
    rl::EndShaderMode();
}

fn draw_debug(eng: Engine&) {
    let s = eng.stats;
    rl::DrawRectangle(4, 4, 340, 108, rl::Fade(rl::BLACK, 0.7));
    rl::DrawText(str(rl::GetFPS(), " fps, frame ", eng.frame), 10, 8, 18, rl::GREEN);
    rl::DrawText(str(s.commands, " commands: ", s.drawn, " drawn, ", s.culled, " culled"), 10, 28, 18, rl::GREEN);
    rl::DrawText(str("draw list ", s.command_bytes, " + ", s.index_bytes, " bytes"), 10, 48, 18, rl::GREEN);
    rl::DrawText(str(eng.assets.len, " assets loaded"), 10, 68, 18, rl::GREEN);
    rl::DrawText(str("sort ", ms(s.sort_ms), ", draw ", ms(s.draw_ms), ", present ", ms(s.present_ms), " ms"), 10, 88, 18, rl::GREEN);
}

fn ms(x: f64) -> f64 { ((x*100.0) as! i64)/100.0
}
