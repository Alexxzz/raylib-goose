// A fragment shader with uniforms: LoadShaderFromMemory("", code) keeps
// raylib's default vertex shader (C passes NULL), and SetShaderValue takes
// the uniform's value by reference.
import rl from "..";

let FRAGMENT = """
#version 330
in vec2 fragTexCoord;
in vec4 fragColor;
out vec4 finalColor;
uniform float time;
uniform vec2 resolution;
void main() {
    vec2 uv = gl_FragCoord.xy/resolution;
    vec3 col = 0.5 + 0.5*cos(time + uv.xyx*3.0 + vec3(0.0, 2.0, 4.0));
    finalColor = vec4(col, 1.0);
}
""";

fn main() {
    rl::InitWindow(800, 450, "raylib [shaders] example - uniforms");

    let shader = rl::LoadShaderFromMemory("", FRAGMENT);
    let time_loc = rl::GetShaderLocation(shader, "time");
    let resolution_loc = rl::GetShaderLocation(shader, "resolution");
    let resolution = rl::Vector2 { rl::GetScreenWidth(), rl::GetScreenHeight() };
    rl::SetShaderValue(shader, resolution_loc, resolution, rl::SHADER_UNIFORM_VEC2);

    rl::SetTargetFPS(60);

    while !rl::WindowShouldClose() {
        let time = rl::GetTime() as f32;
        rl::SetShaderValue(shader, time_loc, time, rl::SHADER_UNIFORM_FLOAT);

        rl::BeginDrawing();
        rl::ClearBackground(rl::RAYWHITE);
        rl::BeginShaderMode(shader);
        rl::DrawRectangle(0, 0, rl::GetScreenWidth(), rl::GetScreenHeight(), rl::WHITE);
        rl::EndShaderMode();
        rl::DrawText("A fragment shader, its uniforms set from Goose", 10, 40, 20, rl::WHITE);
        rl::DrawFPS(10, 10);
        rl::EndDrawing();
    }

    rl::UnloadShader(shader);
    rl::CloseWindow();
}
