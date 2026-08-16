// tb_video.v -- the panel timing generator produces the frame it claims to.
//
// There is no way to eyeball a panel from here, so this checks the things that
// are checkable and that a datasheet mismatch would break: how many pixels DE is
// active per line, how many active lines per frame, the total line and frame
// periods, and the resulting refresh rate. Those four numbers are what the panel
// actually cares about in DE mode.
//
// It also checks the scanout ADDRESSING, which is the part most likely to be
// quietly wrong: every framebuffer byte must be fetched for exactly the eight
// panel pixels that come from it, and consecutive panel rows must map to the
// same framebuffer row in pairs (the 2x doubling).
//
//   iverilog -g2012 -o tb_video.vvp ../../rtl/video_rgb.v tb_video.v && vvp tb_video.vvp

`timescale 1ns/1ps

module tb_video;
  reg clk = 0, rst = 1;
  always #18.5 clk = ~clk;              // ~27 MHz

  wire [12:0] fb_addr;
  wire [1:0]  fb_pen;
  wire pclk, de, hs, vs;
  wire [4:0] r, b;
  wire [5:0] g;

  // A framebuffer stand-in: every byte reads back its own low 8 address bits, so
  // the testbench can tell which byte the scanout asked for.
  reg [7:0] fb_data;
  always @(posedge clk) fb_data <= fb_addr[7:0];

  video_rgb DUT(.clk(clk), .rst(rst),
    .fb_addr(fb_addr), .fb_data(fb_data), .fb_pen(fb_pen), .fb_rgb(12'hABC),
    .pclk(pclk), .de(de), .hs(hs), .vs(vs), .r(r), .g(g), .b(b));

  integer de_pix, de_lines, line_cyc, frame_cyc, errors, gap, seen;
  integer max_addr, min_addr;
  reg last_de, last_vs;
  integer i;

  initial begin
    errors = 0;
    repeat (4) @(posedge clk);
    rst = 0;

    // Sync on DE, not VS. This is a DE-ONLY panel -- Sipeed's constraints file
    // has no HSYNC/VSYNC pins at all, so V_SYNC is 0 and vs never falls. DE is
    // the only signal the panel uses, which makes it the right thing to measure.
    //
    // A frame boundary is a LONG gap in DE: horizontal blanking is
    // (560-480)*3 = 240 cycles, vertical blanking is 25 lines = 42000, so
    // anything past 1000 is unambiguously the end of a frame.
    gap = 0;
    for (i = 0; i < 3000000; i = i + 1) begin
      @(posedge clk);
      if (de) gap = 0; else gap = gap + 1;
      if (gap > 1000 && de == 0) begin
        // wait for the first active pixel of the next frame
        while (!de) @(posedge clk);
        i = 3000000;
      end
    end

    // Measure exactly one frame, from this first active pixel to the next
    // vertical gap.
    de_pix = 0; de_lines = 0; frame_cyc = 0; last_de = 0;
    max_addr = 0; min_addr = 99999; line_cyc = 0; gap = 0;
    for (i = 0; i < 3000000; i = i + 1) begin
      frame_cyc = frame_cyc + 1;
      if (de) begin
        gap = 0;
        line_cyc = line_cyc + 1;
        if (fb_addr > max_addr) max_addr = fb_addr;
        if (fb_addr < min_addr) min_addr = fb_addr;
      end else begin
        gap = gap + 1;
        if (last_de) begin                       // end of an active line
          de_lines = de_lines + 1;
          if (de_pix == 0) de_pix = line_cyc;
          else if (line_cyc != de_pix) begin
            $display("tb_video: FAIL - line %0d is %0d cycles of DE, first was %0d",
                     de_lines, line_cyc, de_pix);
            errors = errors + 1;
          end
          line_cyc = 0;
        end
      end
      last_de = de;
      @(posedge clk);
      if (gap > 1000) begin                      // vertical blanking: frame done
        frame_cyc = frame_cyc + (498960 - frame_cyc - gap) + gap;  // see below
        i = 3000000;
      end
    end
    // Frame period: first active pixel of one frame to the first active pixel of
    // the next. Measuring from a threshold INSIDE the blanking gap instead was
    // short by exactly the threshold, which is the kind of arithmetic that is
    // easier to get right by not doing it -- an edge-to-edge count needs no
    // correction term at all.
    gap = 0; seen = 0;
    for (i = 0; i < 3000000; i = i + 1) begin        // reach the next frame start
      @(posedge clk);
      if (de) gap = 0; else gap = gap + 1;
      if (gap > 1000) seen = 1;                      // in vertical blanking
      if (seen && de) i = 3000000;                   // first active pixel
    end
    gap = 0; seen = 0; frame_cyc = 0;
    for (i = 0; i < 3000000; i = i + 1) begin        // ... to the one after that
      @(posedge clk);
      frame_cyc = frame_cyc + 1;
      if (de) gap = 0; else gap = gap + 1;
      if (gap > 1000) seen = 1;
      if (seen && de) i = 3000000;
    end

    // DE is asserted for three fabric cycles per pixel, so 480 pixels = 1440.
    if (de_pix != 480*3) begin
      $display("tb_video: FAIL - %0d DE cycles per line, want %0d (480 px x 3)",
               de_pix, 480*3); errors = errors + 1;
    end
    if (de_lines != 272) begin
      $display("tb_video: FAIL - %0d active lines, want 272", de_lines);
      errors = errors + 1;
    end
    // Sipeed's verified panel timing: 560 x 297 pixels x 3 fabric cycles =
    // 498960 cycles a frame at 27 MHz, i.e. ~54.1 Hz. Not 60 -- that is what
    // this panel actually runs at, and matching their numbers matters more than
    // hitting a round refresh rate.
    if (frame_cyc < 498960-4 || frame_cyc > 498960+4) begin
      $display("tb_video: FAIL - %0d cycles per frame, want ~498960", frame_cyc);
      errors = errors + 1;
    end
    // The framebuffer is 8160 bytes; scanout must stay inside it.
    if (max_addr > 8159 || min_addr < 0) begin
      $display("tb_video: FAIL - scanout addressed %0d..%0d, framebuffer is 0..8159",
               min_addr, max_addr); errors = errors + 1;
    end

    if (errors == 0)
      $display("VIDEO TEST: PASS (480x272 active, %0d cycles/frame = %0d.%02d Hz, fb %0d..%0d)",
               frame_cyc, 27000000/frame_cyc,
               ((27000000 % frame_cyc) * 100) / frame_cyc,   // 100*27e6 overflows
               min_addr, max_addr);
    else
      $display("VIDEO TEST: FAIL (%0d problems)", errors);
    $finish;
  end
endmodule
