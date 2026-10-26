// honk: loaded resources, unloaded in the reverse order of loading.
//
// Textures, fonts, shaders, sounds and music live outside Goose's memory, in
// raylib and on the GPU, so no scope frees them. honk keeps them on a stack
// that follows the scopes instead: every load pushes the resource, and the
// end of a scene (honk::scenes), of a honk::scope, or of the run, unloads
// everything loaded since it started. A scene therefore loads what it needs
// and never unloads anything by hand.
//
// The load functions return raylib's own values (rl::Texture, rl::Shader,
// ...), which draw commands copy. Using one after its scope has ended draws
// nothing or plays nothing; it does not touch freed memory.

namespace honk;

import std;
import rl;

enum Asset {
    Texture { t: rl::Texture },
    Target { t: rl::RenderTexture },
    Font { f: rl::Font },
    Shader { s: rl::Shader },
    Sound { s: rl::Sound },
    Music { m: rl::Music },
}

fn unload(eng: Engine&, a: Asset) {
    match a {
        Texture t => rl::UnloadTexture(t.t),
        Target t => rl::UnloadRenderTexture(t.t),
        Font f => rl::UnloadFont(f.f),
        Shader s => {
            if eng.has_post && eng.post.id == s.s.id { eng.has_post = false; }
            rl::UnloadShader(s.s);
        },
        Sound s => rl::UnloadSound(s.s),
        Music m => {
            if eng.has_music && eng.music.ctxData == m.m.ctxData { rl::StopMusicStream(eng.music); eng.has_music = false; }
            rl::UnloadMusicStream(m.m);
        },
    }
}

// The asset stack's height: release(eng, mark(eng)) later unloads what was
// loaded in between.
fn mark(eng: Engine&) -> i64 { eng.assets.len }

// Unloads everything loaded since `mark`, latest first.
fn release(eng: Engine&, mark: i64) {
    while eng.assets.len > mark { unload(eng, eng.assets.pop()); }
}

// Runs body(), then unloads what it loaded, however it ends: for an overlay
// or a level inside a scene.
fn scope<F>(eng: Engine&) {
    let m = eng.assets.len;
    defer release(eng, m);
    F();
}

// --- loading -------------------------------------------------------------------

fn load_texture(eng: Engine&, path: const u8[:]) -> rl::Texture {
    let t = rl::LoadTexture(path);
    eng.assets.push(Asset.Texture { t: t });
    return t;
}

// Uploads an image to the GPU and unloads the image: draw into an rl::Image
// with rl::ImageDraw* and bake it into a texture.
fn bake(eng: Engine&, image: rl::Image) -> rl::Texture {
    let t = rl::LoadTextureFromImage(image);
    rl::UnloadImage(image);
    eng.assets.push(Asset.Texture { t: t });
    return t;
}

fn render_texture(eng: Engine&, width: i32, height: i32) -> rl::RenderTexture {
    let t = rl::LoadRenderTexture(width, height);
    eng.assets.push(Asset.Target { t: t });
    return t;
}

fn load_font(eng: Engine&, path: const u8[:], size: i32) -> rl::Font {
    let f = rl::LoadFontEx(path, size, []);
    eng.assets.push(Asset.Font { f: f });
    return f;
}

// A shader from files; an empty path keeps raylib's default for that stage.
fn load_shader(eng: Engine&, vertex: const u8[:], fragment: const u8[:]) -> rl::Shader {
    let s = rl::LoadShader(vertex, fragment);
    eng.assets.push(Asset.Shader { s: s });
    return s;
}

// A shader from source code; an empty string keeps raylib's default.
fn shader(eng: Engine&, vertex: const u8[:], fragment: const u8[:]) -> rl::Shader {
    let s = rl::LoadShaderFromMemory(vertex, fragment);
    eng.assets.push(Asset.Shader { s: s });
    return s;
}

// A fragment shader from source code, with raylib's default vertex shader.
fn shader(eng: Engine&, fragment: const u8[:]) -> rl::Shader { shader(eng, "", fragment) }

fn load_sound(eng: Engine&, path: const u8[:]) -> rl::Sound {
    let s = rl::LoadSound(path);
    eng.assets.push(Asset.Sound { s: s });
    return s;
}

// A sound from the bytes of a sound file (".wav", ".ogg", ...), such as one
// a program builds or embeds with embed_file.
fn sound(eng: Engine&, file_type: const u8[:], data: const u8[:]) -> rl::Sound {
    let wave = rl::LoadWaveFromMemory(file_type, data);
    let s = rl::LoadSoundFromWave(wave);
    rl::UnloadWave(wave);
    eng.assets.push(Asset.Sound { s: s });
    return s;
}

fn load_music(eng: Engine&, path: const u8[:]) -> rl::Music {
    let m = rl::LoadMusicStream(path);
    eng.assets.push(Asset.Music { m: m });
    return m;
}

// Plays music, streamed by the frame loop, in place of what was playing.
fn play_music(eng: Engine&, music: rl::Music) {
    if eng.has_music { rl::StopMusicStream(eng.music); }
    eng.music = music;
    eng.has_music = true;
    rl::PlayMusicStream(music);
}

fn stop_music(eng: Engine&) {
    if eng.has_music { rl::StopMusicStream(eng.music); }
    eng.has_music = false;
}

// --- shader uniforms -----------------------------------------------------------

// Sets a float uniform by name; does nothing if the shader has no such uniform.
fn set_uniform(shader: rl::Shader, name: const u8[:], value: f32) {
    let loc = rl::GetShaderLocation(shader, name);
    if loc >= 0 { rl::SetShaderValue(shader, loc, value, rl::SHADER_UNIFORM_FLOAT); }
}

fn set_uniform(shader: rl::Shader, name: const u8[:], value: rl::Vector2) {
    let loc = rl::GetShaderLocation(shader, name);
    if loc >= 0 { rl::SetShaderValue(shader, loc, value, rl::SHADER_UNIFORM_VEC2); }
}

fn set_uniform(shader: rl::Shader, name: const u8[:], value: rl::Vector4) {
    let loc = rl::GetShaderLocation(shader, name);
    if loc >= 0 { rl::SetShaderValue(shader, loc, value, rl::SHADER_UNIFORM_VEC4); }
}
