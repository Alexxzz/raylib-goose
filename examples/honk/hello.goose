// The smallest honk program: one scene, input actions, a camera and text.
//
//   goose run examples/honk/hello.goose
import rl from "../..";
import rl.honk;

let LEFT = 0;
let RIGHT = 1;
let UP = 2;
let DOWN = 3;

fn main() {
    honk::run(honk::Config { title: "honk - hello", width: 800, height: 450 }) { eng =>
        honk::bind_key(eng, LEFT, rl::KEY_LEFT);
        honk::bind_key(eng, RIGHT, rl::KEY_RIGHT);
        honk::bind_key(eng, UP, rl::KEY_UP);
        honk::bind_key(eng, DOWN, rl::KEY_DOWN);

        var pos = rl::Vector2 { 0.0, 0.0 };
        honk::frames(eng) { f =>
            pos = rl::Vector2Add(pos, rl::Vector2Scale(f.direction(LEFT, RIGHT, UP, DOWN), 240.0*f.dt));
            honk::follow(eng, pos, 6.0);

            // The world, through the camera.
            for i in 21 {
                let x = (i - 10)*80.0;
                f.line(rl::Vector2 { x, -800.0 }, rl::Vector2 { x, 800.0 }, 1.0, rl::DARKGRAY);
                f.line(rl::Vector2 { -800.0, x }, rl::Vector2 { 800.0, x }, 1.0, rl::DARKGRAY);
            }
            f.rect(pos, rl::Vector2 { 40.0, 40.0 }, f.time as f32*90.0, rl::GOLD);

            // The screen, over it.
            f.screen();
            f.text("Arrow keys move the square. F1 shows the debug overlay.", rl::Vector2 { 12.0, 12.0 }, 20.0, rl::RAYWHITE);
        };
    };
}
