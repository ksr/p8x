// tb_sdram_scanout.v -- does framebuffer pixel N appear at panel column N?
//
// THE TEST THAT WAS MISSING. gfx.sh compares framebuffer CONTENTS and tb_video
// checked frame SHAPE; neither looks at the mapping between them, so a scanout
// that displays the right pixels in the wrong places passes both. The old
// video_rgb.v got tb_scanout.v for exactly this reason after a doubled-vertical-
// line bug; sdram_video.v shipped without an equivalent, and a doubled column
// duly turned up on the panel while the co-sim stayed green.
//
// The panel output is decoded back to the pixel byte, which is exact: 3-3-2 is
// spread as r={p[7:5],p[7:6]}, g={p[4:2],p[4:2]}, b={p[1:0],p[1:0],p[1]}, so
// {r[4:2], g[5:3], b[4:3]} recovers p precisely.
`timescale 1ns/1ps
module tb;
  reg clk=0, rst=1; always #5 clk=~clk;

  wire        rd; reg ack=0;
  wire [22:0] addr;
  reg  [31:0] dout32; reg data_ready=0;
  wire        pclk, de; wire [4:0] r, b; wire [5:0] g;
  wire [15:0] underruns; wire frame_tick, want_bus;

  sdram_video #(.FB_BASE(23'd0)) dut(
    .clk(clk), .rst(rst), .rd(rd), .ack(ack), .addr(addr), .dout32(dout32),
    .data_ready(data_ready), .want_bus(want_bus),
    .pclk(pclk), .de(de), .r(r), .g(g), .b(b),
    .underruns(underruns), .frame_tick(frame_tick));

  // framebuffer: 480x272 bytes
  reg [7:0] fb [0:130559];
  integer i, x, y;

  // memory model: ack next cycle, answer a few cycles later
  reg [2:0] lat=0; reg pend=0; reg [22:0] alat;
  always @(posedge clk) begin
    ack<=0; data_ready<=0;
    if(rst) begin lat<=0; pend<=0; end
    else if(rd && !ack && !pend && lat==0) begin ack<=1; alat<=addr; pend<=1; lat<=3; end
    else if(pend) begin
      if(lat==1) begin
        dout32 <= {fb[{alat[22:2],2'd3}], fb[{alat[22:2],2'd2}],
                   fb[{alat[22:2],2'd1}], fb[{alat[22:2],2'd0}]};
        data_ready<=1; pend<=0; lat<=0;
      end else lat<=lat-1;
    end
  end

  // capture one displayed row: decode the byte at each active column
  reg [7:0] seen [0:479];
  integer col, bad=0;
  reg capturing=0;
  reg pclk_d=0;
  always @(posedge clk) begin
    pclk_d <= pclk;
    if (capturing && pclk && !pclk_d && de) begin
      if (col < 480) seen[col] = {r[4:2], g[5:3], b[4:3]};
      col = col + 1;
    end
  end

  task capture_row;
    begin
      col = 0;
      for (i=0;i<480;i=i+1) seen[i] = 8'hEE;
      @(posedge dut.frame_tick);        // start of a frame
      capturing = 1;
      while (col < 480) @(posedge clk);
      capturing = 0;
    end
  endtask

  initial begin
    // Row 0 is a RAMP: column c must decode to c&255. A duplicated, shifted or
    // stale column shows up as a value that does not match its own index.
    for (y=0;y<272;y=y+1)
      for (x=0;x<480;x=x+1)
        fb[y*480+x] = (y==0) ? x[7:0] : 8'h00;
    // a single lit column at x=0 on row 1, which is the reported symptom
    fb[1*480+0] = 8'hFF;

    repeat(4) @(posedge clk); rst=0;
    // Let a couple of frames go by first. Frame 0 starts before any line has
    // been fetched, so capturing it reads an empty line buffer and reports
    // everything wrong -- a false alarm that hides the real one.
    @(posedge dut.frame_tick);
    @(posedge dut.frame_tick);
    $display("probe: fetching=%b fw=%0d inflight=%b rd=%b bank=%b underruns=%0d",
             dut.fetching, dut.fw, dut.inflight, rd, dut.bank, underruns);
    $display("probe: lbuf[0]=%08x lbuf[1]=%08x lbuf[128]=%08x",
             dut.lbuf[0], dut.lbuf[1], dut.lbuf[128]);
    capture_row;

    for (i=0;i<480;i=i+1)
      if (seen[i] !== i[7:0]) begin
        if (bad < 8)
          $display("FAIL: panel column %0d shows byte %02x, want %02x", i, seen[i], i[7:0]);
        bad = bad + 1;
      end

    if (bad) begin
      $display("TB-SCANOUT: FAIL - %0d of 480 columns wrong", bad);
      $display("  first few columns: %02x %02x %02x %02x %02x %02x",
               seen[0],seen[1],seen[2],seen[3],seen[4],seen[5]);
      $finish(1);
    end
    $display("TB-SCANOUT: PASS (framebuffer pixel N appears at panel column N)");
    $finish(0);
  end
endmodule
