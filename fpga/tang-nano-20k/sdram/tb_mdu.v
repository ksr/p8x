// tb_mdu.v -- the stage-8a multiply-divide unit against a behavioral
// reference of the muldiv contract (STAGE8-DESIGN.md): signed (a*b)/c,
// 32-bit intermediate, truncate toward zero, saturate +/-32767, 0 when a
// or b is 0 (even with c=0), +/-32767 when c is 0.
//
// Checks, in order: the presence probe ('M'), the low-write-clears-high
// pair rule, the 14 directed vectors shared with emulator/test/c_g3d_test
// (same numbers -- three implementations pinned to one reference), then
// 2000 random vectors with the corner cases forced in ($8000 operands,
// zeros, c=0). Busy must clear within 24 cycles of MDGO, every time.
//
//   iverilog -g2012 -o tbmdu tb_mdu.v ../../rtl/p8x_mdu.v ../../rtl/mdu_core.v && ./tbmdu
`timescale 1ns/1ps

module tb;
  reg clk = 0, rst = 1;
  always #5 clk = ~clk;

  reg        sel = 0, wr = 0;
  reg  [3:0] a = 0;
  reg  [7:0] wdata = 0;
  wire [7:0] rdata;

  p8x_mdu dut (.clk(clk), .rst(rst), .sel(sel), .a(a), .wr(wr),
               .wdata(wdata), .rdata(rdata));

  integer errors = 0;

  task wr8(input [3:0] ra, input [7:0] v);
    begin
      @(negedge clk); sel = 1; wr = 1; a = ra; wdata = v;
      @(negedge clk); sel = 0; wr = 0;
    end
  endtask

  task rd8(input [3:0] ra, output [7:0] v);
    begin
      a = ra; sel = 1; #1; v = rdata; sel = 0;
    end
  endtask

  function signed [15:0] ref_muldiv(input signed [15:0] ia, ib, ic);
    integer ua, ub, uc, uq;
    begin
      ua = (ia < 0) ? -ia : ia;         // -(-32768) = 32768: intended
      ub = (ib < 0) ? -ib : ib;
      uc = (ic < 0) ? -ic : ic;
      if (ua == 0 || ub == 0) ref_muldiv = 0;
      else if (uc == 0)
        ref_muldiv = ((ia < 0) ^ (ib < 0)) ? -16'sd32767 : 16'sd32767;
      else begin
        uq = (ua * ub) / uc;            // <= 2^30, fits a 32-bit integer
        if (uq > 32767) uq = 32767;
        ref_muldiv = ((ia < 0) ^ (ib < 0) ^ (ic < 0)) ? -uq[15:0] : uq[15:0];
      end
    end
  endfunction

  reg [7:0] t1, t2;

  task check(input signed [15:0] ia, ib, ic);
    reg signed [15:0] want, got;
    integer n;
    begin
      wr8(4'h0, ia[7:0]); wr8(4'h9, ia[15:8]);
      wr8(4'h1, ib[7:0]); wr8(4'hA, ib[15:8]);
      wr8(4'h2, ic[7:0]); wr8(4'hB, ic[15:8]);
      wr8(4'h4, 8'h01);                              // MDGO
      n = 0; rd8(4'h5, t1);
      while ((t1 & 8'h80) && n < 30) begin
        @(negedge clk); n = n + 1; rd8(4'h5, t1);
      end
      if (n >= 24) begin
        $display("FAIL: busy for %0d cycles on (%0d,%0d,%0d)", n, ia, ib, ic);
        errors = errors + 1;
      end
      rd8(4'hC, t1); rd8(4'h3, t2);
      got  = {t1, t2};
      want = ref_muldiv(ia, ib, ic);
      if (got !== want) begin
        $display("FAIL: muldiv(%0d,%0d,%0d) = %0d, want %0d", ia, ib, ic, got, want);
        errors = errors + 1;
      end
    end
  endtask

  integer i;
  reg signed [15:0] ra, rb, rc;
  initial begin
    repeat (4) @(negedge clk); rst = 0; repeat (2) @(negedge clk);

    // the presence probe
    rd8(4'h6, t1);
    if (t1 !== 8'h4D) begin $display("FAIL: MDID != 'M'"); errors = errors + 1; end

    // the pair rule: a high then a low write leaves the high byte CLEAR
    wr8(4'h9, 8'h12); wr8(4'h0, 8'h34);      // a = $0034, not $1234
    wr8(4'h1, 8'h01); wr8(4'h2, 8'h01);      // b = 1, c = 1
    wr8(4'h4, 8'h01);
    repeat (24) @(negedge clk);
    rd8(4'hC, t1); rd8(4'h3, t2);
    if ({t1, t2} !== 16'h0034) begin
      $display("FAIL: low write did not clear the high byte"); errors = errors + 1;
    end

    // the directed vectors shared with c_g3d_test
    check(240, 271, 240);      check(12345, 271, 240);
    check(30000, 30000, 7);    check(-300, 250, 100);
    check(300, -250, 100);     check(-300, -250, 100);
    check(25000, 4, 100);      check(100, 0, 5);
    check(5, 7, 0);            check(-5, 7, 0);
    check(32767, 1, 1);        check(511, 513, 2);
    check(90, 120, 128);       check(-90, 120, 128);

    // the corners, explicitly
    check(-32768, 1, 1);       check(1, -32768, 1);
    check(-32768, -32768, 1);  check(-32768, -32768, -32768);
    check(0, 0, 0);            check(1, 1, -32768);
    check(32767, 32767, 1);    check(32767, 32767, 32767);

    // random sweep
    for (i = 0; i < 2000; i = i + 1) begin
      ra = $random; rb = $random; rc = $random;
      if (i % 7 == 0) rc = rc & 16'h00FF;    // small divisors: saturation path
      if (i % 11 == 0) rc = 0;
      if (i % 13 == 0) rb = rb & 16'h00FF;   // small products: full divide path
      check(ra, rb, rc);
    end

    if (errors == 0) $display("TB-MDU: PASS (probe, pair rule, %0d vectors)", 22 + 2000);
    else begin $display("TB-MDU: %0d FAILURES", errors); $finish; end
    $finish;
  end
endmodule
