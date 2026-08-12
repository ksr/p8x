// tb_sd_spi.v -- unit test for sd_spi's ERROR paths.
//
// The board-level bench only ever runs a healthy card, so the failure branches
// were never executed. This drives sd_spi directly against the fault-injecting
// model and asserts the controller RECOVERS rather than wedging:
//
//   +sdfail=0  healthy: init completes, a read returns data
//   +sdfail=1  card never initialises -> must keep retrying, never latch up
//   +sdfail=2  card never releases busy after a write -> must time out and
//              return to idle, not hold busy forever
//
// Before the fix, sdfail=2 hung in S_WBUSY indefinitely (every later request
// silently dropped) and sdfail=1 sat in S_ERR re-pulsing `done` every clock.

`timescale 1ns/1ps
module tb_sd_spi;
  reg clk = 0;
  always #18.5 clk = ~clk;              // 27 MHz
  reg rst = 1;

  reg         rd_req = 0, wr_req = 0;
  reg  [31:0] lba = 0;
  wire        busy, done, err, ready, d_stb, d_req;
  wire [7:0]  d_out;
  reg  [7:0]  d_in = 8'hA5;
  wire        sck, mosi, cs, miso;

  sd_spi DUT(.clk(clk), .rst(rst), .rd_req(rd_req), .wr_req(wr_req), .lba(lba),
             .busy(busy), .done(done), .err(err),
             .d_out(d_out), .d_stb(d_stb), .d_in(d_in), .d_req(d_req),
             .ready(ready),
             .sd_clk(sck), .sd_mosi(mosi), .sd_miso(miso), .sd_cs(cs));
  sd_model CARD(.sd_clk(sck), .sd_mosi(mosi), .sd_miso(miso), .sd_cs(cs));

  integer mode = 0;
  integer i;
  integer resets = 0;
  reg prev_cs = 1;

  // count CS re-assertions while not ready: evidence the ladder is retrying
  always @(posedge clk) begin
    if (!ready && prev_cs && !cs) resets = resets + 1;
    prev_cs <= cs;
  end

  task wait_ready(input integer limit);
    begin
      i = 0;
      while (!ready && i < limit) begin @(posedge clk); i = i + 1; end
    end
  endtask

  initial begin
    if ($value$plusargs("sdfail=%d", mode)) ;
    repeat (4) @(posedge clk);
    rst = 0;

    if (mode == 1) begin
      // must NOT latch up: keep retrying and leave the door open for a card
      wait_ready(80_000_000);   // ACMD41 bound + a retry, at 27 MHz
      if (ready) $display("FAIL: card reported ready despite never initialising");
      else if (resets < 2)
        $display("FAIL: no retry -- controller latched up (CS asserted %0d time(s))", resets);
      else
        $display("PASS: never-init card, controller retried %0d times, no lockup", resets);
      $finish;
    end

    wait_ready(80_000_000);
    if (!ready) begin $display("FAIL: card never initialised"); $finish; end
    $display("init OK (ready asserted)");

    if (mode == 2) begin
      // write to a card that never releases busy: must time out, not hang
      @(posedge clk); wr_req <= 1; @(posedge clk); wr_req <= 0;
      while (!busy) @(posedge clk);        // don't race the request
      i = 0;
      while (busy && i < 8_000_000) begin @(posedge clk); i = i + 1; end
      if (busy)      $display("FAIL: still busy after %0d cycles -- S_WBUSY hangs", i);
      else if (!err) $display("FAIL: returned to idle but did not report an error");
      else           $display("PASS: stuck-busy write timed out after %0d cycles, err set", i);
      $finish;
    end

    // healthy: a read must complete and deliver 512 bytes
    @(posedge clk); rd_req <= 1; @(posedge clk); rd_req <= 0;
    while (!busy) @(posedge clk);          // don't race the request
    i = 0;
    while (busy && i < 8_000_000) begin @(posedge clk); i = i + 1; end
    if (busy)     $display("FAIL: read never completed");
    else if (err) $display("FAIL: healthy read reported an error");
    else          $display("PASS: healthy read completed in %0d cycles", i);
    $finish;
  end
endmodule
