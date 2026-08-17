// sdram_test.v -- Stage 0: does the Tang Nano 20K's in-package SDRAM actually
// work, on this board, under the open toolchain?
//
// Deliberately standalone: no CPU, no panel, nothing from the P8X design. If
// this fails we learn that the SDRAM path is a dead end BEFORE any of the
// graphics work is redesigned around it. It also gives the two numbers that
// decide whether the idea is affordable at all -- what the controller costs in
// LUTs, and what clock it holds -- which the build report prints for free.
//
// The controller is vendored and known-good (see sdram.v). Everything else here
// is ours.
//
// WHAT IT TESTS, and why each part earns its place:
//
//   1. A 64 KB sequential pass. Enough to cross column boundaries and several
//      rows, which is where a mis-wired address bus first shows up.
//   2. A sparse pass across the whole 8 MB, one byte every 64 KB. Address
//      ALIASING is the classic SDRAM failure -- rows, columns or banks wired
//      wrongly make high addresses fold back onto low ones -- and a sequential
//      test near address 0 cannot see it. Both patterns are derived from the
//      FULL address, so a fold writes a value that does not match on read-back.
//   3. Refresh runs throughout. A controller that reads back fine immediately
//      but drops bits after a few milliseconds is a refresh bug, so the two
//      passes are separated in time by the whole write phase.
//
// Results go to the LEDs (immediately, no host needed) and to the UART at
// 115200 (with the error counts, so a failure is diagnosable rather than just
// visible).
module sdram_test(
    input        clk27,          // 27 MHz crystal
    output [5:0] led,            // active LOW
    output       uart_txp,

    // The in-package SDRAM. These names are MAGIC: apicula bonds them to the
    // dedicated pads and they must NOT appear in the .cst. Renaming any of them
    // gets "ERROR: Unconstrained IO" -- see README.md, which records the
    // controlled experiment that established this.
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

  localparam FREQ = 27_000_000;

  // ---- clocks ---------------------------------------------------------------
  // 27 MHz in, 27 MHz out: the PLL is NOT here to multiply. It is here for
  // CLKOUTP, the same frequency phase-shifted 225 degrees, which is the clock
  // the SDRAM chip itself is given. The shift is what buys setup/hold margin at
  // the pads; driving the chip from the raw clock is the classic way to get a
  // controller that works in simulation and reads garbage on hardware.
  // Parameters are the ones Gowin's own IP generator produces for this board:
  // IDIV 2, FBDIV 2 -> 27 MHz, VCO 864 MHz (in range), PSDA_SEL 1010 = 225 deg.
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

  // ---- reset ----------------------------------------------------------------
  // SDRAM wants >=100 us of stable clock before initialisation. 16384 cycles at
  // 27 MHz is ~607 us, comfortably past it, and costs nothing once.
  reg [13:0] rst_cnt = 0;
  reg        resetn  = 0;
  always @(posedge clk) begin
    if (!pll_lock) begin
      rst_cnt <= 0;
      resetn  <= 0;
    end else if (rst_cnt != 14'h3FFF) begin
      rst_cnt <= rst_cnt + 1'b1;
    end else begin
      resetn <= 1;
    end
  end

  // ---- the controller -------------------------------------------------------
  reg         rd, wr, refresh;
  reg  [22:0] addr;
  reg  [7:0]  din;
  wire [7:0]  dout;
  wire        data_ready, busy;

  sdram #(.FREQ(FREQ)) u_sdram (
    .clk(clk), .clk_sdram(clk_sdram), .resetn(resetn),
    .addr(addr), .rd(rd), .wr(wr), .refresh(refresh),
    .din(din), .dout(dout), .data_ready(data_ready), .busy(busy),
    .SDRAM_DQ(IO_sdram_dq), .SDRAM_A(O_sdram_addr), .SDRAM_BA(O_sdram_ba),
    .SDRAM_nCS(O_sdram_cs_n), .SDRAM_nWE(O_sdram_wen_n),
    .SDRAM_nRAS(O_sdram_ras_n), .SDRAM_nCAS(O_sdram_cas_n),
    .SDRAM_CLK(O_sdram_clk), .SDRAM_CKE(O_sdram_cke), .SDRAM_DQM(O_sdram_dqm));

  // ---- refresh timer --------------------------------------------------------
  // The controller does not refresh itself; the caller must ask. Every row needs
  // refreshing every 64 ms and there are 8192 of them, so a pulse every 7.8 us
  // is the requirement. 15 us here is the reference design's figure and works
  // because the controller refreshes all banks per pulse.
  localparam REFRESH_COUNT = FREQ / 1000 / 1000 * 15;
  reg [11:0] refresh_time = 0;
  reg        refresh_needed = 0;
  reg        refresh_done;                 // pulse from the main FSM
  always @(posedge clk) begin
    if (!resetn) begin
      refresh_time   <= 0;
      refresh_needed <= 0;
    end else begin
      if (refresh_time != REFRESH_COUNT) refresh_time <= refresh_time + 1'b1;
      else                               refresh_needed <= 1;
      if (refresh_done) begin
        refresh_time   <= 0;
        refresh_needed <= 0;
      end
    end
  end

  // ---- the pattern ----------------------------------------------------------
  // Derived from the WHOLE address, so an address line that is stuck, swapped or
  // folded stores a byte that cannot match on read-back. A constant or a simple
  // counter would survive most aliasing faults unnoticed.
  function [7:0] pattern(input [22:0] a);
    pattern = a[7:0] ^ a[15:8] ^ {1'b0, a[22:16]} ^ 8'h5A;
  endfunction

  localparam SEQ_BYTES = 23'd65536;        // sequential pass: 64 KB from 0
  localparam SPARSE_N  = 23'd128;          // sparse pass: one byte per 64 KB, 8 MB

  localparam S_IDLE=0, S_WSEQ=1, S_RSEQ=2, S_RSEQ_W=3,
             S_WSPR=4, S_RSPR=5, S_RSPR_W=6, S_REFRESH=7, S_DONE=8;
  reg [3:0]  st = S_IDLE, st_ret = S_IDLE;
  reg [22:0] idx = 0;
  reg [15:0] err_seq = 0, err_spr = 0;     // saturating error counts
  reg [7:0]  want_b;                    // NOT `expect`: reserved in SystemVerilog

  wire [22:0] spr_addr = {idx[6:0], 16'd0};   // 0, 64K, 128K, ... 8M

  // A command may only be issued when the controller is idle AND our own
  // previous pulse has cleared. `busy` does not rise until the cycle AFTER the
  // controller sees rd/wr, so testing !busy alone lets a second command be
  // issued into that gap -- where it is silently swallowed. The symptom is
  // beautifully misleading: exactly HALF of memory reads back wrong, which
  // looks like a broken data bus rather than a handshake bug.
  wire can_issue = !busy && !rd && !wr;

  always @(posedge clk) begin
    rd <= 0; wr <= 0; refresh <= 0; refresh_done <= 0;

    if (!resetn) begin
      st <= S_IDLE; idx <= 0; err_seq <= 0; err_spr <= 0;
    end else if (refresh_needed && !busy && !rd && !wr
                 && st != S_REFRESH && st != S_DONE && st != S_IDLE
                 && st != S_RSEQ_W && st != S_RSPR_W) begin
      // Refresh takes priority over the test's own work, but ONLY from a state
      // where nothing is in flight. Excluding the two _W states is the whole
      // point: a read is issued in one state and answered by a one-cycle
      // data_ready pulse in the next, and the controller drops `busy` in the
      // SAME cycle it raises data_ready. Without these two exclusions the
      // refresh arm wins that cycle, the case() below never runs, the pulse is
      // missed, and the FSM waits forever for an answer that already came --
      // which on hardware is indistinguishable from the SDRAM having hung.
      refresh      <= 1;
      refresh_done <= 1;
      st_ret       <= st;
      st           <= S_REFRESH;
    end else case (st)
      S_IDLE:    if (!busy) begin idx <= 0; st <= S_WSEQ; end

      S_REFRESH: if (!busy) st <= st_ret;

      // ---- 64 KB sequential write, then read back and compare
      S_WSEQ: if (can_issue) begin
        addr <= idx; din <= pattern(idx); wr <= 1;
        if (idx == SEQ_BYTES - 1) begin idx <= 0; st <= S_RSEQ; end
        else                            idx <= idx + 1'b1;
      end
      S_RSEQ: if (can_issue) begin
        addr <= idx; rd <= 1; want_b <= pattern(idx); st <= S_RSEQ_W;
      end
      S_RSEQ_W: if (data_ready) begin
        if (dout != want_b && err_seq != 16'hFFFF) err_seq <= err_seq + 1'b1;
        if (idx == SEQ_BYTES - 1) begin idx <= 0; st <= S_WSPR; end
        else begin idx <= idx + 1'b1; st <= S_RSEQ; end
      end

      // ---- sparse pass over the full 8 MB
      S_WSPR: if (can_issue) begin
        addr <= spr_addr; din <= pattern(spr_addr); wr <= 1;
        if (idx == SPARSE_N - 1) begin idx <= 0; st <= S_RSPR; end
        else                           idx <= idx + 1'b1;
      end
      S_RSPR: if (can_issue) begin
        addr <= spr_addr; rd <= 1; want_b <= pattern(spr_addr); st <= S_RSPR_W;
      end
      S_RSPR_W: if (data_ready) begin
        if (dout != want_b && err_spr != 16'hFFFF) err_spr <= err_spr + 1'b1;
        if (idx == SPARSE_N - 1) st <= S_DONE;
        else begin idx <= idx + 1'b1; st <= S_RSPR; end
      end

      S_DONE: ;                            // hold; the reporter takes over
      default: st <= S_IDLE;
    endcase
  end

  // ---- report ---------------------------------------------------------------
  // "SDRAM SEQ=xxxx SPR=xxxx PASS\r\n", repeated about once a second so a
  // terminal attached at any time sees it.
  wire pass = (err_seq == 0) && (err_spr == 0);
  reg  [7:0]  ch;
  reg  [5:0]  mi = 0;                      // message index
  reg  [24:0] tick = 0;
  reg         sending = 0, send = 0;
  wire        tx_busy;

  uart_tx #(.DIV(FREQ/115200)) u_tx (
    .clk(clk), .rst(!resetn), .data(ch), .send(send), .tx(uart_txp), .busy(tx_busy));

  function [7:0] hex(input [3:0] n);
    hex = (n < 10) ? (8'h30 + n) : (8'h41 + n - 4'd10);
  endfunction

  localparam MSGLEN = 6'd30;
  always @(*) begin
    case (mi)
      0:  ch = "S";  1:  ch = "D";  2:  ch = "R";  3:  ch = "A";  4:  ch = "M";
      5:  ch = " ";  6:  ch = "S";  7:  ch = "E";  8:  ch = "Q";  9:  ch = "=";
      10: ch = hex(err_seq[15:12]);  11: ch = hex(err_seq[11:8]);
      12: ch = hex(err_seq[7:4]);    13: ch = hex(err_seq[3:0]);
      14: ch = " ";  15: ch = "S";  16: ch = "P";  17: ch = "R";  18: ch = "=";
      19: ch = hex(err_spr[15:12]);  20: ch = hex(err_spr[11:8]);
      21: ch = hex(err_spr[7:4]);    22: ch = hex(err_spr[3:0]);
      23: ch = " ";
      24: ch = pass ? "P" : "F";
      25: ch = pass ? "A" : "A";
      26: ch = pass ? "S" : "I";
      27: ch = pass ? "S" : "L";
      28: ch = 8'h0D;
      default: ch = 8'h0A;
    endcase
  end

  always @(posedge clk) begin
    send <= 0;
    if (!resetn) begin
      mi <= 0; sending <= 0; tick <= 0;
    end else if (!sending) begin
      tick <= tick + 1'b1;
      if (tick == 25'h1FFFFFF && st == S_DONE) begin
        tick <= 0; mi <= 0; sending <= 1;
      end
    end else if (!tx_busy && !send) begin
      send <= 1;
      if (mi == MSGLEN - 1) begin sending <= 0; mi <= 0; end
      else                        mi <= mi + 1'b1;
    end
  end

  // led[5] lit once the test has finished, led[4] lit if it passed, and
  // led[3:0] show the live state so a hang is visible without a terminal at
  // all: stuck on 1 or 2 is the sequential pass, 4 or 5 the sparse one.
  // (The LEDs are active LOW, hence the inversion.)
  assign led = ~{(st == S_DONE), (st == S_DONE) && pass, st[3:0]};

endmodule
