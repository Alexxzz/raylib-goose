// raylib's shapes_bouncing_ball, in Goose: input, raymath, and str() for
// the formatting C code does with TextFormat.
import rl from "..";

fn main() {
    rl::SetConfigFlags(rl::FLAG_MSAA_4X_HINT);
    rl::InitWindow(800, 450, "raylib [shapes] example - bouncing ball");

    var ball_position = rl::Vector2 { rl::GetScreenWidth()/2.0, rl::GetScreenHeight()/2.0 };
    var ball_speed = rl::Vector2 { 5.0, 4.0 };
    let ball_radius: f32 = 20.0;
    var pause = false;
    var frames_counter = 0;

    rl::SetTargetFPS(60);

    while !rl::WindowShouldClose() {
        if rl::IsKeyPressed(rl::KEY_SPACE) { pause = !pause; }
        if rl::IsMouseButtonPressed(rl::MOUSE_BUTTON_LEFT) { ball_position = rl::GetMousePosition(); }

        if !pause {
            ball_position = rl::Vector2Add(ball_position, ball_speed);

            // Check walls collision for bouncing
            if ball_position.x >= rl::GetScreenWidth() - ball_radius || ball_position.x <= ball_radius {
                ball_speed.x *= -1.0;
            }
            if ball_position.y >= rl::GetScreenHeight() - ball_radius || ball_position.y <= ball_radius {
                ball_speed.y *= -1.0;
            }
        } else {
            frames_counter++;
        }

        rl::BeginDrawing();
        rl::ClearBackground(rl::RAYWHITE);

        rl::DrawCircleV(ball_position, ball_radius, rl::MAROON);
        rl::DrawText("PRESS SPACE to PAUSE BALL MOVEMENT, CLICK to MOVE IT", 10, rl::GetScreenHeight() - 25, 20, rl::LIGHTGRAY);
        rl::DrawText(str("speed ", rl::Vector2Length(ball_speed)), 10, 40, 20, rl::DARKGRAY);

        // On pause, we draw a blinking message
        if pause && (frames_counter/30) % 2 != 0 { rl::DrawText("PAUSED", 350, 200, 30, rl::GRAY); }

        rl::DrawFPS(10, 10);
        rl::EndDrawing();
    }

    rl::CloseWindow();
}
