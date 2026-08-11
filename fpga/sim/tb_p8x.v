// tb_p8x.v -- Milestone-1/2 co-sim testbench.
//
// Runs the P8X RTL for N cycles and (with -DP8X_TRACE) emits one canonical
// state line per cycle on stdout, in the SAME format as `p8xemu -T`. Diff the
// two traces to prove the RTL matches the golden emulator model.
//
//   +cycles=N    number of cycles to run (default 200000)
//   +rx=FILE     scripted console input, one byte per line as hex (optional).
//                Absent => the receiver is never ready, matching `p8xemu -N`.
//   +tx=FILE     write console output bytes here (optional)
//   +con         INTERACTIVE console: keystrokes from stdin, output to stdout.
//                For driving the monitor by hand (see console.sh). Not for
//                co-sim -- a live console is not reproducible by definition.
//
// The scripted input lives HERE rather than in p8x_soc, so the SoC stays free of
// file I/O and the whole console model is deterministic: RDRF is simply "the
// script still has a byte", and a byte is consumed exactly when the CPU reads
// $FF05. No baud timing, no arrival races -- both models step identically.
//
// Note: reads ucode.hex and eeprom.hex from the current directory (run.sh puts
// them there before invoking the sim).

`timescale 1ns/1ps
module tb_p8x;
  reg clk = 0;
  reg rst = 1;
  wire halted;

  // ---- console input: scripted (co-sim) or live from stdin (+con) ----
  reg [7:0] rxs [0:65535];
  integer   rx_len = 0;
  integer   rx_pos = 0;
  reg       con    = 0;         // interactive mode
  integer   pend   = -1;        // live mode: one-char lookahead, -1 = empty
  wire      rx_avail = con ? (pend >= 0) : (rx_pos < rx_len);
  wire [7:0] rx_byte = con ? pend[7:0] : (rx_avail ? rxs[rx_pos] : 8'h00);
  wire      rx_take;
  wire      st_rd;

  // ---- console output ----
  wire       tx_stb;
  wire [7:0] tx_byte;
  integer    txf = 0;

  p8x_soc SOC(.clk(clk), .rst(rst),
              .rx_byte(rx_byte), .rx_avail(rx_avail), .rx_take(rx_take),
              .st_rd(st_rd),
              .tx_stb(tx_stb), .tx_byte(tx_byte),
              .halted(halted));

  always #5 clk = ~clk;   // 100 MHz; functional sim only, frequency irrelevant

  // advance the script exactly when the CPU consumed a byte
  always @(posedge clk) if (rx_take && !con) rx_pos <= rx_pos + 1;
  always @(posedge clk) if (rx_take &&  con) pend   <= -1;

  // log console output
  always @(posedge clk) if (tx_stb && txf != 0) $fwrite(txf, "%02x\n", tx_byte);

  // ---- interactive console -------------------------------------------------
  // Blocking reads are the only portable way to get a key in Verilog, so we use
  // the emulator's rule (rx_misses/RX_SPIN): only block once the machine has
  // polled the status register SPIN times with no output in between, i.e. it is
  // genuinely idle at a prompt. Any output resets the count, so bulk printing
  // never stalls waiting for a keystroke.
  localparam SPIN = 2000;
  integer misses = 0;
  integer ch;
  always @(posedge clk) if (con) begin
    if (tx_stb) begin
      $write("%c", tx_byte); $fflush;
      misses <= 0;
    end else if (st_rd && pend < 0) begin
      if (misses >= SPIN) begin
        ch = $fgetc(32'h8000_0000);        // stdin
        if (ch < 0) begin $write("\n"); $finish; end
        pend   <= ch;
        misses <= 0;
      end else misses <= misses + 1;
    end
  end

  integer ncyc;
  reg [1023:0] rxfile, txfile;
  integer fd, i, c;
  initial begin
    if (!$value$plusargs("cycles=%d", ncyc)) ncyc = 200000;
    if ($test$plusargs("con")) begin con = 1; ncyc = 1<<30; end
    // scripted input: count the bytes so rx_len is exact (an unread rxs[] entry
    // is x, which would make rx_avail meaningless if we guessed the length)
    if ($value$plusargs("rx=%s", rxfile)) begin
      for (i = 0; i < 65536; i = i + 1) rxs[i] = 8'h00;
      $readmemh(rxfile, rxs);
      fd = $fopen(rxfile, "r");
      if (fd != 0) begin
        rx_len = 0;
        c = $fgetc(fd);
        while (c != -1) begin
          if (c == "\n") rx_len = rx_len + 1;
          c = $fgetc(fd);
        end
        $fclose(fd);
      end
    end
    if ($value$plusargs("tx=%s", txfile)) txf = $fopen(txfile, "w");
    // hold reset across two edges, then release
    @(posedge clk); @(posedge clk); rst = 0;
    // run until cycle budget or HALT
    while (ncyc > 0 && !halted) begin @(posedge clk); ncyc = ncyc - 1; end
    if (txf != 0) $fclose(txf);
    $finish;
  end
endmodule
