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
  reg [7:0] buf_[0:511];
  reg [9:0] idx;
  reg       drq, errf, wmode, dev;

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
  wire [7:0] status = {sd_busy, 1'b1, 6'b0} | (drq ? 8'h08 : 8'h00)
                                            | (errf ? 8'h01 : 8'h00);
  assign cf_rdata = !present         ? 8'hFF :
                    (cf_a == 3'd0)   ? buf_[idx] :
                    (cf_a == 3'd7)   ? status : 8'hFF;

  // IDENTIFY model string, byte-swapped into words 27-46 as ATA specifies.
  // Deliberately different from the emulator's "P8X-CF EMULATOR" so the monitor's
  // I command tells you at a glance whether you are on hardware or in the model.
  localparam [8*40:1] MODEL = "P8X-SD TANG NANO 20K                    ";

  integer i;
  reg [1:0] cmd_pend;

  always @(posedge clk) begin
    if (rst) begin
      idx <= 0; drq <= 0; errf <= 0; wmode <= 0; dev <= 0;
      lba0 <= 0; lba1 <= 0; lba2 <= 0; feat <= 0;
      rd_req <= 0; wr_req <= 0; cmd_pend <= 0;
    end else begin
      rd_req <= 1'b0; wr_req <= 1'b0;

      // ---- data arriving from the card during a read ----
      if (sd_dstb) begin buf_[idx] <= sd_dout; idx <= idx + 1'b1; end
      // ---- card pulling data from us during a write ----
      if (sd_dreq) begin wbyte <= buf_[idx]; idx <= idx + 1'b1; end

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
                  buf_[idx] <= cf_wdata;
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
                         for (i = 0; i < 512; i = i + 1) buf_[i] <= 8'h00;
                         for (i = 0; i < 40; i = i + 2) begin
                           buf_[54+i]   <= MODEL[(40-(i+1))*8 -: 8];
                           buf_[54+i+1] <= MODEL[(40-i)*8 -: 8];
                         end
                         idx <= 0; drq <= 1; errf <= 0; wmode <= 0;
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
