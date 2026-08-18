// tb_sdram_arb.v -- the arbiter, against a controller stub that reproduces the
// two behaviours that actually cause bugs:
//
//   1. `busy` does not rise until the cycle AFTER a command pulse is seen.
//   2. on a read, `busy` DROPS in the very same cycle `data_ready` RISES.
//
// (2) is the deadlock generator. An arbiter that decides "the controller looks
// idle, someone else may go" will hand the bus away in exactly the cycle the
// outstanding answer arrives, and the read that was already in flight waits for
// an answer that has been and gone. A stub that dropped busy a cycle early
// would let a broken arbiter pass, so the timing here is the test.
//
//   iverilog -g2012 -o tba tb_sdram_arb.v sdram_arb.v && ./tba
`timescale 1ns/1ps

module tb;
  reg clk = 0, rst = 1;
  always #5 clk = ~clk;

  wire        c_rd, c_wr, c_wr_word, c_refresh;
  wire [22:0] c_addr;
  wire [7:0]  c_din;
  reg  [7:0]  c_dout;
  reg  [31:0] c_dout32;
  reg         c_ready, c_busy;

  reg         s_req = 0, f_req = 0, e_req = 0, e_we = 0, e_word = 0;
  reg  [22:0] s_addr = 0, e_addr = 0;
  reg  [7:0]  e_din = 0;
  wire        s_ack, s_ready, f_ack, e_ack, e_ready;

  sdram_arb dut(.clk(clk), .rst(rst),
    .c_rd(c_rd), .c_wr(c_wr), .c_wr_word(c_wr_word), .c_refresh(c_refresh),
    .c_addr(c_addr), .c_din(c_din), .c_dout(c_dout), .c_dout32(c_dout32),
    .c_ready(c_ready), .c_busy(c_busy),
    .s_req(s_req), .s_addr(s_addr), .s_ack(s_ack), .s_ready(s_ready),
    .f_req(f_req), .f_ack(f_ack),
    .e_req(e_req), .e_we(e_we), .e_word(e_word), .e_addr(e_addr),
    .e_din(e_din), .e_ack(e_ack), .e_ready(e_ready));

  // ---- controller stub -------------------------------------------------------
  integer cyc = 0, op = 0;          // op: 1 = read pending
  reg [22:0] a_lat;
  integer reads = 0, writes = 0, refreshes = 0, overlaps = 0;

  always @(posedge clk) begin
    c_ready <= 0;
    if (rst) begin c_busy <= 0; cyc <= 0; op <= 0; end
    else begin
      // Any command arriving while busy is an arbiter bug: it means two
      // operations were issued without waiting.
      if (c_busy && (c_rd || c_wr || c_refresh)) overlaps = overlaps + 1;

      if (cyc != 0) begin
        cyc <= cyc - 1;
        if (cyc == 1) begin
          c_busy <= 0;                       // (2): busy drops WITH data_ready
          if (op == 1) begin
            c_dout   <= a_lat[7:0] ^ 8'hA5;
            c_dout32 <= {a_lat[7:0], 8'h11, 8'h22, 8'h33};
            c_ready  <= 1;
          end
          op <= 0;
        end
      end else if (c_rd)      begin a_lat <= c_addr; c_busy <= 1; cyc <= 4; op <= 1; reads = reads+1; end
      else if (c_wr)          begin c_busy <= 1; cyc <= 4; op <= 0; writes = writes+1; end
      else if (c_refresh)     begin c_busy <= 1; cyc <= 4; op <= 0; refreshes = refreshes+1; end
    end
  end

  // ---- scoreboard ------------------------------------------------------------
  integer s_acks = 0, s_readies = 0, e_acks = 0, e_readies = 0, f_acks = 0;
  integer bad = 0;
  always @(posedge clk) if (!rst) begin
    if (s_ack)   s_acks    = s_acks + 1;
    if (s_ready) s_readies = s_readies + 1;
    if (e_ack)   e_acks    = e_acks + 1;
    if (e_ready) e_readies = e_readies + 1;
    if (f_ack)   f_acks    = f_acks + 1;
    // Two masters must never be acked in the same cycle.
    if ((s_ack && e_ack) || (s_ack && f_ack) || (e_ack && f_ack)) begin
      $display("FAIL: two masters acked in one cycle"); bad = bad + 1;
    end
    // An answer must never arrive for a master that has nothing outstanding.
    if (s_ready && e_ready) begin
      $display("FAIL: both masters got the same answer"); bad = bad + 1;
    end
  end

  task wait_ack(input integer which);   // 0=s 1=f 2=e
    integer guard;
    begin
      guard = 0;
      while (!((which==0 && s_ack) || (which==1 && f_ack) || (which==2 && e_ack))) begin
        @(posedge clk); guard = guard + 1;
        if (guard > 200) begin $display("FAIL: no ack for master %0d", which); bad=bad+1; disable wait_ack; end
      end
      @(posedge clk);
    end
  endtask

  initial begin
    repeat (4) @(posedge clk); rst = 0; @(posedge clk);

    // 1. a lone engine read gets through and comes back to the ENGINE
    e_addr = 23'h001234; e_we = 0; e_req = 1;
    wait_ack(2); e_req = 0;
    begin : w1
      integer g; g = 0;
      while (!e_ready) begin @(posedge clk); g=g+1; if (g>50) begin $display("FAIL: engine read never answered"); bad=bad+1; disable w1; end end
    end
    // Parenthesised deliberately: `!==` binds TIGHTER than `^` in Verilog, so
    // `c_dout !== a ^ b` means `(c_dout !== a) ^ b` -- which is always non-zero
    // and fails every time regardless of the data.
    if (c_dout !== ((8'h34) ^ 8'hA5)) begin $display("FAIL: engine got wrong data (%02x)", c_dout); bad=bad+1; end

    // 2. PRIORITY: both request in the same cycle -> the scanout must win, and
    //    the engine must still be waiting afterwards.
    s_addr = 23'h002000; s_req = 1;
    e_addr = 23'h003000; e_we = 0; e_req = 1;
    wait_ack(0);
    if (e_acks != 1) begin $display("FAIL: engine was served before the scanout"); bad=bad+1; end
    s_req = 0;
    begin : w2
      integer g; g = 0;
      while (!s_ready) begin @(posedge clk); g=g+1; if (g>50) begin $display("FAIL: scanout read never answered"); bad=bad+1; disable w2; end end
    end
    wait_ack(2); e_req = 0;          // the engine gets its turn afterwards

    // 3. refresh outranks the engine
    f_req = 1; e_addr = 23'h004000; e_we = 1; e_din = 8'h5A; e_req = 1;
    wait_ack(1); f_req = 0;
    wait_ack(2); e_req = 0;

    // 4. a span write carries wr_word through
    e_addr = 23'h005000; e_we = 1; e_word = 1; e_din = 8'h77; e_req = 1;
    @(posedge clk);
    if (!c_wr_word && c_wr) begin $display("FAIL: wr_word not forwarded"); bad=bad+1; end
    wait_ack(2); e_req = 0; e_word = 0;

    repeat (40) @(posedge clk);

    $display("reads=%0d writes=%0d refreshes=%0d  overlaps=%0d", reads, writes, refreshes, overlaps);
    $display("s_ack=%0d s_ready=%0d  e_ack=%0d e_ready=%0d  f_ack=%0d",
             s_acks, s_readies, e_acks, e_readies, f_acks);
    if (overlaps != 0) begin
      $display("TB-ARB: FAIL - %0d commands issued while the controller was busy", overlaps);
      $finish(1);
    end
    if (s_readies != 1 || e_readies != 2) begin
      $display("TB-ARB: FAIL - answers went to the wrong master (want s=1 e=2)");
      $finish(1);
    end
    if (bad != 0) begin $display("TB-ARB: FAIL - %0d assertion(s)", bad); $finish(1); end
    $display("TB-ARB: PASS (priority, exclusivity, answer routing, wr_word)");
    $finish(0);
  end
endmodule
