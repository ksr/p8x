// cf_sd.v -- present a microSD card as the CF-IDE task file the P8X BIOS drives.
//
// The firmware talks 8-bit True IDE at $FF10..$FF17 and must not change, so this
// mirrors p8xemu.c's CF model register for register:
//
//   $FF10 data (r/w)   streams the 512-byte sector buffer, DRQ drops when drained
//   $FF11 feature (w)  $FF12 sector count (w, single-sector model)
//   $FF13-15 LBA0-2 (w)   $FF16 head/dev (w, bit 0 = device select)
//   $FF17 command (w) / status (r)
//
// Status differs from the emulator in exactly one way, and it matters: the
// emulator's transfers are instantaneous so it never asserts BSY, while a real
// card takes milliseconds. BSY is asserted here for the duration. The firmware
// already handles it -- CFWAIT spins on BSY for ~4096 polls, which at 9 MHz is
// roughly 14 ms, comfortably longer than a single-block read.
//
// Only device 0 exists (one slot). Device 1 reads back $FF, so the firmware's
// bounded waits time it out and report "no drive" rather than hanging -- the same
// floating-bus behaviour the emulator models for a missing drive.

module cf_sd(
  input        clk,
  input        rst,
  // task-file bus
  input        cf_rd,        // strobe: this microcycle reads the selected reg
  input        cf_wr,        // strobe: this microcycle writes it
  input  [2:0] cf_a,
  input  [7:0] cf_wdata,
  output [7:0] cf_rdata,
  // SD pins
  output       sd_clk,
  output       sd_mosi,
  input        sd_miso,
  output       sd_cs,
  output       card_ready);

  // ---- sector buffer ----
  //
  // 512 bytes, and the SHAPE of the code below is what decides whether that
  // costs one RAM or 4,096 flip-flops. yosys will only map an array onto a RAM
  // primitive if the array has ONE write port; a memory written from several
  // places at once has no primitive at all to map onto, so it falls back to
  // discrete flops plus a 512-entry read mux. This buffer used to do exactly
  // that -- IDENTIFY filled all 512 entries in a single cycle, which is 512
  // write ports -- and the result was over half the logic in the whole design,
  // with a mux whose cost re-optimised by thousands of LUTs whenever anything
  // unrelated changed. That instability is what kept pushing the LCD build off
  // the placement cliff. It is the same accident the palette hit earlier.
  //
  // So: every writer muxes onto the one port below, and every reader shares the
  // one asynchronous read. Keep it that way.
  reg [7:0] buf_[0:511];
  reg [9:0] idx;
  reg       drq, errf, wmode, dev;

  // The IDENTIFY fill walks the buffer a byte per clock instead of writing it
  // all at once. 512 clocks is 19 us at 27 MHz, invisible next to an SD command,
  // and BSY is held for the duration so a caller that does not poll DRQ still
  // cannot read the buffer mid-fill.
  reg       filling;
  reg [9:0] fi;

  // ---- task file ----
  reg [7:0] lba0, lba1, lba2, feat;

  wire present = (dev == 1'b0);          // only device 0 is fitted

  wire        sd_busy, sd_done, sd_err, sd_ready, sd_dstb, sd_dreq;
  wire [7:0]  sd_dout;
  reg         rd_req, wr_req;
  reg  [31:0] lba;
  reg  [7:0]  wbyte;

  sd_spi SD(.clk(clk), .rst(rst),
            .rd_req(rd_req), .wr_req(wr_req), .lba(lba),
            .busy(sd_busy), .done(sd_done), .err(sd_err),
            .d_out(sd_dout), .d_stb(sd_dstb), .d_in(wbyte), .d_req(sd_dreq),
            .ready(sd_ready),
            .sd_clk(sd_clk), .sd_mosi(sd_mosi), .sd_miso(sd_miso), .sd_cs(sd_cs));

  assign card_ready = sd_ready;

  // status: BSY | 0x40 | DRQ | ERR   (the 0x40 is DRDY, as in the emulator)
  // `filling` reads as BSY: during an IDENTIFY fill the buffer genuinely is not
  // ready, and the emulator's instantaneous fill is the thing being modelled.
  wire [7:0] status = {sd_busy | filling, 1'b1, 6'b0} | (drq ? 8'h08 : 8'h00)
                                                      | (errf ? 8'h01 : 8'h00);

  // ONE asynchronous read port, shared by the data-port read and the write path
  // that feeds the card. Two separate `buf_[idx]` reads would be two read ports
  // and two copies of the RAM.
  wire [7:0] bq = buf_[idx];

  assign cf_rdata = !present         ? 8'hFF :
                    (cf_a == 3'd0)   ? bq :
                    (cf_a == 3'd7)   ? status : 8'hFF;

  // IDENTIFY model string, byte-swapped into words 27-46 as ATA specifies.
  // Deliberately different from the emulator's "P8X-CF EMULATOR" so the monitor's
  // I command tells you at a glance whether you are on hardware or in the model.
  localparam [8*40:1] MODEL = "P8X-SD TANG NANO 20K                    ";

  // The swap that the old paired writes did structurally, now done to the INDEX:
  // buffer byte 54+j carries model character j^1. MODEL is declared [320:1] with
  // the first character in the high bits, so character c sits at (40-c)*8 -: 8.
  wire [9:0] moff  = fi - 10'd54;                   // 0..39 across the name field
  wire [6:0] mk    = 7'd40 - {1'b0, moff[5:0] ^ 6'd1};
  wire [7:0] fbyte = (fi >= 10'd54 && fi < 10'd94) ? MODEL[mk*8 -: 8] : 8'h00;

  // The single write port. Priority matters only in that these never overlap:
  // a fill runs with DRQ low and no transfer outstanding, and the card streams
  // in only during a read command while the CPU can only write during a write.
  wire       bw_en   = filling | sd_dstb
                     | (cf_wr && cf_a == 3'd0 && present && drq && wmode);
  wire [9:0] bw_addr = filling ? fi : idx;
  wire [7:0] bw_data = filling ? fbyte : (sd_dstb ? sd_dout : cf_wdata);

  always @(posedge clk) if (bw_en) buf_[bw_addr] <= bw_data;

  reg [1:0] cmd_pend;

  always @(posedge clk) begin
    if (rst) begin
      idx <= 0; drq <= 0; errf <= 0; wmode <= 0; dev <= 0;
      lba0 <= 0; lba1 <= 0; lba2 <= 0; feat <= 0;
      rd_req <= 0; wr_req <= 0; cmd_pend <= 0;
      filling <= 0; fi <= 0;
    end else begin
      rd_req <= 1'b0; wr_req <= 1'b0;

      // ---- IDENTIFY fill, one byte a clock ----
      // DRQ is raised only when the last byte has landed, so the monitor's
      // CFDRQ spin (bounded at ~4096 polls, far more than the 512 clocks this
      // takes) sees the buffer complete or not at all.
      if (filling) begin
        if (fi == 10'd511) begin
          filling <= 1'b0; fi <= 0; idx <= 0; drq <= 1'b1;
        end else fi <= fi + 1'b1;
      end

      // ---- data arriving from the card during a read ----
      if (sd_dstb) idx <= idx + 1'b1;          // the write itself is on bw_*
      // ---- card pulling data from us during a write ----
      if (sd_dreq) begin wbyte <= bq; idx <= idx + 1'b1; end

      if (sd_done) begin
        idx  <= 0;
        errf <= sd_err;
        drq  <= (cmd_pend == 2'd1) && !sd_err;   // read: buffer now has the data
        if (cmd_pend == 2'd2) drq <= 1'b0;       // write: transfer complete
        cmd_pend <= 0;
        wmode <= 1'b0;
      end

      if (cf_wr) begin
        case (cf_a)
          3'd1: feat <= cf_wdata;
          3'd2: ;                                 // sector count: single-sector
          3'd3: lba0 <= cf_wdata;
          3'd4: lba1 <= cf_wdata;
          3'd5: lba2 <= cf_wdata;
          3'd6: dev  <= cf_wdata[0];
          3'd0: if (present && drq && wmode) begin       // data port write
                  // the byte itself goes in through bw_*; this only sequences
                  if (idx == 10'd511) begin              // buffer full -> flush
                    idx <= 0; drq <= 0;
                    lba <= {8'd0, lba2, lba1, lba0};
                    wr_req <= 1'b1; cmd_pend <= 2'd2;
                  end else idx <= idx + 1'b1;
                end
          3'd7: if (present) case (cf_wdata)             // command
                  8'hEF: begin errf <= 0; drq <= 0; end          // SET FEATURES
                  8'hEC: if (!sd_ready) begin
                         // Report the truth: the IDENTIFY text is generated here,
                         // so without this a dead or absent card still answers
                         // "CF OK" and the failure only shows up later as a
                         // mysterious bad filesystem.
                         errf <= 1; drq <= 0;
                       end else begin                                 // IDENTIFY
                         // Start the fill; DRQ comes up when it finishes.
                         filling <= 1'b1; fi <= 0;
                         idx <= 0; drq <= 0; errf <= 0; wmode <= 0;
                       end
                  8'h20: if (!sd_ready) begin errf <= 1; drq <= 0; end
                       else begin                                     // READ SECTORS
                         idx <= 0; drq <= 0; errf <= 0; wmode <= 0;
                         lba <= {8'd0, lba2, lba1, lba0};
                         rd_req <= 1'b1; cmd_pend <= 2'd1;
                       end
                  8'h30: begin                                   // WRITE SECTORS
                         idx <= 0; drq <= 1; errf <= 0; wmode <= 1;
                         cmd_pend <= 0;
                       end
                  default: begin errf <= 1; drq <= 0; end
                endcase
        endcase
      end

      // ---- data port read: advance, drop DRQ when the buffer drains ----
      if (cf_rd && cf_a == 3'd0 && present && drq && !wmode) begin
        if (idx == 10'd511) begin idx <= 0; drq <= 1'b0; end
        else idx <= idx + 1'b1;
      end
    end
  end
endmodule
