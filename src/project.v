/*
 * Copyright (c) 2025 Uri Shaked
 * SPDX-License-Identifier: Apache-2.0
 *
 * Simple one-player pong: move the paddle with Up/Down on the SNES controller.
 * The ball bounces off the top, bottom and right edges and off the paddle.
 * If the paddle misses, the ball is served again from the middle.
 */

`default_nettype none

module tt_um_evaristocaribeiro_pongasic (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // always 1 when the design is powered, so you can ignore it
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);

  // Unused outputs assigned to 0.
  assign uio_out = 0;
  assign uio_oe  = 0;

  // VGA signals
  wire hsync;
  wire vsync;
  reg [1:0] R;
  reg [1:0] G;
  reg [1:0] B;
  wire video_active;
  wire [9:0] pix_x;
  wire [9:0] pix_y;

  // Tiny VGA Pmod
  assign uo_out = {hsync, B[0], G[0], R[0], vsync, B[1], G[1], R[1]};

  hvsync_generator vga_sync_gen (
      .clk(clk),
      .reset(~rst_n),
      .hsync(hsync),
      .vsync(vsync),
      .display_on(video_active),
      .hpos(pix_x),
      .vpos(pix_y)
  );

  // Gamepad Pmod
  wire inp_b, inp_y, inp_select, inp_start, inp_up, inp_down, inp_left, inp_right, inp_a, inp_x, inp_l, inp_r;

  gamepad_pmod_single driver (
      // Inputs:
      .rst_n(rst_n),
      .clk(clk),
      .pmod_data(ui_in[6]),
      .pmod_clk(ui_in[5]),
      .pmod_latch(ui_in[4]),
      // Outputs:
      .b(inp_b),
      .y(inp_y),
      .select(inp_select),
      .start(inp_start),
      .up(inp_up),
      .down(inp_down),
      .left(inp_left),
      .right(inp_right),
      .a(inp_a),
      .x(inp_x),
      .l(inp_l),
      .r(inp_r)
  );

  // Suppress unused signals warning (buttons not used by the game yet)
  wire _unused_ok = &{ena, ui_in[7], ui_in[3:0], uio_in,
                      inp_b, inp_y, inp_select, inp_start, inp_left, inp_right,
                      inp_a, inp_x, inp_l, inp_r};

  // Colors
  localparam [5:0] BLACK = {2'b00, 2'b00, 2'b00};
  localparam [5:0] WHITE = {2'b11, 2'b11, 2'b11};

  // Game settings (all sizes in pixels, speeds in pixels per frame)
  localparam [9:0] PAD_X        = 16;   // paddle left edge
  localparam [9:0] PAD_W        = 8;    // paddle width
  localparam [9:0] PAD_H        = 64;   // paddle height
  localparam [9:0] PAD_SPEED    = 4;
  localparam [9:0] BALL_SIZE    = 8;
  localparam [9:0] BALL_SPEED   = 4;    // same speed in x and y
  localparam [9:0] PAD_START_Y  = 208;  // (480 - 64) / 2
  localparam [9:0] BALL_START_X = 316;  // (640 - 8) / 2
  localparam [9:0] BALL_START_Y = 236;  // (480 - 8) / 2

  // Game state
  reg [9:0] pad_y;       // paddle top edge
  reg [9:0] ball_x;      // ball left edge
  reg [9:0] ball_y;      // ball top edge
  reg       ball_right;  // 1 = moving right, 0 = moving left
  reg       ball_down;   // 1 = moving down,  0 = moving up

  // Update the game once per frame, just after the last visible line
  wire frame_tick = (pix_x == 0) && (pix_y == 480);

  // Is the ball level with the paddle?
  wire ball_on_pad = (ball_y + BALL_SIZE > pad_y) && (ball_y < pad_y + PAD_H);

  always @(posedge clk) begin
    if (~rst_n) begin
      pad_y      <= PAD_START_Y;
      ball_x     <= BALL_START_X;
      ball_y     <= BALL_START_Y;
      ball_right <= 1;
      ball_down  <= 1;
    end else if (frame_tick) begin

      // Paddle: move while Up/Down is held, stop at the screen edges
      if (inp_up && pad_y >= PAD_SPEED)
        pad_y <= pad_y - PAD_SPEED;
      else if (inp_down && pad_y + PAD_H + PAD_SPEED <= 480)
        pad_y <= pad_y + PAD_SPEED;

      // Ball, horizontal: turn around at the right edge or at the paddle
      if (ball_right) begin
        if (ball_x + BALL_SIZE + BALL_SPEED > 640)
          ball_right <= 0;                  // bounce off the right edge
        else
          ball_x <= ball_x + BALL_SPEED;
      end else begin
        if (ball_x < PAD_X + PAD_W + BALL_SPEED) begin
          ball_right <= 1;                  // reached the paddle's column
          if (!ball_on_pad)
            ball_x <= BALL_START_X;         // missed: serve again from the middle
        end else
          ball_x <= ball_x - BALL_SPEED;
      end

      // Ball, vertical: turn around at the top and bottom edges
      if (ball_down) begin
        if (ball_y + BALL_SIZE + BALL_SPEED > 480)
          ball_down <= 0;
        else
          ball_y <= ball_y + BALL_SPEED;
      end else begin
        if (ball_y < BALL_SPEED)
          ball_down <= 1;
        else
          ball_y <= ball_y - BALL_SPEED;
      end
    end
  end

  // What is under the beam right now?
  wire pad_pixel  = (pix_x >= PAD_X)  && (pix_x < PAD_X + PAD_W) &&
                    (pix_y >= pad_y)  && (pix_y < pad_y + PAD_H);
  wire ball_pixel = (pix_x >= ball_x) && (pix_x < ball_x + BALL_SIZE) &&
                    (pix_y >= ball_y) && (pix_y < ball_y + BALL_SIZE);

  // RGB output logic
  always @(posedge clk) begin
    if (~rst_n) begin
      R <= 0;
      G <= 0;
      B <= 0;
    end else begin
      if (video_active) begin
        {R, G, B} <= (pad_pixel || ball_pixel) ? WHITE : BLACK;
      end else begin
        {R, G, B} <= 0;
      end
    end
  end

endmodule
