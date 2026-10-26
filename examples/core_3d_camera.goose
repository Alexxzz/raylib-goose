// A 3D scene with an orbital camera: rl::UpdateCamera takes the camera by
// reference and moves it, and GetWorldToScreen places a label over the cube.
import rl from "..";

fn main() {
    let screen_width: i32 = 800;
    let screen_height: i32 = 450;
    rl::InitWindow(screen_width, screen_height, "raylib [core] example - 3d camera");

    var camera = rl::Camera3D {
        position: rl::Vector3 { 10.0, 10.0, 10.0 },
        target: rl::Vector3 { 0.0, 0.0, 0.0 },
        up: rl::Vector3 { 0.0, 1.0, 0.0 },
        fovy: 45.0,
        projection: rl::CAMERA_PERSPECTIVE
    };
    let cube_position = rl::Vector3 { 0.0, 1.0, 0.0 };

    rl::SetTargetFPS(60);

    while !rl::WindowShouldClose() {
        rl::UpdateCamera(camera, rl::CAMERA_ORBITAL);

        // The point above the cube, in screen space
        let label = rl::GetWorldToScreen(rl::Vector3Add(cube_position, rl::Vector3 { 0.0, 1.8, 0.0 }), camera);
        let text = "Goose cube";
        let text_width = rl::MeasureText(text, 20);

        rl::BeginDrawing();
        rl::ClearBackground(rl::RAYWHITE);

        rl::BeginMode3D(camera);
        rl::DrawCube(cube_position, 2.0, 2.0, 2.0, rl::RED);
        rl::DrawCubeWires(cube_position, 2.0, 2.0, 2.0, rl::MAROON);
        for i in 8 {
            let angle = i*rl::PI/4.0;
            let p = rl::Vector3RotateByAxisAngle(rl::Vector3 { 4.0, 0.5, 0.0 }, rl::Vector3 { 0.0, 1.0, 0.0 }, angle);
            rl::DrawSphere(p, 0.5, rl::ColorFromHSV(i*45.0, 0.8, 0.9));
        }
        rl::DrawGrid(10, 1.0);
        rl::EndMode3D();

        rl::DrawText(text, label.x as! i32 - text_width/2, label.y as! i32, 20, rl::BLACK);
        rl::DrawText("Orbital camera: the scene turns by itself", 10, 40, 20, rl::DARKGRAY);
        rl::DrawFPS(10, 10);
        rl::EndDrawing();
    }

    rl::CloseWindow();
}
