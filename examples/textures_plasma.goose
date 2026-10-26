// A texture whose pixels Goose computes every frame: an array of rl::Color
// handed to rl::UpdateTexture as a slice.
import rl from "..";

fn main() {
    let width: i32 = 320;
    let height: i32 = 180;
    let scale: f32 = 2.5;
    rl::InitWindow(800, 450, "raylib [textures] example - plasma");

    let image = rl::GenImageColor(width, height, rl::BLACK);
    let texture = rl::LoadTextureFromImage(image);
    rl::UnloadImage(image);

    var pixels: rl::Color[>..] = [];
    for i in width*height { pixels.push(rl::BLACK); }

    rl::SetTargetFPS(60);

    while !rl::WindowShouldClose() {
        let t = rl::GetTime() as f32;
        for y in height {
            for x in width {
                let fx = x as f32;
                let fy = y as f32;
                let v = sin(fx*0.06 + t) + sin(fy*0.05 - t*1.3) + sin((fx + fy)*0.03 + t*0.7);
                let hue = rl::Wrap(v*60.0 + t*40.0, 0.0, 360.0);
                pixels[y*width + x] = rl::ColorFromHSV(hue, 0.7, 0.95);
            }
        }
        rl::UpdateTexture(texture, pixels);

        rl::BeginDrawing();
        rl::ClearBackground(rl::BLACK);
        rl::DrawTextureEx(texture, rl::Vector2 { 0.0, 0.0 }, 0.0, scale, rl::WHITE);
        rl::DrawRectangle(10, 10, 250, 30, rl::Fade(rl::BLACK, 0.6));
        rl::DrawFPS(20, 15);
        rl::EndDrawing();
    }

    rl::UnloadTexture(texture);
    rl::CloseWindow();
}
