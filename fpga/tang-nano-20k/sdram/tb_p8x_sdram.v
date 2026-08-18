// tb_p8x_sdram.v -- the P8X streaming controller against the chip model.
//
//   iverilog -g2012 -o tbps tb_p8x_sdram.v p8x_sdram.v sdram_chip.v sdram.v
//   vvp tbps
//
// THE MODEL IS VALIDATED BEFORE IT JUDGES ANYTHING. Phase V runs the VENDORED
// controller -- known good on this hardware -- against sdram_chip. If that
// fails, the model is wrong, full stop. Only then does the new controller's
// verdict mean something. Same discipline as the emulator being the golden
// model for the CPU.
//
// Phase P then works the new controller:
//   P1  word port: random byte writes and read-back (the vendored contract)
//   P2  wr_word: all four lanes land
//   P3  stream: 240 words, in order, gapless enough to matter -- the cycle
//       count is ASSERTED, because "streams but slowly" is exactly the
//       failure that motivated this controller
//   P4  stream crossing a row boundary
//   P5  stream with concurrent word traffic: the bench plays sdram_arb,
//       firing one-cycle pulses whenever it samples !busy -- which is how
//       the window-closing straggler path (SGRAB) actually gets exercised
//   P6  abort: a second st_go mid-stream; the old stream never completes,
//       the new one's data is right, exactly one st_done
//   P7  the audit: chip-model protocol errors == 0, and the refresh gap
//       never exceeded the spec's 421 cycles -- measured, not assumed
`timescale 1ns/1ps
module tb_p8x_sdram;
  reg clk = 0;
  always #18.5 clk = ~clk;                    // 27 MHz
  reg resetn = 0;

  integer fails = 0;
  integer i, j, k, n, cyc0, ops;
  reg [31:0] w, exp;
  reg [22:0] a;

  // ---------------------------------------------------------------------------
  // Phase V: the vendored controller validates the chip model
  // ---------------------------------------------------------------------------
  wire [31:0] vdq;
  wire [10:0] v_A;   wire [1:0] v_BA;
  wire v_nCS, v_nWE, v_nRAS, v_nCAS, v_CLK, v_CKE;
  wire [3:0] v_DQM;

  reg         v_rd = 0, v_wr = 0, v_word = 0, v_ref = 0;
  reg  [22:0] v_addr = 0;
  reg   [7:0] v_din = 0;
  wire  [7:0] v_dout;
  wire [31:0] v_dout32;
  wire        v_ready, v_busy;

  sdram #(.FREQ(27_000_000)) VEND(
    .clk(clk), .clk_sdram(~clk), .resetn(resetn),
    .rd(v_rd), .wr(v_wr), .wr_word(v_word), .refresh(v_ref),
    .addr(v_addr), .din(v_din), .dout(v_dout), .dout32(v_dout32),
    .data_ready(v_ready), .busy(v_busy),
    .SDRAM_DQ(vdq), .SDRAM_A(v_A), .SDRAM_BA(v_BA), .SDRAM_nCS(v_nCS),
    .SDRAM_nWE(v_nWE), .SDRAM_nRAS(v_nRAS), .SDRAM_nCAS(v_nCAS),
    .SDRAM_CLK(v_CLK), .SDRAM_CKE(v_CKE), .SDRAM_DQM(v_DQM));

  sdram_chip CHIPV(
    .clk(clk), .SDRAM_DQ(vdq), .SDRAM_A(v_A), .SDRAM_BA(v_BA),
    .SDRAM_nCS(v_nCS), .SDRAM_nWE(v_nWE), .SDRAM_nRAS(v_nRAS),
    .SDRAM_nCAS(v_nCAS), .SDRAM_CKE(v_CKE), .SDRAM_DQM(v_DQM));

  // ---------------------------------------------------------------------------
  // Phase P: the new controller
  // ---------------------------------------------------------------------------
  wire [31:0] pdq;
  wire [10:0] p_A;   wire [1:0] p_BA;
  wire p_nCS, p_nWE, p_nRAS, p_nCAS, p_CLK, p_CKE;
  wire [3:0] p_DQM;

  reg         p_rd = 0, p_wr = 0, p_word = 0;
  reg  [22:0] p_addr = 0;
  reg  [15:0] p_din = 0;
  wire [15:0] p_dout;
  wire [31:0] p_dout32;
  wire        p_ready, p_busy;

  reg         st_go = 0;
  reg  [22:0] st_addr = 0;
  reg   [8:0] st_words = 0;
  wire        st_valid, st_done;
  wire [31:0] st_data;

  p8x_sdram #(.FREQ(27_000_000)) DUT(
    .clk(clk), .clk_sdram(~clk), .resetn(resetn),
    .rd(p_rd), .wr(p_wr), .wr_word(p_word),
    .addr(p_addr), .din(p_din), .dout(p_dout), .dout32(p_dout32),
    .data_ready(p_ready), .busy(p_busy),
    .st_go(st_go), .st_addr(st_addr), .st_words(st_words),
    .st_valid(st_valid), .st_data(st_data), .st_done(st_done),
    .SDRAM_DQ(pdq), .SDRAM_A(p_A), .SDRAM_BA(p_BA), .SDRAM_nCS(p_nCS),
    .SDRAM_nWE(p_nWE), .SDRAM_nRAS(p_nRAS), .SDRAM_nCAS(p_nCAS),
    .SDRAM_CLK(p_CLK), .SDRAM_CKE(p_CKE), .SDRAM_DQM(p_DQM));

  sdram_chip CHIPP(
    .clk(clk), .SDRAM_DQ(pdq), .SDRAM_A(p_A), .SDRAM_BA(p_BA),
    .SDRAM_nCS(p_nCS), .SDRAM_nWE(p_nWE), .SDRAM_nRAS(p_nRAS),
    .SDRAM_nCAS(p_nCAS), .SDRAM_CKE(p_CKE), .SDRAM_DQM(p_DQM));

  // stream collector: every st_valid word, in arrival order
  integer     sc_n = 0, done_n = 0;
  reg  [31:0] sc_buf [0:1023];
  always @(posedge clk) begin
    if (st_valid) begin sc_buf[sc_n] = st_data; sc_n = sc_n + 1; end
    if (st_done)  done_n = done_n + 1;
  end

  // cycle counter for budget assertions
  integer cycles = 0;
  always @(posedge clk) cycles = cycles + 1;



  task check(input cond, input [8*60:1] what);
    if (!cond) begin
      fails = fails + 1;
      $display("FAIL: %0s", what);
    end
  endtask

  // ---- vendored-port tasks (the arbiter's discipline, hand-rolled) ----------
  task v_write8(input [22:0] ad, input [7:0] d);
    begin
      wait (!v_busy); @(posedge clk);
      v_addr <= ad; v_din <= d; v_wr <= 1; @(posedge clk); v_wr <= 0;
      @(posedge clk); wait (!v_busy); @(posedge clk);
    end
  endtask
  task v_read8(input [22:0] ad, output [7:0] d);
    begin
      wait (!v_busy); @(posedge clk);
      v_addr <= ad; v_rd <= 1; @(posedge clk); v_rd <= 0;
      @(posedge clk); wait (v_ready);
      @(negedge clk); d = v_dout;       // mid-cycle: bus and mux settled
      @(posedge clk);
    end
  endtask

  // ---- new-controller word-port tasks (same discipline, 16-bit data) ---------
  task p_write16(input [22:0] ad, input [15:0] d, input word);
    begin
      wait (!p_busy); @(posedge clk);
      p_addr <= ad; p_din <= d; p_word <= word; p_wr <= 1;
      @(posedge clk); p_wr <= 0; p_word <= 0;
      @(posedge clk); wait (!p_busy); @(posedge clk);
    end
  endtask
  task p_read16(input [22:0] ad, output [15:0] d);
    begin
      wait (!p_busy); @(posedge clk);
      p_addr <= ad; p_rd <= 1; @(posedge clk); p_rd <= 0;
      @(posedge clk); wait (p_ready);
      @(negedge clk); d = p_dout;       // mid-cycle: bus and mux settled
      @(posedge clk);
    end
  endtask

  reg [7:0]  shadow [0:65535];              // byte shadow (vendored phase)
  reg [15:0] shadow16 [0:32767];            // halfword shadow (16-bit port)
  reg [7:0]  got8;
  reg [15:0] got16;
  integer seed = 32'h5EED;

  initial begin
    repeat (4) @(posedge clk);
    resetn = 1;

    // both controllers wait out the 200 us power-on delay
    wait (!v_busy);
    wait (!p_busy);
    $display("init done at %0d cycles", cycles);
    $display("phaseV start t=%0d", cycles);

    // ---- Phase V: validate the model against known-good RTL -----------------
    // the vendored refresh is the caller's job; hold it off during the burst
    // of writes, pulse it between ops the way sdram_test.v's timer would
    for (i = 0; i < 300; i = i + 1) begin
      a = $random(seed) & 23'h00FFFF;
      w = $random(seed) & 8'hFF;
      shadow[a[15:0]] = w[7:0];
      v_write8(a, w[7:0]);
      if (i % 16 == 15) begin               // a refresh now and then
        wait (!v_busy); @(posedge clk);
        v_ref <= 1; @(posedge clk); v_ref <= 0;
        @(posedge clk); wait (!v_busy); @(posedge clk);
      end
    end
    for (i = 0; i < 300; i = i + 1) begin
      a = $random(seed) & 23'h00FFFF;       // same sequence: reseed
      w = $random(seed);
    end
    seed = 32'h5EED;                        // replay the addresses
    for (i = 0; i < 300; i = i + 1) begin
      a = $random(seed) & 23'h00FFFF;
      w = $random(seed) & 8'hFF;
      v_read8(a, got8);
      check(got8 === shadow[a[15:0]], "phase V: vendored read-back mismatch");
    end
    check(CHIPV.protocol_errors == 0, "phase V: vendored RTL violated the model");
    if (fails == 0) $display("phase V ok: model validated against the vendored controller");

    $display("P1 start t=%0d", cycles);
    // ---- P1: word port, random 16-bit pixels --------------------------------
    seed = 32'hCAFE;
    for (i = 0; i < 300; i = i + 1) begin
      a = $random(seed) & 23'h00FFFE;         // halfword-aligned
      w = $random(seed) & 16'hFFFF;
      shadow16[a[15:1]] = w[15:0];
      p_write16(a, w[15:0], 1'b0);
    end
    seed = 32'hCAFE;
    for (i = 0; i < 300; i = i + 1) begin
      a = $random(seed) & 23'h00FFFE;
      w = $random(seed) & 16'hFFFF;
      p_read16(a, got16);
      check(got16 === shadow16[a[15:1]], "P1: word-port read-back mismatch");
    end
    if (fails == 0) $display("P1 ok: word port (internal refresh live throughout)");

    // ---- P2: wr_word paints the aligned PAIR --------------------------------
    p_write16(23'h010000, 16'hA55A, 1'b1);
    p_read16(23'h010000, got16);
    check(got16 === 16'hA55A, "P2: wr_word low half missing");
    p_read16(23'h010002, got16);
    check(got16 === 16'hA55A, "P2: wr_word high half missing");
    if (fails == 0) $display("P2 ok: wr_word pair");

    $display("P3 start t=%0d", cycles);
    // ---- P3: a straight 240-word stream, order and cost ---------------------
    for (i = 0; i < 512; i = i + 1)
      CHIPP.mem[21'h20000 + i] = 32'hBEE0_0000 + i;   // preload, write path proven above
    sc_n = 0; done_n = 0;
    @(posedge clk);
    cyc0 = cycles;
    st_addr <= 23'h20000 << 2; st_words <= 9'd240; st_go <= 1;
    @(posedge clk); st_go <= 0;
    wait (st_done); @(posedge clk);
    check(sc_n == 240, "P3: wrong word count");
    for (i = 0; i < 240; i = i + 1)
      if (sc_buf[i] !== 32'hBEE0_0000 + i) begin
        check(0, "P3: stream data mismatch"); i = 240;
      end
    $display("P3: 240 words in %0d cycles", cycles - cyc0);
    check(cycles - cyc0 < 400, "P3: stream slower than words + chunk overhead");
    if (fails == 0) $display("P3 ok: stream");

    // ---- P4: a stream crossing a row boundary -------------------------------
    // word 21'h200F8 has col 0xF8: 8 words in row, then 32 in the next
    for (i = 0; i < 64; i = i + 1)
      CHIPP.mem[21'h200F8 + i] = 32'hC0DE_0000 + i;
    sc_n = 0; done_n = 0;
    @(posedge clk);
    st_addr <= 23'h200F8 << 2; st_words <= 9'd40; st_go <= 1;
    @(posedge clk); st_go <= 0;
    wait (st_done); @(posedge clk);
    check(sc_n == 40, "P4: wrong word count over the row boundary");
    for (i = 0; i < 40; i = i + 1)
      if (sc_buf[i] !== 32'hC0DE_0000 + i) begin
        check(0, "P4: data mismatch over the row boundary"); i = 40;
      end
    if (fails == 0) $display("P4 ok: row boundary");

    $display("P5 start t=%0d", cycles);
    // ---- P5: stream with concurrent word traffic ----------------------------
    // The bench plays sdram_arb: sample !busy at an edge, fire the pulse on
    // the next. Some pulses will land in a closing window -- that is SGRAB's
    // reason to exist, and this is what walks into it.
    sc_n = 0; done_n = 0; ops = 0;
    @(posedge clk);
    st_addr <= 23'h20000 << 2; st_words <= 9'd240; st_go <= 1;
    @(posedge clk); st_go <= 0;
    j = 0;
    while (done_n == 0) begin
      @(posedge clk);
      if (!p_busy && !p_rd && !p_wr && done_n == 0) begin
        p_addr <= 23'h000100 + (ops & 63); p_rd <= 1;
        @(posedge clk); p_rd <= 0;
        @(posedge clk); wait (p_ready || done_n != 0);
        if (p_ready) ops = ops + 1;
        @(posedge clk);
      end
      j = j + 1;
      if (j > 20000) begin check(0, "P5: stream never finished"); done_n = 99; end
    end
    check(sc_n == 240, "P5: stream lost words under word traffic");
    for (i = 0; i < 240; i = i + 1)
      if (sc_buf[i] !== 32'hBEE0_0000 + i) begin
        check(0, "P5: stream data corrupted by word traffic"); i = 240;
      end
    $display("P5: %0d word reads landed inside the stream", ops);
    check(ops >= 2, "P5: the engine window never opened");
    if (fails == 0) $display("P5 ok: interleave");

    $display("P6 start t=%0d", cycles);
    // ---- P6: abort ----------------------------------------------------------
    for (i = 0; i < 256; i = i + 1)
      CHIPP.mem[21'h30000 + i] = 32'hAB00_0000 + i;
    sc_n = 0; done_n = 0;
    @(posedge clk);
    st_addr <= 23'h20000 << 2; st_words <= 9'd240; st_go <= 1;
    @(posedge clk); st_go <= 0;
    repeat (50) @(posedge clk);
    st_addr <= 23'h30000 << 2; st_words <= 9'd120; st_go <= 1;   // the abort
    @(posedge clk); st_go <= 0;
    wait (st_done); repeat (4) @(posedge clk);
    check(done_n == 1, "P6: aborted stream still signalled st_done");
    check(sc_n >= 120 && sc_n < 240 + 120, "P6: word count out of range");
    for (i = 0; i < 120; i = i + 1)
      if (sc_buf[sc_n - 120 + i] !== 32'hAB00_0000 + i) begin
        check(0, "P6: replacement stream data wrong"); i = 120;
      end
    if (fails == 0) $display("P6 ok: abort");

    $display("P7 start t=%0d", cycles);
    // ---- P7: the audit ------------------------------------------------------
    repeat (3000) @(posedge clk);           // idle soak: refresh alone
    check(CHIPP.protocol_errors == 0, "P7: protocol errors against the chip model");
    $display("P7: refreshes=%0d max_gap=%0d", CHIPP.refreshes, CHIPP.max_refresh_gap);
    check(CHIPP.max_refresh_gap <= 421, "P7: refresh gap exceeded the 421-cycle spec");
    check(CHIPP.refreshes >= (cycles - 5419) / 450, "P7: too few refreshes for the run length");

    if (fails == 0) $display("TB-P8X-SDRAM: PASS (model validated, word, stream, row-cross, interleave, abort, refresh audit)");
    else            $display("TB-P8X-SDRAM: FAIL (%0d)", fails);
    $finish;
  end

  initial begin
    #80_000_000;                            // 80 ms wall: something hung
    $display("TB-P8X-SDRAM: TIMEOUT");
    $finish;
  end
endmodule
