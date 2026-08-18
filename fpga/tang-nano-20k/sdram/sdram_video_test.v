// sdram_video_test.v -- Stage 1 top: a picture on the panel, fed from SDRAM.
//
// Still no CPU and nothing from the P8X design, for the same reason stage 0 had
// none: if this fails we want to know that the SDRAM video path is a dead end,
// not spend a day wondering which half of a merged design broke it.
//
// Sequence: paint a test image into SDRAM once, then hand the bus to the
// scanout and leave it running. The image is chosen so that every way this can
// go subtly wrong is VISIBLE rather than plausible:
//
//   - a one-pixel white border proves the first and last pixel of every line
//     and the first and last line arrive. Off-by-ones live exactly there, and
//     this project has already been bitten by a debug view that never sampled
//     x=239 or y=135.
//   - both diagonals cross every row and column, so a line fetched from the
//     wrong address, or a stride that is off by a byte, shears them visibly
//     instead of producing a picture that merely looks odd.
//   - a smooth horizontal ramp under a coarse vertical one: byte-lane errors in
//     the 32-bit word show up as a repeating 4-pixel stipple in the ramp, which
//     a flat colour field would hide completely.
//
// But the picture is only the sanity check. The MEASUREMENT is `underruns` --
// lines where the fetch did not finish before the buffers swapped. Tearing is
// obvious; a scanout that misses one line an hour is not, and that is exactly
// the fault that would surface later as an intermittent glitch once a drawing
// engine starts competing for the same bus. It is reported over UART with the
// frame count, so "0 underruns" can be read as "0 in N frames" rather than
// "0 so far".
module sdram_video_test(
    input        clk27,
    output [5:0] led,
    output       uart_txp,

    output       lcd_clk,
    output       lcd_de,
    output [4:0] lcd_r,
    output [5:0] lcd_g,
    output [4:0] lcd_b,

    // Magic names -- bonded in-package, must NOT appear in the .cst. See README.
    output        O_sdram_clk,
    output        O_sdram_cke,
    output        O_sdram_cs_n,
    output        O_sdram_cas_n,
    output        O_sdram_ras_n,
    output        O_sdram_wen_n,
    inout  [31:0] IO_sdram_dq,
    output [10:0] O_sdram_addr,
    output [1:0]  O_sdram_ba,
    output [3:0]  O_sdram_dqm);

  localparam FREQ   = 27_000_000;
  localparam H_ACT  = 480;
  localparam V_ACT  = 272;

  // ---- clocks (see sdram_test.v for why the PLL is here at all) --------------
  wire clk, clk_sdram, pll_lock;
  rPLL #(
    .FCLKIN("27"), .IDIV_SEL(1), .FBDIV_SEL(1), .ODIV_SEL(32),
    .PSDA_SEL("1010"), .DUTYDA_SEL("1000"), .DEVICE("GW2A-18C"),
    .DYN_IDIV_SEL("false"), .DYN_FBDIV_SEL("false"), .DYN_ODIV_SEL("false"),
    .DYN_DA_EN("false"), .CLKFB_SEL("internal"),
    .CLKOUT_BYPASS("false"), .CLKOUTP_BYPASS("false"), .CLKOUTD_BYPASS("false"),
    .CLKOUTD_SRC("CLKOUT"), .CLKOUT_DLY_STEP(0), .CLKOUTP_DLY_STEP(0)
  ) pll (
    .CLKIN(clk27), .CLKFB(1'b0), .RESET(1'b0), .RESET_P(1'b0),
    .FBDSEL(6'b0), .IDSEL(6'b0), .ODSEL(6'b0),
    .PSDA(4'b0), .DUTYDA(4'b0), .FDLY(4'b0),
    .CLKOUT(clk), .CLKOUTP(clk_sdram), .CLKOUTD(), .CLKOUTD3(), .LOCK(pll_lock));

  reg [13:0] rst_cnt = 0;
  reg        resetn  = 0;
  always @(posedge clk) begin
    if (!pll_lock)                  begin rst_cnt <= 0; resetn <= 0; end
    else if (rst_cnt != 14'h3FFF)   rst_cnt <= rst_cnt + 1'b1;
    else                            resetn <= 1;
  end

  // ---- controller -----------------------------------------------------------
  reg         c_rd, c_wr, c_refresh;
  reg  [22:0] c_addr;
  reg  [7:0]  c_din;
  wire [7:0]  c_dout;
  wire [31:0] c_dout32;
  wire        c_ready, c_busy;

  sdram #(.FREQ(FREQ)) u_sdram (
    .clk(clk), .clk_sdram(clk_sdram), .resetn(resetn),
    .addr(c_addr), .rd(c_rd), .wr(c_wr), .wr_word(1'b0), .refresh(c_refresh),
    .din(c_din), .dout(c_dout), .dout32(c_dout32),
    .data_ready(c_ready), .busy(c_busy),
    .SDRAM_DQ(IO_sdram_dq), .SDRAM_A(O_sdram_addr), .SDRAM_BA(O_sdram_ba),
    .SDRAM_nCS(O_sdram_cs_n), .SDRAM_nWE(O_sdram_wen_n),
    .SDRAM_nRAS(O_sdram_ras_n), .SDRAM_nCAS(O_sdram_cas_n),
    .SDRAM_CLK(O_sdram_clk), .SDRAM_CKE(O_sdram_cke), .SDRAM_DQM(O_sdram_dqm));

  // ---- refresh --------------------------------------------------------------
  localparam REFRESH_COUNT = FREQ / 1000 / 1000 * 15;
  reg [11:0] refresh_time = 0;
  reg        refresh_needed = 0, refresh_done;
  always @(posedge clk) begin
    if (!resetn) begin refresh_time <= 0; refresh_needed <= 0; end
    else begin
      if (refresh_time != REFRESH_COUNT) refresh_time <= refresh_time + 1'b1;
      else                               refresh_needed <= 1;
      if (refresh_done) begin refresh_time <= 0; refresh_needed <= 0; end
    end
  end

  // Declared here, not with the painter below: it gates the scanout instance.
  reg painting = 1;

  // ---- the scanout ----------------------------------------------------------
  wire        v_rd;
  wire [22:0] v_addr;
  wire        v_want;
  wire [15:0] underruns;
  wire        frame_tick;

  sdram_video #(.H_ACT(H_ACT), .V_ACT(V_ACT), .FB_BASE(23'd0)) u_video (
    .clk(clk), .rst(!resetn || painting),
    .rd(v_rd), .addr(v_addr), .dout32(c_dout32),
    .data_ready(c_ready && !painting), .busy(c_busy), .want_bus(v_want),
    .pclk(lcd_clk), .de(lcd_de), .r(lcd_r), .g(lcd_g), .b(lcd_b),
    .underruns(underruns), .frame_tick(frame_tick));

  // ---- painter: fill the framebuffer once, then get out of the way ----------
  // Byte-at-a-time, which is slow (130,560 writes, ~50 ms) and completely fine:
  // it happens once, before the scanout is released.
  reg  [9:0]  wx = 0, wy = 0;
  wire        border = (wx == 0) || (wx == H_ACT-1) || (wy == 0) || (wy == V_ACT-1);
  wire        diag   = (wx[8:0] == wy[8:0]) || (wx == (H_ACT-1) - wy);
  wire [7:0]  paint  = border ? 8'hFF :
                       diag   ? 8'hFF :
                       {wy[7:5], wx[8:6], wx[5:4]};

  always @(posedge clk) begin
    c_rd <= 0; c_wr <= 0; c_refresh <= 0; refresh_done <= 0;

    if (!resetn) begin
      painting <= 1; wx <= 0; wy <= 0;
    end else if (refresh_needed && !c_busy && !c_rd && !c_wr && !v_want) begin
      // Refresh only when the scanout has no fetch outstanding. During painting
      // v_want is low, so it interleaves freely there too.
      c_refresh    <= 1;
      refresh_done <= 1;
    end else if (painting) begin
      if (!c_busy && !c_rd && !c_wr) begin
        c_addr <= {13'd0, wy} * H_ACT + {13'd0, wx};
        c_din  <= paint;
        c_wr   <= 1;
        if (wx == H_ACT-1) begin
          wx <= 0;
          if (wy == V_ACT-1) painting <= 0;
          else               wy <= wy + 1'b1;
        end else wx <= wx + 1'b1;
      end
    end else begin
      // Scanout owns the bus from here on.
      c_addr <= v_addr;
      c_rd   <= v_rd;
    end
  end

  // ---- report ---------------------------------------------------------------
  // "SDVID UR=xxxx FR=xxxx\r\n" once a second. The frame count is what makes a
  // zero meaningful: 0 underruns in 1 frame proves nothing, 0 in 3000 does.
  reg [15:0] frames = 0;
  reg        de_d = 0;
  always @(posedge clk) begin
    de_d <= lcd_de;
    if (!resetn) frames <= 0;
    // count a frame on the first DE after the vertical gap: cheap and needs no
    // access to the scanout's internal counters
    else if (frame_tick) frames <= frames + 1'b1;
  end

  reg [7:0]  ch;
  reg [5:0]  mi = 0;
  reg [24:0] tick = 0;
  reg        sending = 0, send = 0;
  wire       tx_busy;

  uart_tx #(.DIV(FREQ/115200)) u_tx (
    .clk(clk), .rst(!resetn), .data(ch), .send(send), .tx(uart_txp), .busy(tx_busy));

  function [7:0] hex(input [3:0] n);
    hex = (n < 10) ? (8'h30 + n) : (8'h41 + n - 4'd10);
  endfunction

  localparam MSGLEN = 6'd23;
  always @(*) begin
    case (mi)
      0: ch="S"; 1: ch="D"; 2: ch="V"; 3: ch="I"; 4: ch="D"; 5: ch=" ";
      6: ch="U"; 7: ch="R"; 8: ch="=";
      9:  ch=hex(underruns[15:12]); 10: ch=hex(underruns[11:8]);
      11: ch=hex(underruns[7:4]);   12: ch=hex(underruns[3:0]);
      13: ch=" "; 14: ch="F"; 15: ch="R"; 16: ch="=";
      17: ch=hex(frames[15:12]); 18: ch=hex(frames[11:8]);
      19: ch=hex(frames[7:4]);   20: ch=hex(frames[3:0]);
      21: ch=8'h0D;
      default: ch=8'h0A;
    endcase
  end

  always @(posedge clk) begin
    send <= 0;
    if (!resetn) begin mi <= 0; sending <= 0; tick <= 0; end
    else if (!sending) begin
      tick <= tick + 1'b1;
      if (tick == 25'h1FFFFFF) begin tick <= 0; mi <= 0; sending <= 1; end
    end else if (!tx_busy && !send) begin
      send <= 1;
      if (mi == MSGLEN-1) begin sending <= 0; mi <= 0; end
      else                      mi <= mi + 1'b1;
    end
  end

  // led[5] = painting done, led[4] = no underruns yet, led[3:0] = low frame bits
  assign led = ~{!painting, (underruns == 0), frames[3:0]};

endmodule
