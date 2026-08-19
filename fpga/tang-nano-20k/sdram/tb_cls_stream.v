// tb_cls_stream.v -- does a WRITE STORM survive the scanout stream?
//
// THE TEST THAT WAS MISSING, round two. The controller bench's interleave
// phase landed word READS inside a running stream; the co-sim has no scanout
// at all. Nothing ever simulated the actual worst case: CLS -- paired-pixel
// writes at the engine's maximum rate -- against live line fetches. On the
// board that case LOSES WRITES IN CHUNKS (bars showing through a CLS as
// stripes), and a write is fire-and-forget through the arbiter, so nothing
// reports the loss.
//
// The full real stack: sdram_video fetching lines through the stream port,
// gfx_mem + sdram_arb writing a CLS-speed storm through the word port, the
// real controller, the protocol-checking chip model. Afterwards the CHIP's
// memory is audited word by word: every write the engine issued must be
// there. One missing word fails.
//
//   iverilog -g2012 -o tbcs tb_cls_stream.v sdram_video.v p8x_sdram.v \
//            sdram_chip.v sdram_arb.v gfx_mem.v
//   vvp tbcs
`timescale 1ns/1ps
module tb;
  reg clk=0, rst=1; always #5 clk=~clk;
  reg crst_n=0;

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
  wire c_busy, c_ready;
  wire        c_rd, c_wr, c_word;
  wire [22:0] c_addr;
  wire [15:0] c_din, c_dout;
  wire [31:0] c_dout32;

  sdram_video #(.FB_BASE(23'd0)) VID(
    .clk(clk), .rst(rst),
    .st_go(st_go), .st_addr(st_addr), .st_words(st_words),
    .st_valid(st_valid), .st_data(st_data), .st_done(st_done),
    .pclk(pclk), .de(de), .r(r), .g(g), .b(b),
    .underruns(underruns), .frame_tick(frame_tick));

  p8x_sdram #(.FREQ(27_000_000)) CTL(
    .clk(clk), .clk_sdram(~clk), .resetn(crst_n),
    .rd(c_rd), .wr(c_wr), .wr_word(c_word),
    .addr(c_addr), .din(c_din), .dout(c_dout), .dout32(c_dout32),
    .data_ready(c_ready), .busy(c_busy),
    .st_go(st_go), .st_addr(st_addr), .st_words(st_words),
    .st_valid(st_valid), .st_data(st_data), .st_done(st_done),
    .SDRAM_DQ(dq), .SDRAM_A(m_A), .SDRAM_BA(m_BA), .SDRAM_nCS(m_nCS),
    .SDRAM_nWE(m_nWE), .SDRAM_nRAS(m_nRAS), .SDRAM_nCAS(m_nCAS),
    .SDRAM_CLK(m_CLK), .SDRAM_CKE(m_CKE), .SDRAM_DQM(m_DQM));

  sdram_chip CHIP(
    .clk(clk), .SDRAM_DQ(dq), .SDRAM_A(m_A), .SDRAM_BA(m_BA),
    .SDRAM_nCS(m_nCS), .SDRAM_nWE(m_nWE), .SDRAM_nRAS(m_nRAS),
    .SDRAM_nCAS(m_nCAS), .SDRAM_CKE(m_CKE), .SDRAM_DQM(m_DQM));

  // engine side: gfx_mem through the real arbiter (spare masters tied off,
  // as on the board)
  wire e_req, e_we, e_word, e_ack, e_ready;
  wire [22:0] e_addr;
  wire [15:0] e_din;

  sdram_arb ARB(
    .clk(clk), .rst(rst),
    .c_rd(c_rd), .c_wr(c_wr), .c_wr_word(c_word), .c_refresh(),
    .c_addr(c_addr), .c_din(c_din), .c_dout(c_dout), .c_dout32(c_dout32),
    .c_ready(c_ready), .c_busy(c_busy),
    .s_req(1'b0), .s_addr(23'd0), .s_ack(), .s_ready(),
    .f_req(1'b0), .f_ack(),
    .e_req(e_req), .e_we(e_we), .e_word(e_word), .e_addr(e_addr),
    .e_din(e_din), .e_ack(e_ack), .e_ready(e_ready));

  reg  signed [17:0] px_x, px_y;
  reg  [15:0] px_pen;
  reg         px_go, px_read, px_word;
  wire        px_busy;
  wire [15:0] px_out;

  gfx_mem MEM(
    .clk(clk), .rst(rst),
    .px_x(px_x), .px_y(px_y), .px_pen(px_pen), .px_go(px_go),
    .px_read(px_read), .px_word(px_word),
    .px_busy(px_busy), .px_out(px_out),
    .e_req(e_req), .e_we(e_we), .e_word(e_word), .e_addr(e_addr),
    .e_din(e_din), .e_ack(e_ack), .e_ready(e_ready), .e_dout(c_dout));

  integer x, y, i, wrote, bad;


  // S_CLS's exact cadence: paired writes, next request the moment busy drops
  task cls_region(input integer y0, input integer y1, input [15:0] pen);
    begin
      for (y = y0; y <= y1; y = y + 1)
        for (x = 0; x < 480; x = x + 2) begin
          wait (!px_busy); @(posedge clk);
          px_x <= x; px_y <= y; px_pen <= pen;
          px_word <= 1'b1; px_read <= 0; px_go <= 1;
          @(posedge clk); px_go <= 0;
          @(posedge clk);
          wrote = wrote + 2;
        end
    end
  endtask

  initial begin
    wrote = 0; bad = 0;
    px_go = 0; px_read = 0; px_word = 0;

    // preload the fb region with a sentinel so a missing write is VISIBLE
    for (y = 0; y < 40; y = y + 1)
      for (x = 0; x < 480; x = x + 2)
        CHIP.mem[(y*1024 + x*2) >> 2] = 32'hBAD0BAD0;

    repeat(4) @(posedge clk); crst_n = 1;
    wait (!c_busy);
    @(posedge clk); rst = 0;

    // let the scanout get going -- the storm must run against LIVE fetches
    @(posedge frame_tick);

    // the storm: 40 lines of paired writes, exactly S_CLS's rhythm
    cls_region(0, 39, 16'h07E0);
    $display("storm done: %0d pixels written, underruns so far %0d", wrote, underruns);

    // drain, then audit the chip's memory: every pair must hold the pen
    repeat (100) @(posedge clk);
    for (y = 0; y < 40; y = y + 1)
      for (x = 0; x < 480; x = x + 2)
        if (CHIP.mem[(y*1024 + x*2) >> 2] !== 32'h07E007E0) begin
          if (bad < 12)
            $display("FAIL: pixels (%0d,%0d)+(%0d,%0d) hold %08x, want 07e007e0",
                     x, y, x+1, y, CHIP.mem[(y*1024 + x*2) >> 2]);
          bad = bad + 1;
        end

    if (CHIP.protocol_errors != 0) begin
      $display("FAIL: %0d protocol errors", CHIP.protocol_errors);
      bad = bad + 1;
    end
    if (bad) begin
      $display("TB-CLS-STREAM: FAIL -- %0d of 9600 pixel pairs wrong (writes lost under the stream)", bad);
      $finish(1);
    end
    $display("TB-CLS-STREAM: PASS (write storm survives the scanout stream, %0d underruns)", underruns);
    $finish(0);
  end

  initial begin
    #80_000_000;
    $display("TB-CLS-STREAM: TIMEOUT");
    $finish(1);
  end
endmodule
