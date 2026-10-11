## How it works

Notre Dame Football ASIC is a single-player Pong game with a Notre Dame football theme, drawn on a 640x480 VGA screen. You play a lineman holding a blocking pad on the goal line, and your goal is to keep the football from getting past you into the end zone.

The screen shows half of a football field, seen from above:

- On the left, the end zone with diagonal stripes and a yellow goal post. Since the field is seen from straight above, the uprights only show as round caps on the ends of the crossbar.
- The field from the goal line to the 50, with a white yard line every 5 yards, alternating light and dark green 5-yard bands, and short tick marks for every yard along the sidelines and the hash marks.
- The left half of the Notre Dame monogram at midfield, in Notre Dame blue and gold. The 50 yard line is the right edge of the screen, so the logo looks like it continues off screen, like in the middle of the real stadium.
- A white outline around the whole field.

The lineman (with a gold helmet) holds a black pad on the goal line and moves up and down with the controls. The football bounces off the outline at the top, bottom and right side of the field, and off the pad. The game is updated once per frame (60 times per second):

- The ball starts at a speed of 5 pixels per frame, and every time it hits the pad it gets 1 faster, up to 9.
- Where the pad is when the ball hits it changes the ball's angle, so its path is less predictable. With the pad in the middle of the screen the ball leaves at 45 degrees. The higher the pad, the flatter and faster sideways the ball goes; the lower the pad, the steeper. The ball's speed is split between x and y by `round(speed * (pad_y - 208) / 500)` pixels, where `pad_y` is the top of the pad and 208 is the pad in the middle of the screen.
- If the ball gets past the pad, it is served again from the middle of the field at speed 5.

## How to test

Connect the TinyVGA Pmod to the output pins and a VGA monitor, and a SNES compatible controller to the Gamepad Pmod. After reset, the ball is served from the middle of the field right away: move the lineman up and down with the D-pad to block it.

| Controller | Lineman   |
|------------|-----------|
| D-pad Up   | Move up   |
| D-pad Down | Move down |

## External hardware

- [TinyVGA Pmod](https://github.com/mole99/tiny-vga) on the output pins
- [Gamepad Pmod](https://github.com/psychogenic/gamepad-pmod) on `ui_in[6:4]`, with a SNES compatible controller
