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
//   +cfrw        open the CF image READ-WRITE and flush completed sector writes.
//                Off by default: the co-sim must never mutate the image it is
//                diffing, and a write that changed the disk would make a rerun
//                non-reproducible. console.sh passes it, because an interactive
//                session that reports "Saved" and silently discards the data is
//                worse than useless.
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

  // ---- CF-IDE model (mirrors the C model in p8xemu.c exactly) ----------------
  // Two devices on a shared task file. Feature/LBA writes latch into BOTH (the
  // firmware writes CFLBAx before CFHEAD); the DEV bit picks who executes the
  // command. An absent drive reads back $FF, so the firmware's bounded waits
  // time out instead of hanging. BSY is never asserted -- transfers here are
  // instantaneous, exactly as in the emulator.
  wire       cf_rd, cf_wr;
  wire [2:0] cf_a;
  wire [7:0] cf_wdata;
  reg  [7:0] cf_rdata;

  integer   cffd   [0:1];            // 0 = no image attached
  reg [7:0] cfbuf  [0:1023];         // dev*512 + idx
  integer   cfidx  [0:1];
  reg       cfdrq  [0:1];
  reg       cferr  [0:1];
  reg       cfwr_m [0:1];            // WRITE SECTORS in progress
  reg       cfrw = 1'b0;             // +cfrw: writes are flushed to the image
  reg [7:0] cflba0 [0:1], cflba1 [0:1], cflba2 [0:1], cffeat [0:1];
  reg       cfdev = 1'b0;            // ATA device select ($FF16 bit 0)
  wire      cfpres = (cffd[cfdev] != 0);

  always @* begin
    case (cf_a)
      3'd0: cf_rdata = cfpres ? cfbuf[cfdev*512 + cfidx[cfdev]] : 8'hFF;
      3'd7: cf_rdata = cfpres ? (8'h40 | (cfdrq[cfdev] ? 8'h08 : 8'h00)
                                       | (cferr[cfdev] ? 8'h01 : 8'h00)) : 8'hFF;
      default: cf_rdata = 8'hFF;
    endcase
  end

  p8x_soc SOC(.clk(clk), .rst(rst),
              .rx_byte(rx_byte), .rx_avail(rx_avail), .rx_take(rx_take),
              .st_rd(st_rd),
              .tx_stb(tx_stb), .tx_byte(tx_byte),
              .cf_rd(cf_rd), .cf_wr(cf_wr), .cf_a(cf_a),
              .cf_wdata(cf_wdata), .cf_rdata(cf_rdata),
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
        // EOF, or Ctrl-D typed at a non-canonical terminal (where the tty layer
        // does NOT turn ^D into EOF -- it arrives as a plain 0x04 byte).
        if (ch < 0 || ch == 8'h04) begin $write("\n"); $finish; end
        pend   <= ch;
        misses <= 0;
      end else misses <= misses + 1;
    end
  end

  // ---- CF behaviour ---------------------------------------------------------
  integer cfi, cfc, cflba;

  task cf_identify;                        // ATA IDENTIFY: byte-swapped model
    reg [8*40:1] m;                        // string at words 27-46 (bytes 54..)
    begin
      m = "P8X-CF EMULATOR                         ";
      for (cfi = 0; cfi < 512; cfi = cfi + 1) cfbuf[cfdev*512 + cfi] = 8'h00;
      // reg [8*40:1] holds char 0 in the HIGH bits, so char i is m[(40-i)*8 -: 8].
      // The pairs are swapped, which is what ATA IDENTIFY does and what the
      // monitor's I command un-swaps when it prints the model string.
      for (cfi = 0; cfi < 40; cfi = cfi + 2) begin
        cfbuf[cfdev*512 + 54 + cfi]     = m[(40-(cfi+1))*8 -: 8];
        cfbuf[cfdev*512 + 54 + cfi + 1] = m[(40-cfi)*8 -: 8];
      end
      cfidx[cfdev] = 0; cfdrq[cfdev] = 1; cferr[cfdev] = 0; cfwr_m[cfdev] = 0;
    end
  endtask

  task cf_writesec;                        // flush the sector buffer to the image
    begin
      cflba = (cflba2[cfdev] << 16) | (cflba1[cfdev] << 8) | cflba0[cfdev];
      if (cfrw && cffd[cfdev] != 0) begin
        cfc = $fseek(cffd[cfdev], cflba * 512, 0);
        for (cfi = 0; cfi < 512; cfi = cfi + 1)
          $fwrite(cffd[cfdev], "%c", cfbuf[cfdev*512 + cfi]);
        $fflush(cffd[cfdev]);
      end
    end
  endtask

  task cf_readsec;
    begin
      for (cfi = 0; cfi < 512; cfi = cfi + 1) cfbuf[cfdev*512 + cfi] = 8'h00;
      cflba = (cflba2[cfdev] << 16) | (cflba1[cfdev] << 8) | cflba0[cfdev];
      if (cffd[cfdev] != 0) begin
        cfc = $fseek(cffd[cfdev], cflba * 512, 0);
        for (cfi = 0; cfi < 512; cfi = cfi + 1) begin
          cfc = $fgetc(cffd[cfdev]);
          cfbuf[cfdev*512 + cfi] = (cfc < 0) ? 8'h00 : cfc[7:0];
        end
      end
      cfidx[cfdev] = 0; cfdrq[cfdev] = 1; cferr[cfdev] = 0; cfwr_m[cfdev] = 0;
    end
  endtask

  always @(posedge clk) begin
    // data-port read: advance, drop DRQ when the 512-byte buffer drains
    if (cf_rd && cf_a == 3'd0 && cfpres) begin
      if (cfidx[cfdev] >= 511) begin cfidx[cfdev] <= 0; cfdrq[cfdev] <= 1'b0; end
      else                           cfidx[cfdev] <= cfidx[cfdev] + 1;
    end
    if (cf_wr) begin
      // shared task file: both devices latch feature and LBA
      case (cf_a)
        3'd1: begin cffeat[0] <= cf_wdata; cffeat[1] <= cf_wdata; end
        3'd3: begin cflba0[0] <= cf_wdata; cflba0[1] <= cf_wdata; end
        3'd4: begin cflba1[0] <= cf_wdata; cflba1[1] <= cf_wdata; end
        3'd5: begin cflba2[0] <= cf_wdata; cflba2[1] <= cf_wdata; end
        3'd6: cfdev <= cf_wdata[0];        // DEV select
        default: ;                         // $FF12 sector count: single-sector model
      endcase
      // data and command route to the selected device, and only if present
      if (cfpres) begin
        if (cf_a == 3'd0) begin            // data port write
          cfbuf[cfdev*512 + cfidx[cfdev]] = cf_wdata;
          if (cfidx[cfdev] >= 511) begin
            // buffer full: flush it if +cfrw, otherwise drain and discard (the
            // co-sim must not mutate the image it is diffing)
            cf_writesec();
            cfidx[cfdev] <= 0; cfdrq[cfdev] <= 1'b0; cfwr_m[cfdev] <= 1'b0;
          end else cfidx[cfdev] <= cfidx[cfdev] + 1;
        end
        if (cf_a == 3'd7) case (cf_wdata)  // command
          8'hEF: begin cferr[cfdev] <= 1'b0; cfdrq[cfdev] <= 1'b0; end  // SET FEATURES
          8'hEC: cf_identify();                                          // IDENTIFY
          8'h20: cf_readsec();                                           // READ SECTORS
          8'h30: begin cfidx[cfdev] <= 0; cfdrq[cfdev] <= 1'b1;          // WRITE SECTORS
                       cferr[cfdev] <= 1'b0; cfwr_m[cfdev] <= 1'b1; end
          default: begin cferr[cfdev] <= 1'b1; cfdrq[cfdev] <= 1'b0; end
        endcase
      end
    end
  end

  integer ncyc;
  reg [1023:0] rxfile, txfile, cffile, cffile1;
  integer fd, i, c;
  initial begin
    if (!$value$plusargs("cycles=%d", ncyc)) ncyc = 200000;
    if ($test$plusargs("con")) begin con = 1; ncyc = 1<<30; end
    // CF images (read-only: a co-sim run must never mutate the disk)
    for (i = 0; i < 2; i = i + 1) begin
      cffd[i] = 0; cfidx[i] = 0; cfdrq[i] = 0; cferr[i] = 0; cfwr_m[i] = 0;
      cflba0[i] = 0; cflba1[i] = 0; cflba2[i] = 0; cffeat[i] = 0;
    end
    for (i = 0; i < 1024; i = i + 1) cfbuf[i] = 8'h00;
    cfrw = $test$plusargs("cfrw");
    if ($value$plusargs("cf=%s",  cffile))
      cffd[0] = cfrw ? $fopen(cffile,  "r+b") : $fopen(cffile,  "rb");
    if ($value$plusargs("cf1=%s", cffile1))
      cffd[1] = cfrw ? $fopen(cffile1, "r+b") : $fopen(cffile1, "rb");
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
