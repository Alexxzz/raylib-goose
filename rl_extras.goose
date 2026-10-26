// rl: hand-written additions to the generated bindings in rl.goose.
//
// raylib takes `const void *` for data whose type the caller knows: a shader
// uniform, a texture's pixels, audio samples, mesh vertices. The generated
// bindings declare these as u64 (an address only C can give). Here the same
// C functions are bound again with typed references, and wrapped to take
// Goose slices, so a call passes Goose data:
//
//   let time: f32 = rl::GetTime() as f32;
//   rl::SetShaderValue(shader, loc, time, rl::SHADER_UNIFORM_FLOAT);
//   rl::UpdateTexture(texture, pixels);              // pixels: rl::Color[>..]

namespace rl;

extern "raylib" {
    fn c_SetShaderValue_f32(shader: Shader, locIndex: i32, value: const f32&, uniformType: i32) = "SetShaderValue";
    fn c_SetShaderValue_i32(shader: Shader, locIndex: i32, value: const i32&, uniformType: i32) = "SetShaderValue";
    fn c_SetShaderValue_v2(shader: Shader, locIndex: i32, value: const Vector2&, uniformType: i32) = "SetShaderValue";
    fn c_SetShaderValue_v3(shader: Shader, locIndex: i32, value: const Vector3&, uniformType: i32) = "SetShaderValue";
    fn c_SetShaderValue_v4(shader: Shader, locIndex: i32, value: const Vector4&, uniformType: i32) = "SetShaderValue";
    fn c_SetShaderValueV_f32(shader: Shader, locIndex: i32, value: const f32&, uniformType: i32, count: i32) = "SetShaderValueV";
    fn c_SetShaderValueV_i32(shader: Shader, locIndex: i32, value: const i32&, uniformType: i32, count: i32) = "SetShaderValueV";
    fn c_SetShaderValueV_v2(shader: Shader, locIndex: i32, value: const Vector2&, uniformType: i32, count: i32) = "SetShaderValueV";
    fn c_SetShaderValueV_v3(shader: Shader, locIndex: i32, value: const Vector3&, uniformType: i32, count: i32) = "SetShaderValueV";
    fn c_SetShaderValueV_v4(shader: Shader, locIndex: i32, value: const Vector4&, uniformType: i32, count: i32) = "SetShaderValueV";

    fn c_UpdateTexture_colors(texture: Texture2D, pixels: const Color&) = "UpdateTexture";
    fn c_UpdateTextureRec_colors(texture: Texture2D, rec: Rectangle, pixels: const Color&) = "UpdateTextureRec";

    fn c_UpdateSound_i16(sound: Sound, data: const i16&, sampleCount: i32) = "UpdateSound";
    fn c_UpdateSound_f32(sound: Sound, data: const f32&, sampleCount: i32) = "UpdateSound";
    fn c_UpdateAudioStream_i16(stream: AudioStream, data: const i16&, frameCount: i32) = "UpdateAudioStream";
    fn c_UpdateAudioStream_f32(stream: AudioStream, data: const f32&, frameCount: i32) = "UpdateAudioStream";

    fn c_UpdateMeshBuffer_f32(mesh: Mesh, index: i32, data: const f32&, dataSize: i32, offset: i32) = "UpdateMeshBuffer";

    fn c_SaveFileData_bytes(fileName: const u8&, data: const u8&, dataSize: i32) -> bool = "SaveFileData";
}

// --- shader uniforms ------------------------------------------------------------
//
// The value is passed by reference, so it must be a variable, not a literal.

fn SetShaderValue(shader: Shader, locIndex: i32, value: const f32&, uniformType: i32) {
    c_SetShaderValue_f32(shader, locIndex, value, uniformType);
}
fn SetShaderValue(shader: Shader, locIndex: i32, value: const i32&, uniformType: i32) {
    c_SetShaderValue_i32(shader, locIndex, value, uniformType);
}
fn SetShaderValue(shader: Shader, locIndex: i32, value: const Vector2&, uniformType: i32) {
    c_SetShaderValue_v2(shader, locIndex, value, uniformType);
}
fn SetShaderValue(shader: Shader, locIndex: i32, value: const Vector3&, uniformType: i32) {
    c_SetShaderValue_v3(shader, locIndex, value, uniformType);
}
fn SetShaderValue(shader: Shader, locIndex: i32, value: const Vector4&, uniformType: i32) {
    c_SetShaderValue_v4(shader, locIndex, value, uniformType);
}

// A uniform array: count is the slice's length, which must not be 0.
fn SetShaderValueV(shader: Shader, locIndex: i32, values: const f32[:], uniformType: i32) {
    c_SetShaderValueV_f32(shader, locIndex, values[0], uniformType, values.len as i32);
}
fn SetShaderValueV(shader: Shader, locIndex: i32, values: const i32[:], uniformType: i32) {
    c_SetShaderValueV_i32(shader, locIndex, values[0], uniformType, values.len as i32);
}
fn SetShaderValueV(shader: Shader, locIndex: i32, values: const Vector2[:], uniformType: i32) {
    c_SetShaderValueV_v2(shader, locIndex, values[0], uniformType, values.len as i32);
}
fn SetShaderValueV(shader: Shader, locIndex: i32, values: const Vector3[:], uniformType: i32) {
    c_SetShaderValueV_v3(shader, locIndex, values[0], uniformType, values.len as i32);
}
fn SetShaderValueV(shader: Shader, locIndex: i32, values: const Vector4[:], uniformType: i32) {
    c_SetShaderValueV_v4(shader, locIndex, values[0], uniformType, values.len as i32);
}

// --- textures -------------------------------------------------------------------

// Update GPU texture with new data, for a PIXELFORMAT_UNCOMPRESSED_R8G8B8A8
// texture: pixels holds width*height colors.
fn UpdateTexture(texture: Texture2D, pixels: const Color[:]) {
    assert(pixels.len >= texture.width*(texture.height as i64));
    c_UpdateTexture_colors(texture, pixels[0]);
}

// Update GPU texture rectangle with new data: pixels holds rec's width*height colors.
fn UpdateTextureRec(texture: Texture2D, rec: Rectangle, pixels: const Color[:]) {
    assert(pixels.len >= (rec.width as i64)*(rec.height as i64));
    c_UpdateTextureRec_colors(texture, rec, pixels[0]);
}

// --- audio ----------------------------------------------------------------------
//
// data holds 16-bit or 32-bit float samples, matching the sound's or the
// stream's sampleSize; frames counts samples per channel.

fn UpdateSound(sound: Sound, data: const i16[:], frames: i32) {
    assert((frames as i64)*sound.stream.channels <= data.len);
    c_UpdateSound_i16(sound, data[0], frames);
}
fn UpdateSound(sound: Sound, data: const f32[:], frames: i32) {
    assert((frames as i64)*sound.stream.channels <= data.len);
    c_UpdateSound_f32(sound, data[0], frames);
}
fn UpdateAudioStream(stream: AudioStream, data: const i16[:], frames: i32) {
    assert((frames as i64)*stream.channels <= data.len);
    c_UpdateAudioStream_i16(stream, data[0], frames);
}
fn UpdateAudioStream(stream: AudioStream, data: const f32[:], frames: i32) {
    assert((frames as i64)*stream.channels <= data.len);
    c_UpdateAudioStream_f32(stream, data[0], frames);
}

// --- meshes and files -----------------------------------------------------------

// Update mesh vertex data in GPU for a specific buffer index; offset is in bytes.
fn UpdateMeshBuffer(mesh: Mesh, index: i32, data: const f32[:], offset: i32) {
    c_UpdateMeshBuffer_f32(mesh, index, data[0], (data.len*4) as i32, offset);
}

// Save data to file from byte array (write), returns true on success
fn SaveFileData(fileName: const u8[:], data: const u8[:]) -> bool {
    let name = cstring(fileName);
    let empty: u8[1] = [0];
    if data.len == 0 { return c_SaveFileData_bytes(name[0], empty[0], 0); }
    return c_SaveFileData_bytes(name[0], data[0], data.len as i32);
}
