## How it works

This project is a simple one-player Pong game displayed on a VGA monitor at 640×480, 60 Hz.

<img width="1374" height="1392" alt="image" src="https://github.com/user-attachments/assets/6e9021de-6d96-4f97-b87f-899521d250ba" />

A white paddle sits near the left edge of the screen and a small white ball moves diagonally across the playfield. The ball bounces off the top, bottom and right edges of the screen and off the paddle. If the paddle misses the ball, the ball is served again from the middle of the screen, heading right.

The design has no frame buffer. A sync generator produces the VGA timing and the current pixel position, and each pixel's color is computed on the fly by checking whether that position falls inside the paddle or ball rectangle.

The game state is just the paddle's vertical position, the ball's position and the ball's direction. It is updated once per frame, at the start of vertical blanking, so objects never tear on screen.

Controller input comes from the Gamepad Pmod, whose microcontroller reads the SNES controller and sends the button states to the chip over a 3-wire serial interface (data, clock, latch). The chip shifts in the 12 button bits and latches them, and the game uses the Up and Down buttons to move the paddle.

## How to test

1. Plug the Tiny VGA Pmod into the dedicated outputs (`uo_out`) and connect a VGA monitor.
2. Plug the Gamepad Pmod into the dedicated inputs (`ui_in`); it uses `ui_in[6]` (data), `ui_in[5]` (clock) and `ui_in[4]` (latch). Connect an SNES controller to it.
3. Set the project clock to 25.175 MHz (25 MHz also works on most monitors) and reset the design.
4. The paddle appears at the left, centered vertically, and the ball starts in the middle of the screen moving toward the right.
5. Hold Up or Down on the controller to move the paddle and keep the ball from getting past it. The paddle stops at the top and bottom edges of the screen.

## External hardware

- Tiny VGA Pmod, connected to the dedicated outputs
- Gamepad Pmod, connected to the dedicated inputs
- SNES controller, connected to the Gamepad Pmod
- VGA monitor
