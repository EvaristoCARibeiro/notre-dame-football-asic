/*
 * Copyright (c) 2025 Uri Shaked
 * SPDX-License-Identifier: Apache-2.0
 *
 * Simple one-player pong: move the paddle with Up/Down on the SNES controller.
 * The ball bounces off the white field outline and off the paddle.
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
  localparam [5:0] BLACK       = {2'b00, 2'b00, 2'b00};
  localparam [5:0] WHITE       = {2'b11, 2'b11, 2'b11};
  localparam [5:0] DARK_GREEN  = {2'b00, 2'b01, 2'b00};
  localparam [5:0] LIGHT_GREEN = {2'b01, 2'b10, 2'b01};
  localparam [5:0] BROWN       = {2'b10, 2'b01, 2'b00};
  localparam [5:0] GOLD        = {2'b11, 2'b10, 2'b00};
  localparam [5:0] NAVY        = {2'b00, 2'b00, 2'b01};

  // Game settings (all sizes in pixels, speeds in pixels per frame)
  localparam [9:0] BORDER       = 4;    // white outline around the field
  localparam [9:0] PAD_X        = 107;  // pad left edge: x = 107..110, centered on the goal line
  localparam [9:0] PAD_W        = 4;    // pad thickness
  localparam [9:0] PAD_H        = 64;   // paddle height
  localparam [9:0] PAD_SPEED    = 4;
  localparam [9:0] BALL_W       = 30;   // football: 15 x 7 sprite drawn at 2x
  localparam [9:0] BALL_H       = 14;
  localparam [9:0] BALL_SPEED   = 8;    // same speed in x and y
  localparam [9:0] PAD_START_Y  = 208;  // (480 - 64) / 2
  localparam [9:0] BALL_START_X = 303;  // about (640 - 30) / 2; lands exactly on the pad face
  localparam [9:0] BALL_START_Y = 233;  // (480 - 14) / 2

  // Game state
  reg [9:0] pad_y;       // paddle top edge
  reg [9:0] ball_x;      // ball left edge
  reg [9:0] ball_y;      // ball top edge
  reg       ball_right;  // 1 = moving right, 0 = moving left
  reg       ball_down;   // 1 = moving down,  0 = moving up

  // Update the game once per frame, just after the last visible line
  wire frame_tick = (pix_x == 0) && (pix_y == 480);

  // Is the ball level with the paddle?
  wire ball_on_pad = (ball_y + BALL_H > pad_y) && (ball_y < pad_y + PAD_H);

  always @(posedge clk) begin
    if (~rst_n) begin
      pad_y      <= PAD_START_Y;
      ball_x     <= BALL_START_X;
      ball_y     <= BALL_START_Y;
      ball_right <= 1;
      ball_down  <= 1;
    end else if (frame_tick) begin

      // Paddle: move while Up/Down is held, stop at the outline
      if (inp_up && pad_y >= BORDER + PAD_SPEED)
        pad_y <= pad_y - PAD_SPEED;
      else if (inp_down && pad_y + PAD_H + PAD_SPEED <= 480 - BORDER)
        pad_y <= pad_y + PAD_SPEED;

      // Ball, horizontal: turn around at the right outline or at the paddle
      if (ball_right) begin
        if (ball_x + BALL_W + BALL_SPEED > 640 - BORDER)
          ball_right <= 0;                  // bounce off the right outline
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

      // Ball, vertical: turn around at the top and bottom outline
      if (ball_down) begin
        if (ball_y + BALL_H + BALL_SPEED > 480 - BORDER)
          ball_down <= 0;
        else
          ball_y <= ball_y + BALL_SPEED;
      end else begin
        if (ball_y < BORDER + BALL_SPEED)
          ball_down <= 1;
        else
          ball_y <= ball_y - BALL_SPEED;
      end
    end
  end

  // What is under the beam right now?
  wire pad_pixel  = (pix_x >= PAD_X)  && (pix_x < PAD_X + PAD_W) &&
                    (pix_y >= pad_y)  && (pix_y < pad_y + PAD_H);
  // Lineman holding the pad: 9 x 12 sprite drawn at 4x size (36 x 48) just left
  // of the pad and centered on it, so he moves with the pad.
  //
  //   ...NNN...    G = gold helmet
  //   ..NNNNBB.    N = navy shoulders
  //   ..NNNNBBB    B = brown arms and face
  //   .GGGGG..B    W = white gloves and face mask
  //   GGGGGBW.W    . = see-through
  //   GGGGGBW..
  //   GGGGGBW..    The pad is the plain black bar on the
  //   GGGGGBW.W    right; he faces right, toward the ball.
  //   .GGGGG..B
  //   ..NNNNBBB
  //   ..NNNNBB.
  //   ...NNN...
  //
  localparam [9:0] LM_X = PAD_X - 36;      // lineman left edge
  wire in_lm_box = (pix_x >= LM_X) && (pix_x < PAD_X) &&
                   (pix_y >= pad_y + 8) && (pix_y < pad_y + 56);
  wire [9:0] lm_dx  = pix_x - LM_X;        // position inside the lineman box
  wire [9:0] lm_dy  = pix_y - pad_y - 8;
  wire [3:0] lm_col = lm_dx[5:2];          // divide by 4 for the 4x size
  wire [3:0] lm_row = lm_dy[5:2];

  reg [8:0] lm_gold, lm_navy, lm_brown, lm_white;
  always @(*) begin  // gold helmet
    case (lm_row)
      4'd0:    lm_gold = 9'b000000000;
      4'd1:    lm_gold = 9'b000000000;
      4'd2:    lm_gold = 9'b000000000;
      4'd3:    lm_gold = 9'b011111000;
      4'd4:    lm_gold = 9'b111110000;
      4'd5:    lm_gold = 9'b111110000;
      4'd6:    lm_gold = 9'b111110000;
      4'd7:    lm_gold = 9'b111110000;
      4'd8:    lm_gold = 9'b011111000;
      4'd9:    lm_gold = 9'b000000000;
      4'd10:   lm_gold = 9'b000000000;
      4'd11:   lm_gold = 9'b000000000;
      default: lm_gold = 9'b000000000;
    endcase
  end

  always @(*) begin  // navy shoulders
    case (lm_row)
      4'd0:    lm_navy = 9'b000111000;
      4'd1:    lm_navy = 9'b001111000;
      4'd2:    lm_navy = 9'b001111000;
      4'd3:    lm_navy = 9'b000000000;
      4'd4:    lm_navy = 9'b000000000;
      4'd5:    lm_navy = 9'b000000000;
      4'd6:    lm_navy = 9'b000000000;
      4'd7:    lm_navy = 9'b000000000;
      4'd8:    lm_navy = 9'b000000000;
      4'd9:    lm_navy = 9'b001111000;
      4'd10:   lm_navy = 9'b001111000;
      4'd11:   lm_navy = 9'b000111000;
      default: lm_navy = 9'b000000000;
    endcase
  end

  always @(*) begin  // brown arms and face
    case (lm_row)
      4'd0:    lm_brown = 9'b000000000;
      4'd1:    lm_brown = 9'b000000110;
      4'd2:    lm_brown = 9'b000000111;
      4'd3:    lm_brown = 9'b000000001;
      4'd4:    lm_brown = 9'b000001000;
      4'd5:    lm_brown = 9'b000001000;
      4'd6:    lm_brown = 9'b000001000;
      4'd7:    lm_brown = 9'b000001000;
      4'd8:    lm_brown = 9'b000000001;
      4'd9:    lm_brown = 9'b000000111;
      4'd10:   lm_brown = 9'b000000110;
      4'd11:   lm_brown = 9'b000000000;
      default: lm_brown = 9'b000000000;
    endcase
  end

  always @(*) begin  // white gloves and face mask
    case (lm_row)
      4'd0:    lm_white = 9'b000000000;
      4'd1:    lm_white = 9'b000000000;
      4'd2:    lm_white = 9'b000000000;
      4'd3:    lm_white = 9'b000000000;
      4'd4:    lm_white = 9'b000000101;
      4'd5:    lm_white = 9'b000000100;
      4'd6:    lm_white = 9'b000000100;
      4'd7:    lm_white = 9'b000000101;
      4'd8:    lm_white = 9'b000000000;
      4'd9:    lm_white = 9'b000000000;
      4'd10:   lm_white = 9'b000000000;
      4'd11:   lm_white = 9'b000000000;
      default: lm_white = 9'b000000000;
    endcase
  end

  wire [3:0] lm_bit      = 4'd8 - lm_col;  // bit 8 is the leftmost column
  wire       lm_is_gold  = in_lm_box && lm_gold[lm_bit];
  wire       lm_is_navy  = in_lm_box && lm_navy[lm_bit];
  wire       lm_is_brown = in_lm_box && lm_brown[lm_bit];
  wire       lm_is_white = in_lm_box && lm_white[lm_bit];
  wire       lm_pixel    = lm_is_gold || lm_is_navy || lm_is_brown || lm_is_white;
  wire [5:0] lm_color    = lm_is_gold  ? GOLD :
                           lm_is_navy  ? NAVY :
                           lm_is_brown ? BROWN : WHITE;

  wire in_ball_box = (pix_x >= ball_x) && (pix_x < ball_x + BALL_W) &&
                     (pix_y >= ball_y) && (pix_y < ball_y + BALL_H);

  // Football sprite: 15 x 7 pixels, drawn at 2x size (30 x 14).
  //
  //   ....BBBBBBB....    B = brown leather
  //   ..BWBBBBBBBWB..    W = white laces
  //   .BBWBWBWBWBWBB.    . = see-through
  //   BBBWWWWWWWWWBBB
  //   .BBWBWBWBWBWBB.
  //   ..BWBBBBBBBWB..
  //   ....BBBBBBB....
  //
  // Stored as one 15-bit mask per color and row (1 = pixel has that color).
  wire [9:0] ball_dx = pix_x - ball_x;   // position inside the ball box
  wire [9:0] ball_dy = pix_y - ball_y;
  wire [3:0] fb_col  = ball_dx[4:1];     // divide by 2 for the 2x size
  wire [3:0] fb_row  = ball_dy[4:1];

  reg [14:0] fb_brown, fb_white;
  always @(*) begin  // brown leather
    case (fb_row)
      4'd0:    fb_brown = 15'b000011111110000;
      4'd1:    fb_brown = 15'b001011111110100;
      4'd2:    fb_brown = 15'b011010101010110;
      4'd3:    fb_brown = 15'b111000000000111;
      4'd4:    fb_brown = 15'b011010101010110;
      4'd5:    fb_brown = 15'b001011111110100;
      4'd6:    fb_brown = 15'b000011111110000;
      default: fb_brown = 15'b000000000000000;
    endcase
  end

  always @(*) begin  // white laces
    case (fb_row)
      4'd0:    fb_white = 15'b000000000000000;
      4'd1:    fb_white = 15'b000100000001000;
      4'd2:    fb_white = 15'b000101010101000;
      4'd3:    fb_white = 15'b000111111111000;
      4'd4:    fb_white = 15'b000101010101000;
      4'd5:    fb_white = 15'b000100000001000;
      4'd6:    fb_white = 15'b000000000000000;
      default: fb_white = 15'b000000000000000;
    endcase
  end

  wire [3:0] fb_bit     = 4'd14 - fb_col;  // bit 14 is the leftmost column
  wire       ball_white = in_ball_box && fb_white[fb_bit];
  wire       ball_brown = in_ball_box && fb_brown[fb_bit];
  wire       ball_pixel = ball_white || ball_brown;
  wire [5:0] ball_color = ball_white ? WHITE : BROWN;

  // ---------------- Football field background ----------------
  // End zone on the left, then the field from the goal line (0) to the 50,
  // with a white yard line every 5 yards and alternating green 5-yard bands.
  localparam GOAL_X = 108;  // goal line x position (end zone is x < 108)
  localparam BAND_W = 53;   // 5 yards in pixels: 108 + 10 * 53 = 638
  localparam LINE_W = 2;    // yard line thickness

  integer k;
  reg yard_line;   // on a white yard line (0, 5, 10, ... 50)
  reg light_band;  // in a light green band (flips at every yard line)
  always @(*) begin
    yard_line  = 0;
    light_band = 0;
    for (k = 0; k <= 10; k = k + 1) begin
      if (pix_x >= GOAL_X + k * BAND_W) begin
        light_band = ~light_band;
        if (pix_x < GOAL_X + k * BAND_W + LINE_W)
          yard_line = 1;
      end
    end
  end

  // End zone stripes: 9 diagonal lines spread over the whole height.
  // Pixels with the same value of 21*y + 19*x lie on one line at atan(19/21) = 42 degrees.
  // A stripe every 1024 steps puts them 1024 / 21 = 48.8 px apart, and each stripe is
  // 64 steps (about 2 px) thick. Starting the first stripe at STRIPE_V0 centers all 9
  // between the top and bottom outline; the x range leaves a margin on both sides.
  localparam        STRIPE_X0 = 16;    // stripes run from x = 16 ...
  localparam        STRIPE_X1 = 95;    // ... to x = 95
  localparam [13:0] STRIPE_V0 = 1956;  // where the first (top) stripe starts
  wire [13:0] stripe_v = {4'b0, pix_y} * 14'd21 + {4'b0, pix_x} * 14'd19;
  wire [13:0] stripe_n = stripe_v - STRIPE_V0;  // steps past the start of the first stripe
  wire        stripe   = (pix_x >= STRIPE_X0) && (pix_x <= STRIPE_X1) &&
                         (stripe_n < 9 * 1024) && (stripe_n[9:6] == 4'b0000);

  // White outline around the whole field
  wire outline = (pix_x < BORDER) || (pix_x >= 640 - BORDER) ||
                 (pix_y < BORDER) || (pix_y >= 480 - BORDER);

  // Small white ring on the 35 yard line, halfway down the field.
  // The 35 is the 7th yard line past the goal line: x = 108 + 7 * 53 = 479 (2 px wide),
  // so a 12 x 12 ring from x = 474 is centered on it. 1 = white.
  localparam RING_X = GOAL_X + 7 * BAND_W - 5;  // = 474
  localparam RING_Y = 234;                       // centered between y = 239 and 240
  wire in_ring_box = (pix_x >= RING_X) && (pix_x < RING_X + 12) &&
                     (pix_y >= RING_Y) && (pix_y < RING_Y + 12);
  wire [9:0] ring_dx = pix_x - RING_X;
  wire [9:0] ring_dy = pix_y - RING_Y;

  reg [11:0] ring_row;
  always @(*) begin
    case (ring_dy[3:0])
      4'd0:    ring_row = 12'b000011110000;
      4'd1:    ring_row = 12'b001111111100;
      4'd2:    ring_row = 12'b011100001110;
      4'd3:    ring_row = 12'b011000000110;
      4'd4:    ring_row = 12'b110000000011;
      4'd5:    ring_row = 12'b110000000011;
      4'd6:    ring_row = 12'b110000000011;
      4'd7:    ring_row = 12'b110000000011;
      4'd8:    ring_row = 12'b011000000110;
      4'd9:    ring_row = 12'b011100001110;
      4'd10:   ring_row = 12'b001111111100;
      4'd11:   ring_row = 12'b000011110000;
      default: ring_row = 12'b000000000000;
    endcase
  end
  wire ring = in_ring_box && ring_row[4'd11 - ring_dx[3:0]];  // bit 11 is the leftmost column

  // Yard ticks: a short 1 px mark every yard, along the top and bottom outline and in
  // two rows across the middle (3/8 and 5/8 of the way down, like real hash marks).
  // They are vertical lines every yard that only show inside those 4 short bands.
  // There are 5 yards per 53 px and 386 / 4096 is about 5 / 53, so (x - 108) * 386
  // grows by 4096 every yard: its low 12 bits wrap around once per yard, and the
  // pixel where they have just wrapped (value below 386) gets the tick.
  localparam        TICK_LEN = 6;       // tick length in pixels
  localparam        HASH1_Y  = 178;     // upper middle row: y = 178..183
  localparam        HASH2_Y  = 296;     // lower middle row: y = 296..301
  localparam [11:0] TICK_X0  = GOAL_X;  // count yards from the goal line
  wire [11:0] tick_dx   = {2'b0, pix_x} - TICK_X0;
  wire [11:0] yard_frac = tick_dx * 12'd386;   // keeps only the low 12 bits
  wire        tick_x    = (yard_frac < 12'd386);
  wire        tick_y    = (pix_y < BORDER + TICK_LEN) ||                   // top edge
                          (pix_y >= 480 - BORDER - TICK_LEN) ||            // bottom edge
                          (pix_y >= HASH1_Y && pix_y < HASH1_Y + TICK_LEN) ||
                          (pix_y >= HASH2_Y && pix_y < HASH2_Y + TICK_LEN);
  wire        tick      = tick_x && tick_y;

  // RGB output logic
  always @(posedge clk) begin
    if (~rst_n) begin
      R <= 0;
      G <= 0;
      B <= 0;
    end else begin
      if (video_active) begin
        if (pad_pixel)
          {R, G, B} <= BLACK;                              // the pad on top
        else if (lm_pixel)
          {R, G, B} <= lm_color;                           // the lineman holding it
        else if (ball_pixel)
          {R, G, B} <= ball_color;                         // then the football
        else if (outline)
          {R, G, B} <= WHITE;                              // field outline
        else if (pix_x < GOAL_X)
          {R, G, B} <= stripe ? WHITE : DARK_GREEN;        // end zone
        else if (yard_line || ring || tick)
          {R, G, B} <= WHITE;                              // yard lines, ring and ticks
        else
          {R, G, B} <= light_band ? LIGHT_GREEN : DARK_GREEN;
      end else begin
        {R, G, B} <= BLACK;
      end
    end
  end

endmodule