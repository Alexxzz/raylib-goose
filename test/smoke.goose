// A smoke test of the bindings against a real raylib: opens a window, calls
// a wide sample of the API, checks the results, draws a few frames and
// exits. Run it with a display (xvfb-run on a headless machine):
//
//   goose run test/smoke.goose
//
// It prints one line per failed check and ends with the count.

import rl from "..";

var checks = 0;
var failures = 0;

fn check(ok: bool, what: const u8[:]) {
    checks++;
    if !ok {
        failures++;
        print("FAILED: ", what);
    }
}

fn same(a: rl::Color, b: rl::Color) -> bool { a.r == b.r && a.g == b.g && a.b == b.b && a.a == b.a }

fn near(a: f32, b: f32) -> bool { rl::FloatEquals(a, b) }

fn strings() {
    check(rl::TextToUpper("goose") == "GOOSE", "TextToUpper");
    check(rl::TextLength("hello") == 5, "TextLength");
    check(rl::TextIsEqual("abc", "abc") && !rl::TextIsEqual("abc", "abd"), "TextIsEqual");
    check(rl::TextFindIndex("raylib goose", "goose") == 7, "TextFindIndex");
    check(rl::TextSubtext("raylib goose", 7, 5) == "goose", "TextSubtext");
    check(rl::GetFileName("assets/sprites/goose.png") == "goose.png", "GetFileName");
    check(rl::GetFileExtension("goose.png") == ".png", "GetFileExtension");
    check(rl::GetFileNameWithoutExt("dir/goose.png") == "goose", "GetFileNameWithoutExt");
    check(rl::IsFileExtension("goose.png", ".png;.jpg"), "IsFileExtension");
    check(rl::GetCodepointCount("h\xc3\xa9llo") == 5, "GetCodepointCount (UTF-8)");
    check(rl::TextToInteger("-1234") == -1234, "TextToInteger");
    check(rl::GetWorkingDirectory().len > 0, "GetWorkingDirectory");
    check(rl::MeasureText("goose", 20) > 0, "MeasureText");
    // An empty string passes an empty C string.
    check(rl::TextLength("") == 0, "TextLength of an empty string");

    var count: i32 = 0;
    let codepoints = rl::LoadCodepoints("h\xc3\xa9", count);
    check(count == 2 && codepoints != 0, "LoadCodepoints");
    rl::UnloadCodepoints(codepoints);
}

fn collisions() {
    let a = rl::Rectangle { 0.0, 0.0, 10.0, 10.0 };
    let b = rl::Rectangle { 5.0, 5.0, 10.0, 10.0 };
    check(rl::CheckCollisionRecs(a, b), "CheckCollisionRecs");
    let r = rl::GetCollisionRec(a, b);
    check(r.x == 5.0 && r.y == 5.0 && r.width == 5.0 && r.height == 5.0, "GetCollisionRec");
    check(rl::CheckCollisionCircles(rl::Vector2 { 0.0, 0.0 }, 1.0, rl::Vector2 { 1.5, 0.0 }, 1.0), "CheckCollisionCircles");
    let triangle = [rl::Vector2 { 0.0, 0.0 }, rl::Vector2 { 10.0, 0.0 }, rl::Vector2 { 0.0, 10.0 }];
    check(rl::CheckCollisionPointPoly(rl::Vector2 { 2.0, 2.0 }, triangle), "CheckCollisionPointPoly inside");
    check(!rl::CheckCollisionPointPoly(rl::Vector2 { 9.0, 9.0 }, triangle), "CheckCollisionPointPoly outside");

    let ray = rl::Ray { rl::Vector3 { -5.0, 0.5, 0.5 }, rl::Vector3 { 1.0, 0.0, 0.0 } };
    let box = rl::BoundingBox { rl::Vector3 { 0.0, 0.0, 0.0 }, rl::Vector3 { 1.0, 1.0, 1.0 } };
    let hit = rl::GetRayCollisionBox(ray, box);
    check(hit.hit && near(hit.distance, 5.0) && near(hit.normal.x, -1.0), "GetRayCollisionBox (RayCollision has padding)");
    let miss = rl::GetRayCollisionSphere(ray, rl::Vector3 { 0.0, 5.0, 0.0 }, 1.0);
    check(!miss.hit, "GetRayCollisionSphere miss");
}

fn colors() {
    check(rl::ColorToInt(rl::Color { 255, 0, 0, 255 }) == -16776961, "ColorToInt");  // 0xff0000ff
    check(same(rl::GetColor(0xff0000ff), rl::Color { 255, 0, 0, 255 }), "GetColor");
    check(same(rl::Fade(rl::Color { 10, 20, 30, 255 }, 0.5), rl::Color { 10, 20, 30, 127 }), "Fade");
    let hsv = rl::ColorToHSV(rl::Color { 0, 255, 0, 255 });
    check(near(hsv.x, 120.0) && near(hsv.y, 1.0) && near(hsv.z, 1.0), "ColorToHSV");
    check(same(rl::ColorFromHSV(0.0, 1.0, 1.0), rl::Color { 255, 0, 0, 255 }), "ColorFromHSV");
}

fn images() {
    var image = rl::GenImageColor(64, 32, rl::BLUE);
    check(image.width == 64 && image.height == 32 && image.data != 0, "GenImageColor");
    rl::ImageDrawRectangle(image, 0, 0, 8, 8, rl::RED);
    check(same(rl::GetImageColor(image, 1, 1), rl::RED) && same(rl::GetImageColor(image, 20, 20), rl::BLUE), "ImageDrawRectangle");
    rl::ImageResize(image, 32, 16);
    check(image.width == 32 && image.height == 16, "ImageResize through Image&");
    rl::ImageFlipVertical(image);
    check(same(rl::GetImageColor(image, 1, 15), rl::RED), "ImageFlipVertical");

    var size: i32 = 0;
    let png = rl::ExportImageToMemory(image, ".png", size);
    check(png != 0 && size > 8, "ExportImageToMemory");
    rl::MemFree(png);
    rl::UnloadImage(image);
}

fn files() {
    let list = rl::LoadDirectoryFilesEx(".", ".goose", false);
    check(list.count > 0, "LoadDirectoryFilesEx (FilePathList has padding)");
    rl::UnloadDirectoryFiles(list);
    check(rl::DirectoryExists("."), "DirectoryExists");
    check(!rl::FileExists("no such file.goose"), "FileExists");
}

fn random() {
    rl::SetRandomSeed(42);
    var in_range = true;
    for i in 100 {
        let v = rl::GetRandomValue(-3, 3);
        if v < -3 || v > 3 { in_range = false; }
    }
    check(in_range, "GetRandomValue");
    let sequence = rl::LoadRandomSequence(10, 0, 9);
    check(sequence != 0, "LoadRandomSequence");
    rl::UnloadRandomSequence(sequence);
}

fn raymath() {
    let m = rl::MatrixMultiply(rl::MatrixTranslate(1.0, 2.0, 3.0), rl::MatrixScale(2.0, 2.0, 2.0));
    let p = rl::Vector3Transform(rl::Vector3 { 1.0, 1.0, 1.0 }, m);
    check(rl::Vector3Equals(p, rl::Vector3 { 4.0, 6.0, 8.0 }), "MatrixMultiply, Vector3Transform");
    let q = rl::QuaternionFromAxisAngle(rl::Vector3 { 0.0, 1.0, 0.0 }, rl::PI/2.0);
    let v = rl::Vector3RotateByQuaternion(rl::Vector3 { 1.0, 0.0, 0.0 }, q);
    check(rl::Vector3Equals(v, rl::Vector3 { 0.0, 0.0, -1.0 }), "QuaternionFromAxisAngle, Vector3RotateByQuaternion");
    var t = rl::Vector3 { 0.0, 0.0, 0.0 };
    var r = rl::QuaternionIdentity();
    var s = rl::Vector3 { 0.0, 0.0, 0.0 };
    rl::MatrixDecompose(rl::MatrixCompose(rl::Vector3 { 1.0, 2.0, 3.0 }, q, rl::Vector3 { 2.0, 2.0, 2.0 }), t, r, s);
    check(rl::Vector3Equals(t, rl::Vector3 { 1.0, 2.0, 3.0 }) && rl::QuaternionEquals(r, q) &&
          rl::Vector3Equals(s, rl::Vector3 { 2.0, 2.0, 2.0 }), "MatrixCompose, MatrixDecompose");
    check(near(rl::Vector2Length(rl::Vector2 { 3.0, 4.0 }), 5.0), "Vector2Length");
}

fn rendering() {
    // Draw into a render texture, then read its pixels back from the GPU.
    let target = rl::LoadRenderTexture(64, 64);
    check(rl::IsRenderTextureValid(target), "LoadRenderTexture");
    rl::BeginTextureMode(target);
    rl::ClearBackground(rl::BLUE);
    rl::DrawRectangle(0, 0, 32, 64, rl::RED);
    rl::DrawLineStrip([rl::Vector2 { 40.0, 10.0 }, rl::Vector2 { 60.0, 10.0 }], rl::GREEN);
    rl::DrawLineStrip([], rl::GREEN);  // an empty slice passes NULL
    rl::EndTextureMode();
    let image = rl::LoadImageFromTexture(target.texture);
    check(same(rl::GetImageColor(image, 4, 30), rl::RED), "drawn pixel, left half");
    check(same(rl::GetImageColor(image, 60, 30), rl::BLUE), "drawn pixel, right half");
    rl::UnloadImage(image);

    // A texture updated from Goose pixels, drawn into the render texture.
    let source = rl::GenImageColor(4, 4, rl::BLACK);
    let texture = rl::LoadTextureFromImage(source);
    rl::UnloadImage(source);
    var pixels: rl::Color[>..] = [];
    for i in 16 { pixels.push(rl::YELLOW); }
    rl::UpdateTexture(texture, pixels);
    rl::BeginTextureMode(target);
    rl::DrawTexturePro(texture, rl::Rectangle { 0.0, 0.0, 4.0, 4.0 }, rl::Rectangle { 0.0, 0.0, 64.0, 64.0 },
                       rl::Vector2 { 0.0, 0.0 }, 0.0, rl::WHITE);
    rl::EndTextureMode();
    let updated = rl::LoadImageFromTexture(target.texture);
    check(same(rl::GetImageColor(updated, 32, 32), rl::YELLOW), "UpdateTexture with Goose colors");
    rl::UnloadImage(updated);
    rl::UnloadTexture(texture);

    // A shader with the default vertex shader (NULL) and a uniform.
    let shader = rl::LoadShaderFromMemory("", """
#version 330
out vec4 finalColor;
uniform vec4 tint;
void main() { finalColor = tint; }
""");
    check(rl::IsShaderValid(shader), "LoadShaderFromMemory with NULL vertex shader");
    let tint = rl::Vector4 { 0.0, 1.0, 1.0, 1.0 };
    rl::SetShaderValue(shader, rl::GetShaderLocation(shader, "tint"), tint, rl::SHADER_UNIFORM_VEC4);
    rl::BeginTextureMode(target);
    rl::BeginShaderMode(shader);
    rl::DrawRectangle(0, 0, 64, 64, rl::WHITE);
    rl::EndShaderMode();
    rl::EndTextureMode();
    let shaded = rl::LoadImageFromTexture(target.texture);
    check(same(rl::GetImageColor(shaded, 10, 10), rl::Color { 0, 255, 255, 255 }), "SetShaderValue (vec4 uniform)");
    rl::UnloadImage(shaded);
    rl::UnloadShader(shader);
    rl::UnloadRenderTexture(target);
}

fn models() {
    // Model and Mesh hold padding and cross by value.
    let mesh = rl::GenMeshCube(2.0, 4.0, 6.0);
    check(mesh.vertexCount == 24 && mesh.vertices != 0, "GenMeshCube");
    let model = rl::LoadModelFromMesh(mesh);
    check(rl::IsModelValid(model) && model.meshCount == 1 && model.materialCount == 1, "LoadModelFromMesh");
    let bounds = rl::GetModelBoundingBox(model);
    check(rl::Vector3Equals(bounds.min, rl::Vector3 { -1.0, -2.0, -3.0 }) &&
          rl::Vector3Equals(bounds.max, rl::Vector3 { 1.0, 2.0, 3.0 }), "GetModelBoundingBox");
    rl::UnloadModel(model);
}

fn main() {
    rl::SetTraceLogLevel(rl::LOG_WARNING);
    rl::InitWindow(320, 240, "rl smoke test");
    check(rl::IsWindowReady(), "InitWindow");
    check(rl::GetScreenWidth() == 320 && rl::GetScreenHeight() == 240, "GetScreenWidth/Height");

    strings();
    collisions();
    colors();
    images();
    files();
    random();
    raymath();
    rendering();
    models();

    var camera = rl::Camera3D {
        position: rl::Vector3 { 4.0, 4.0, 4.0 }, target: rl::Vector3 { 0.0, 0.0, 0.0 },
        up: rl::Vector3 { 0.0, 1.0, 0.0 }, fovy: 45.0, projection: rl::CAMERA_PERSPECTIVE
    };
    let center = rl::GetWorldToScreen(rl::Vector3 { 0.0, 0.0, 0.0 }, camera);
    check(near(center.x, 160.0) && near(center.y, 120.0), "GetWorldToScreen");
    // Moves the camera 1 unit forward, through the reference.
    rl::UpdateCameraPro(camera, rl::Vector3 { 1.0, 0.0, 0.0 }, rl::Vector3 { 0.0, 0.0, 0.0 }, 0.0);
    check(rl::Vector3Distance(camera.position, rl::Vector3 { 4.0, 4.0, 4.0 }) > 0.5, "UpdateCameraPro through Camera&");

    for frame in 3 {
        rl::BeginDrawing();
        rl::ClearBackground(rl::RAYWHITE);
        rl::BeginMode3D(camera);
        rl::DrawCube(rl::Vector3 { 0.0, 0.0, 0.0 }, 1.0, 1.0, 1.0, rl::RED);
        rl::DrawGrid(10, 1.0);
        rl::EndMode3D();
        rl::DrawText(str("frame ", frame), 10, 10, 20, rl::DARKGRAY);
        rl::EndDrawing();
    }

    rl::CloseWindow();
    print(checks - failures, " of ", checks, " checks passed");
    if failures > 0 { abort("smoke test failed"); }
}
