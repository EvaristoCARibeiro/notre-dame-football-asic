/*
 * Copyright (c) 2025 Uri Shaked
 * SPDX-License-Identifier: Apache-2.0
 *
 * Simple one-player pong: move the paddle with Up/Down on the SNES controller.
 * The ball bounces off the white field outline and off the paddle.
 * If the paddle misses, the ball is served again from the middle.
 */

`default_nettype none

module tt_um_evaristocaribeiro_notredamefootballasic (
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
  wire _unused_ok = &{ena, ui_in[7], ui_in[3:2], uio_in,
                      inp_b, inp_y, inp_select, inp_start, inp_left, inp_right,
                      inp_a, inp_x, inp_l, inp_r};

  // Push buttons as a second way to play: ui_in[0] = up, ui_in[1] = down, active high
  // (button to VCC, pull-down resistor to GND). They are not synced to our clock, so pass
  // them through two flip-flops first. No debouncing is needed: the paddle only looks at
  // them once per frame (every 16.7 ms), so a bouncing contact costs at most one step.
  reg [1:0] btn_meta, btn_sync;
  always @(posedge clk) begin
    btn_meta <= ui_in[1:0];
    btn_sync <= btn_meta;
  end

  // Either the controller or the buttons move the paddle; both work at the same time
  wire move_up   = inp_up   || btn_sync[0];
  wire move_down = inp_down || btn_sync[1];

  // Colors
  localparam [5:0] BLACK       = {2'b00, 2'b00, 2'b00};
  localparam [5:0] WHITE       = {2'b11, 2'b11, 2'b11};
  localparam [5:0] DARK_GREEN  = {2'b00, 2'b01, 2'b00};
  localparam [5:0] LIGHT_GREEN = {2'b01, 2'b10, 2'b01};
  localparam [5:0] BROWN       = {2'b10, 2'b01, 2'b00};
  localparam [5:0] GOLD        = {2'b11, 2'b10, 2'b00};
  localparam [5:0] NAVY        = {2'b00, 2'b00, 2'b01};
  localparam [5:0] YELLOW      = {2'b11, 2'b11, 2'b00};
  localparam [5:0] GRAY        = {2'b10, 2'b10, 2'b10};
  localparam [5:0] ND_BLUE     = {2'b00, 2'b00, 2'b01};  // closest to #0C2340 (same as NAVY)
  localparam [5:0] ND_GOLD     = {2'b10, 2'b10, 2'b01};  // closest to #AE9142

  // Game settings (all sizes in pixels, speeds in pixels per frame)
  localparam [9:0] BORDER       = 4;    // white outline around the field
  localparam [9:0] PAD_X        = 107;  // pad left edge: x = 107..110, centered on the goal line
  localparam [9:0] PAD_W        = 4;    // pad thickness
  localparam [9:0] PAD_H        = 64;   // paddle height
  localparam [9:0] PAD_SPEED    = 6;
  localparam [9:0] BALL_W       = 30;   // football: 15 x 7 sprite drawn at 2x
  localparam [9:0] BALL_H       = 14;
  localparam [3:0] SPEED_START  = 5;    // ball speed after a serve ...
  localparam [3:0] SPEED_MAX    = 9;    // ... going up by 1 on every paddle hit, up to this
  localparam [9:0] PAD_START_Y  = 208;  // (480 - 64) / 2, also the "centered" paddle position
  localparam [9:0] BALL_START_X = 303;  // about (640 - 30) / 2
  localparam [9:0] BALL_START_Y = 233;  // (480 - 14) / 2

  // Game state
  reg [9:0] pad_y;       // paddle top edge
  reg [9:0] ball_x;      // ball left edge
  reg [9:0] ball_y;      // ball top edge
  reg       ball_right;  // 1 = moving right, 0 = moving left
  reg       ball_down;   // 1 = moving down,  0 = moving up
  reg [3:0] ball_speed;  // 5..9, goes up on every paddle hit
  reg [3:0] ball_vx;     // pixels per frame in x and y, set on every paddle hit
  reg [3:0] ball_vy;

  // Update the game once per frame, just after the last visible line
  wire frame_tick = (pix_x == 0) && (pix_y == 480);

  // Is the ball level with the paddle?
  wire ball_on_pad = (ball_y + BALL_H > pad_y) && (ball_y < pad_y + PAD_H);

  // New speeds after a paddle hit. The speed s goes up by 1 (up to 9), and the paddle's
  // distance from the middle tilts it between x and y by delta = s * (pad_y - 208) / 500:
  // paddle high -> flatter and faster in x, paddle low -> steeper. Since |pad_y - 208|
  // is at most 204, |delta| is at most 9 * 204 / 500 = 3.7. Rounding a product by 500
  // only needs it compared with 250, 750, 1250 and 1750, so there is no divider.
  wire [3:0]  hit_speed = (ball_speed < SPEED_MAX) ? ball_speed + 4'd1 : SPEED_MAX;
  wire        pad_high  = (pad_y < PAD_START_Y);
  wire [9:0]  pad_off   = pad_high ? PAD_START_Y - pad_y : pad_y - PAD_START_Y;  // 0..204
  wire [11:0] tilt_prod = hit_speed * pad_off[7:0];                             // 0..1836
  wire [3:0]  tilt      = (tilt_prod >= 12'd1750) ? 4'd4 :   // round(tilt_prod / 500)
                          (tilt_prod >= 12'd1250) ? 4'd3 :
                          (tilt_prod >= 12'd750)  ? 4'd2 :
                          (tilt_prod >= 12'd250)  ? 4'd1 : 4'd0;
  wire [3:0]  hit_vx    = pad_high ? hit_speed + tilt : hit_speed - tilt;  // 4..13
  wire [3:0]  hit_vy    = pad_high ? hit_speed - tilt : hit_speed + tilt;

  always @(posedge clk) begin
    if (~rst_n) begin
      pad_y      <= PAD_START_Y;
      ball_x     <= BALL_START_X;
      ball_y     <= BALL_START_Y;
      ball_right <= 1;
      ball_down  <= 1;
      ball_speed <= SPEED_START;
      ball_vx    <= SPEED_START;
      ball_vy    <= SPEED_START;
    end else if (frame_tick) begin

      // Paddle: move while Up/Down is held (controller or buttons), stop at the outline
      if (move_up && pad_y >= BORDER + PAD_SPEED)
        pad_y <= pad_y - PAD_SPEED;
      else if (move_down && pad_y + PAD_H + PAD_SPEED <= 480 - BORDER)
        pad_y <= pad_y + PAD_SPEED;

      // Ball, horizontal: turn around at the right outline or at the paddle.
      // A step that would go past them stops flush against them instead.
      if (ball_right) begin
        if (ball_x + BALL_W + ball_vx > 640 - BORDER) begin
          ball_x     <= 640 - BORDER - BALL_W;
          ball_right <= 0;                  // bounce off the right outline
        end else
          ball_x <= ball_x + ball_vx;
      end else begin
        if (ball_x < PAD_X + PAD_W + ball_vx) begin
          ball_right <= 1;                  // reached the paddle's column
          if (ball_on_pad) begin
            ball_x     <= PAD_X + PAD_W;    // hit: touch the pad face, speed up and tilt
            ball_speed <= hit_speed;
            ball_vx    <= hit_vx;
            ball_vy    <= hit_vy;
          end else begin
            ball_x     <= BALL_START_X;     // missed: serve again from the middle, slow
            ball_speed <= SPEED_START;
            ball_vx    <= SPEED_START;
            ball_vy    <= SPEED_START;
          end
        end else
          ball_x <= ball_x - ball_vx;
      end

      // Ball, vertical: turn around at the top and bottom outline
      if (ball_down) begin
        if (ball_y + BALL_H + ball_vy > 480 - BORDER) begin
          ball_y    <= 480 - BORDER - BALL_H;
          ball_down <= 0;
        end else
          ball_y <= ball_y + ball_vy;
      end else begin
        if (ball_y < BORDER + ball_vy) begin
          ball_y    <= BORDER;
          ball_down <= 1;
        end else
          ball_y <= ball_y - ball_vy;
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

  // Goal post seen straight from above, just inside the end line. From up here the
  // uprights are only round caps at the ends of the crossbar, so the low sun behind the
  // end line casts the post's full Y shape onto the end zone as a shadow.
  // The post is lit from the upper left: yellow on that side, gold on the other.
  localparam [9:0] POST_X  = 10;   // crossbar x = 10..12
  localparam [9:0] POST_Y0 = 180;  // crossbar y = 180..299, between the hash marks
  localparam [9:0] POST_Y1 = 300;
  localparam [9:0] STEM_Y  = 239;  // support post back to the end line: y = 239..240
  wire crossbar  = (pix_x >= POST_X) && (pix_x < POST_X + 3) &&
                   (pix_y >= POST_Y0) && (pix_y < POST_Y1);
  wire post_stem = (pix_x >= BORDER) && (pix_x < POST_X) &&
                   (pix_y >= STEM_Y) && (pix_y < STEM_Y + 2);

  // Upright caps: 5 x 4 rounded blobs at x = 9..13, y = 178..181 and y = 298..301.
  //   .YYG.    Y = yellow, G = gold
  //   YYYGG    Both caps start at a y that is 2 mod 4, so they share the row index.
  //   GGGGG
  //   .GGG.
  wire in_cap = (pix_x >= POST_X - 1) && (pix_x < POST_X + 4) &&
                (((pix_y >= POST_Y0 - 2) && (pix_y < POST_Y0 + 2)) ||
                 ((pix_y >= POST_Y1 - 2) && (pix_y < POST_Y1 + 2)));
  wire [9:0] cap_dx = pix_x - (POST_X - 1);
  wire [9:0] cap_dy = pix_y - (POST_Y0 - 2);
  reg  [4:0] cap_on, cap_hi;  // bit 4 is the leftmost column
  always @(*) begin
    case (cap_dy[1:0])
      2'd0:    begin cap_on = 5'b01110; cap_hi = 5'b01100; end
      2'd1:    begin cap_on = 5'b11111; cap_hi = 5'b11100; end
      2'd2:    begin cap_on = 5'b11111; cap_hi = 5'b00000; end
      default: begin cap_on = 5'b01110; cap_hi = 5'b00000; end
    endcase
  end
  wire [2:0] cap_bit = 3'd4 - cap_dx[2:0];
  wire       cap     = in_cap && cap_on[cap_bit];

  wire       goal_post  = crossbar || post_stem || cap;
  wire       post_lit   = crossbar  ? (pix_x < POST_X + 2) :
                          post_stem ? (pix_y == STEM_Y) : cap_hi[cap_bit];
  wire [5:0] post_color = post_lit ? YELLOW : GOLD;

  // Shadow: a 3 px wide Y on the ground. The crossbar's shadow falls 12 px to the right
  // and 3 px down; the uprights' shadows run on from its ends for 54 px, dropping 1 px
  // every 4 px. Undoing that slope (sh_y) turns them back into straight bands.
  // The support post's shadow climbs from the end line to the crossbar's shadow at
  // 1 px every 8 px. Only every other pixel is darkened (a checkerboard), so the shadow
  // reads as darker grass instead of a black object.
  localparam [9:0] SH_X   = 22;   // crossbar shadow x = 22..24
  localparam [9:0] SH_Y0  = 183;  // crossbar shadow y = 183..302
  localparam [9:0] SH_Y1  = 300;  // lower upright shadow starts here
  localparam [9:0] SH_LEN = 55;   // upright shadows run to x = 76
  wire [9:0] sh_dx = pix_x - SH_X;
  wire [9:0] sh_y  = pix_y - {2'b0, sh_dx[9:2]};      // down 1 px every 4 px
  wire [9:0] st_dx = pix_x - BORDER;
  wire [9:0] st_y  = pix_y - {3'b0, st_dx[9:3]};      // down 1 px every 8 px
  wire shadow_post = (pix_x >= SH_X) && (pix_x < SH_X + SH_LEN) &&
                     (((sh_y >= SH_Y0) && (sh_y < SH_Y0 + 3)) ||                 // upper upright
                      ((sh_y >= SH_Y1) && (sh_y < SH_Y1 + 3)) ||                 // lower upright
                      ((pix_x < SH_X + 3) && (sh_y >= SH_Y0) && (sh_y < SH_Y1 + 3))); // crossbar
  wire shadow_stem = (pix_x >= BORDER) && (pix_x < SH_X) &&
                     (st_y >= STEM_Y) && (st_y < STEM_Y + 3);
  wire post_shadow = (shadow_post || shadow_stem) && (pix_x[0] ^ pix_y[0]);

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

  // Left half of the Notre Dame monogram at midfield. The 50 yard line is under the
  // right outline, so the logo's center line is the right edge of the field and its
  // right half is off screen. 16 x 23 sprite drawn at 4x size (64 x 92):
  //
  //   ......GGGGGGGG..    B = Notre Dame blue
  //   ......GBBBBBBG..    G = Notre Dame gold
  //   ......GBBBBBBG..    . = see-through
  //   ......GBBBBBBG..
  //   ..GGGGGBBBBBBGGG
  //   ..GBBBBBBBBBBBBB
  //   ..GBBBBBBBBBBBBB
  //   ..GBBBBBBBBBBBBB
  //   ...GBBBGGBBBGBBB
  //   ...GBBBGGBBBGBBB
  //   ...GBBBGGBBBGBBB
  //   ...GBBBGGBBBGBBB    <- middle row (11); the rows below mirror the rows above,
  //   ...GBBBGGBBBGBBB       except for the N's diagonal notch (col 12 rows 8..14,
  //   ...GBBBGGBBBGGBB       col 13 rows 13..14), which is added separately and is
  //   ...GBBBGGBBBGGBB       drawn 2 px wider than shown here (6 px instead of 4)
  //   ..GBBBBBBBBBBBBB
  //   ..GBBBBBBBBBBBBB
  //   ..GBBBBBBBBBBBBB
  //   ..GGGGGBBBBBBGGG
  //   ......GBBBBBBG..
  //   ......GBBBBBBG..
  //   ......GBBBBBBG..
  //   ......GGGGGGGG..
  //
  localparam [9:0] LOGO_X = 640 - BORDER - 64;  // = 572, x = 572..635
  localparam [9:0] LOGO_Y = 194;                 // y = 194..285, centered between the hash marks
  wire in_logo_box = (pix_x >= LOGO_X) && (pix_x < 640 - BORDER) &&
                     (pix_y >= LOGO_Y) && (pix_y < LOGO_Y + 92);
  wire [9:0] logo_dx   = pix_x - LOGO_X;
  wire [9:0] logo_dy   = pix_y - LOGO_Y;
  wire [3:0] logo_col  = logo_dx[5:2];                               // divide by 4 for the 4x size
  wire [4:0] logo_row  = logo_dy[6:2];                               // 0..22
  wire [4:0] logo_frow = (logo_row < 12) ? logo_row : 5'd22 - logo_row;  // fold: 0..11

  reg [15:0] logo_blue, logo_gold;  // bit 15 is the leftmost column
  always @(*) begin
    case (logo_frow[3:0])
      4'd0:    begin logo_gold = 16'b0000001111111100; logo_blue = 16'b0000000000000000; end
      4'd1:    begin logo_gold = 16'b0000001000000100; logo_blue = 16'b0000000111111000; end
      4'd2:    begin logo_gold = 16'b0000001000000100; logo_blue = 16'b0000000111111000; end
      4'd3:    begin logo_gold = 16'b0000001000000100; logo_blue = 16'b0000000111111000; end
      4'd4:    begin logo_gold = 16'b0011111000000111; logo_blue = 16'b0000000111111000; end
      4'd5:    begin logo_gold = 16'b0010000000000000; logo_blue = 16'b0001111111111111; end
      4'd6:    begin logo_gold = 16'b0010000000000000; logo_blue = 16'b0001111111111111; end
      4'd7:    begin logo_gold = 16'b0010000000000000; logo_blue = 16'b0001111111111111; end
      default: begin logo_gold = 16'b0001000110000000; logo_blue = 16'b0000111001111111; end  // 8..11
    endcase
  end
  // Notch, in pixels inside the logo box: a 6 px wide bar at x = 48..53 on rows 8..14
  // (same height as the slot to its left), and a foot that goes 4 px further right
  // (x = 54..57) on rows 13..14
  wire       logo_notch   = ((logo_dx[5:0] >= 6'd48) && (logo_dx[5:0] < 6'd54) &&
                             (logo_row >= 5'd8) && (logo_row <= 5'd14)) ||
                            ((logo_dx[5:0] >= 6'd54) && (logo_dx[5:0] < 6'd58) &&
                             (logo_row >= 5'd13) && (logo_row <= 5'd14));
  wire [3:0] logo_bit     = 4'd15 - logo_col;
  wire       logo_is_gold = in_logo_box && (logo_gold[logo_bit] || logo_notch);
  wire       logo_is_blue = in_logo_box && logo_blue[logo_bit];
  wire       logo_pixel   = logo_is_gold || logo_is_blue;
  wire [5:0] logo_color   = logo_is_gold ? ND_GOLD : ND_BLUE;

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
        else if (logo_pixel)
          {R, G, B} <= logo_color;                         // midfield logo over the lines
        else if (pix_x < GOAL_X)
          {R, G, B} <= goal_post   ? post_color :          // end zone with the goal post,
                       post_shadow ? (stripe ? GRAY : BLACK) :   // its shadow,
                       stripe      ? WHITE : DARK_GREEN;   // and the stripes
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
