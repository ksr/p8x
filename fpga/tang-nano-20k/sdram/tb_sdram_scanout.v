// tb_sdram_scanout.v -- does framebuffer pixel N appear at panel column N?
//
// THE TEST THAT WAS MISSING. gfx.sh compares framebuffer CONTENTS and tb_video
// checked frame SHAPE; neither looks at the mapping between them, so a scanout
// that displays the right pixels in the wrong places passes both. The old
// video_rgb.v got tb_scanout.v for exactly this reason after a doubled-vertical-
// line bug; sdram_video.v shipped without an equivalent, and a doubled column
// duly turned up on the panel while the co-sim stayed green.
//
// Since the stream-port integration this bench runs the REAL memory path: the
// P8X streaming controller against the behavioural chip model, not a hand
// rolled stub at the fetch interface. What it proves is therefore the whole
// chain -- sdram_video's fetch bookkeeping, the controller's stream engine
// with refresh interleaved, and the mapping -- with underruns and protocol
// errors asserted at the end, not eyeballed.
//
// The panel output IS the pixel now: RGB565 goes to the pins unmodified, so
// {r,g,b} reassembles the 16-bit value exactly -- and the row-0 ramp holds
// 480 DISTINCT column values where the 8 bpp bench had to wrap at 256.
//
//   iverilog -g2012 -o tbsc tb_sdram_scanout.v sdram_video.v p8x_sdram.v sdram_chip.v
//   vvp tbsc
`timescale 1ns/1ps
module tb;
  reg clk=0, rst=1; always #5 clk=~clk;
  reg crst_n=0;                        // controller reset, released first

  wire        st_go, st_valid, st_done;
  wire [22:0] st_addr;
  wire [8:0]  st_words;
  wire [31:0] st_data;
  wire        pclk, de; wire [4:0] r, b; wire [5:0] g;
  wire [15:0] underruns; wire frame_tick;

  wire [31:0] dq;
  wire [10:0] m_A;   wire [1:0] m_BA;
  wire m_nCS, m_nWE, m_nRAS, m_nCAS, m_CLK, m_CKE;
  wire [3:0] m_DQM;
  wire c_busy;

  sdram_video #(.FB_BASE(23'd0)) dut(
    .clk(clk), .rst(rst),
    .st_go(st_go), .st_addr(st_addr), .st_words(st_words),
    .st_valid(st_valid), .st_data(st_data), .st_done(st_done),
    .pclk(pclk), .de(de), .r(r), .g(g), .b(b),
    .underruns(underruns), .frame_tick(frame_tick));

  p8x_sdram #(.FREQ(27_000_000)) CTL(
    .clk(clk), .clk_sdram(~clk), .resetn(crst_n),
    .rd(1'b0), .wr(1'b0), .wr_word(1'b0),
    .addr(23'd0), .din(16'd0), .dout(), .dout32(),
    .data_ready(), .busy(c_busy),
    .st_go(st_go), .st_addr(st_addr), .st_words(st_words),
    .st_valid(st_valid), .st_data(st_data), .st_done(st_done),
    .SDRAM_DQ(dq), .SDRAM_A(m_A), .SDRAM_BA(m_BA), .SDRAM_nCS(m_nCS),
    .SDRAM_nWE(m_nWE), .SDRAM_nRAS(m_nRAS), .SDRAM_nCAS(m_nCAS),
    .SDRAM_CLK(m_CLK), .SDRAM_CKE(m_CKE), .SDRAM_DQM(m_DQM));

  sdram_chip CHIP(
    .clk(clk), .SDRAM_DQ(dq), .SDRAM_A(m_A), .SDRAM_BA(m_BA),
    .SDRAM_nCS(m_nCS), .SDRAM_nWE(m_nWE), .SDRAM_nRAS(m_nRAS),
    .SDRAM_nCAS(m_nCAS), .SDRAM_CKE(m_CKE), .SDRAM_DQM(m_DQM));

  integer i, x, y;

  function [15:0] xw(input integer v); xw = v[15:0]; endfunction

  // capture one displayed row: reassemble the pixel at each active column
  reg [15:0] seen [0:479];       // row 0, for the column check
  reg [15:0] rowval [0:271];     // pixel of each displayed row (column 1)
  integer col, row, bad=0;
  reg capturing=0;
  reg pclk_d=0;
  always @(posedge clk) begin
    pclk_d <= pclk;
    if (capturing && pclk && !pclk_d && de) begin
      if (row == 0 && col < 480) seen[col] = {r, g, b};
      // Sample column 1, not column 0: the first pixel of every line is
      // latched before the bank swap and comes from the previous buffer, so
      // sampling it measures that bug instead of the row mapping.
      if (col == 1 && row < 272)  rowval[row] = {r, g, b};
      col = col + 1;
      if (col == 480) begin col = 0; row = row + 1; end
    end
  end

  integer u0;
  task capture_frame;
    begin
      col = 0; row = 0;
      u0 = underruns;                 // startup underruns are the controller's
                                      // init window; the FRAME must add none
      for (i=0;i<480;i=i+1) seen[i] = 16'hEEEE;
      for (i=0;i<272;i=i+1) rowval[i] = 16'hEEEE;
      @(posedge dut.frame_tick);
      capturing = 1;
      while (row < 272) @(posedge clk);
      capturing = 0;
    end
  endtask

  initial begin
    // Row 0 is a RAMP: column c must read back exactly c -- all 480 of them
    // distinct at 16 bpp. Every other row is filled with its own index
    // (checks ROW mapping). Preloaded as words at STRIDE 1024, two little-
    // endian pixels a word, matching the write path's layout.
    for (y=0;y<272;y=y+1)
      for (x=0;x<480;x=x+2) begin
        CHIP.mem[(y*1024+x*2)>>2] =
          (y==0) ? { xw(x+1), xw(x) }
                 : { y[15:0], y[15:0] };
      end

    // THE BOARD'S ordering, not a polite one: the scanout comes out of reset
    // WITH the controller and fires st_go into its 200 us init from the very
    // first end-of-line. Holding the video back here is how a first-boot
    // fetch wedge stayed invisible while every warm reset healed it.
    repeat(4) @(posedge clk); crst_n = 1; rst = 0;
    wait (!c_busy);

    // Let a couple of frames go by first. Frame 0 starts before any line has
    // been fetched, so capturing it reads an empty line buffer and reports
    // everything wrong -- a false alarm that hides the real one.
    @(posedge dut.frame_tick);
    @(posedge dut.frame_tick);
    capture_frame;

    // ROW mapping: panel row R must show framebuffer row R.
    for (i=1;i<272;i=i+1)
      if (rowval[i] !== i[15:0]) begin
        if (bad < 8)
          $display("FAIL: panel ROW %0d shows fb row %0d", i, rowval[i]);
        bad = bad + 1;
      end
    for (i=0;i<480;i=i+1)
      if (seen[i] !== i[15:0]) begin
        if (bad < 8)
          $display("FAIL: panel column %0d shows %04x, want %04x", i, seen[i], i[15:0]);
        bad = bad + 1;
      end

    $display("startup underruns (init window): %0d", u0);
    if (underruns !== u0[15:0]) begin
      $display("FAIL: %0d underruns DURING the captured frame", underruns - u0);
      bad = bad + 1;
    end
    if (CHIP.protocol_errors != 0) begin
      $display("FAIL: %0d SDRAM protocol errors", CHIP.protocol_errors);
      bad = bad + 1;
    end
    $display("refresh audit: %0d refreshes, max gap %0d cycles",
             CHIP.refreshes, CHIP.max_refresh_gap);
    if (CHIP.max_refresh_gap > 421) begin
      $display("FAIL: refresh starved during scanout");
      bad = bad + 1;
    end

    if (bad) begin
      $display("TB-SCANOUT: FAIL - %0d checks failed", bad);
      $display("  first few columns: %02x %02x %02x %02x %02x %02x",
               seen[0],seen[1],seen[2],seen[3],seen[4],seen[5]);
      $finish(1);
    end
    $display("TB-SCANOUT: PASS (mapping, real controller, board boot ordering, 0 frame underruns)");
    $finish(0);
  end
endmodule
