// tb_gfx.v -- run a program on the RTL and dump the graphics framebuffer as a
// PPM, in exactly the format p8xemu's -g writes.
//
// That identical format is the whole point. The emulator is the golden model, so
// the test is not "does the picture look right" -- it is `cmp` of two files. Any
// difference at all, one pixel in eight thousand, fails. A Bresenham that lights
// a nicer-looking but different pixel is a bug, and this catches it.
//
// This is a FRAMEBUFFER diff, not the cycle-by-cycle trace diff run.sh does:
// the drawing engine is free to take however many clocks it likes, since nothing
// about its internal timing is visible to software except GSTAT's BUSY bit.
//
//   iverilog -g2012 -o tb_gfx.vvp ../rtl/p8x_cpu.v ../rtl/p8x_soc.v \
//            ../rtl/gfx.v tb_gfx.v
//   vvp tb_gfx.vvp +rom=gfx.hex +ppm=rtl.ppm

`timescale 1ns/1ps

module tb_gfx;
  reg clk = 0, rst = 1;
  always #5 clk = ~clk;

  wire halted;
  reg [1023:0] romfile, ppmfile;

  // The console and CF are unused by a graphics payload, but the SoC needs them
  // tied off: RX permanently empty, CF absent (reads $FF, as a missing drive).
  p8x_soc #(.UCODE_HEX("ucode.hex"), .MEM_HEX("gfxrom.hex")) DUT(
    .clk(clk), .rst(rst),
    .rx_byte(8'h00), .rx_avail(1'b0), .rx_take(), .st_rd(),
    .tx_stb(), .tx_byte(),
    .cf_rd(), .cf_wr(), .cf_a(), .cf_wdata(), .cf_rdata(8'hFF),
    .halted(halted));

  integer fh, x, y, r, i, cyc;
  reg [7:0] b;
  reg [7:0] pen;   // 8 bits: mode 1 has 256 pens
  reg [11:0] rgb;

  // Geometry is per-mode now. The dump has to ask the DEVICE which mode it is
  // in rather than assume, or a mode-1 payload would be read as mode 0 and the
  // diff would fail for entirely the wrong reason.
  wire       md  = DUT.GFX.gmode;
  wire [9:0] GW  = md ? 10'd480 : 10'd240;
  wire [9:0] GH  = md ? 10'd272 : 10'd136;
  wire [9:0] GSTR= md ? 10'd480 : 10'd60;
  wire [1:0] ZOOM= md ? 2'd1    : 2'd2;   // mode 0 is pixel-doubled to the panel

  initial begin
    if (!$value$plusargs("ppm=%s", ppmfile)) ppmfile = "rtl.ppm";
    repeat (4) @(posedge clk);
    rst = 0;

    // Run to HALT. The cap is a backstop: a payload that never halts should
    // fail loudly here rather than hang a CI run.
    cyc = 0;
    while (!halted && cyc < 2000000) begin
      @(posedge clk);
      cyc = cyc + 1;
    end
    if (!halted) begin
      $display("tb_gfx: FAIL - program did not HALT within %0d cycles", cyc);
      $finish;
    end
    // The CPU can HALT while the engine is still drawing -- a BOXFILL outlives
    // the store that started it by thousands of clocks. Let it finish, or the
    // dump catches a half-drawn screen and the diff fails for the wrong reason.
    repeat (200000) @(posedge clk);

    // PPM at PANEL resolution: every framebuffer pixel becomes a 2x2 block, so
    // the file shows what the panel shows. Byte-for-byte what gpu_writeppm does.
    fh = $fopen(ppmfile, "wb");
    if (fh == 0) begin $display("tb_gfx: cannot write %0s", ppmfile); $finish; end
    $fwrite(fh, "P6\n%0d %0d\n255\n", GW*ZOOM, GH*ZOOM);
    for (y = 0; y < GH; y = y + 1)
      for (r = 0; r < ZOOM; r = r + 1)
        for (x = 0; x < GW; x = x + 1) begin
          // The framebuffer is in the memory model now, not inside GFX.
          b   = DUT.SDRAM.mem[y*GSTR + (md ? x : (x >> 2))];
          pen = md ? b : ((b >> ((3 - (x % 4)) * 2)) & 2'b11);
          rgb = DUT.GFX.pal[pen];
          for (i = 0; i < ZOOM; i = i + 1) begin       // doubled across
            $fwrite(fh, "%c", ((rgb >> 8) & 4'hF) * 17);
            $fwrite(fh, "%c", ((rgb >> 4) & 4'hF) * 17);
            $fwrite(fh, "%c", ( rgb       & 4'hF) * 17);
          end
        end
    $fclose(fh);
    $display("tb_gfx: HALT at %0d cycles, wrote %0s", cyc, ppmfile);
    $finish;
  end
endmodule
