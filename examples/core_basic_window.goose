// raylib's core_basic_window, in Goose.
import rl from "..";

fn main() {
    let screen_width: i32 = 800;
    let screen_height: i32 = 450;

    rl::InitWindow(screen_width, screen_height, "raylib [core] example - basic window");
    rl::SetTargetFPS(60);

    while !rl::WindowShouldClose() {
        rl::BeginDrawing();
        rl::ClearBackground(rl::RAYWHITE);
        rl::DrawText("Congrats! You created your first window!", 190, 200, 20, rl::LIGHTGRAY);
        rl::EndDrawing();
    }

    rl::CloseWindow();
}
