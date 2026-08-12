// sd_model.v -- behavioural microSD card in SPI mode, for simulation only.
//
// Enough of the protocol to exercise sd_spi.v end to end: the CMD0 / CMD8 /
// ACMD41 / CMD58 initialisation ladder, CMD17 single-block read, CMD24 single-
// block write. Sector data comes from a real disk image via $fseek, so the
// monitor can actually boot P8XFS in simulation.
//
//   +sd=FILE   disk image to serve (required for reads to return real data)
//
// Deliberately models an SDHC card (CMD58 reports CCS=1), because that is what
// any modern card is and it is the case where LBA is a BLOCK number rather than
// a byte offset -- the easiest thing to get wrong by a factor of 512.
//
// ACMD41 reports "still initialising" a few times before going ready, so the
// controller's retry loop is actually exercised rather than passing by luck.

module sd_model(
  input  sd_clk,
  input  sd_mosi,
  output reg sd_miso,
  input  sd_cs);

  integer fd = 0;
  reg [1023:0] fname;
  initial begin
    sd_miso = 1'b1;
    if ($value$plusargs("sd=%s", fname)) fd = $fopen(fname, "rb");
  end

  reg [7:0]  rxsh = 8'hFF;
  reg [3:0]  nbit = 0;
  reg [7:0]  txb  = 8'hFF;
  reg [7:0]  frame [0:5];
  reg [2:0]  fidx = 0;
  reg        infr = 0;

  // response queue
  reg [7:0]  q [0:1023];
  integer    qn = 0, qi = 0;
  integer    acmd41_left = 3;
  reg        expect_acmd = 0;
  integer    i, c;
  reg [31:0] arg;
  reg        wr_wait = 0;      // waiting for the write data token
  integer    wr_cnt = 0;

  task qput(input [7:0] b); begin q[qn] = b; qn = qn + 1; end endtask
  task qreset;              begin qn = 0; qi = 0; end endtask

  // sample MOSI on the rising edge (master drove it on the falling edge)
  always @(posedge sd_clk) if (!sd_cs) begin
    rxsh = {rxsh[6:0], sd_mosi};
    nbit = nbit + 1;
    if (nbit == 8) begin
      nbit = 0;
      handle_byte(rxsh);
    end
  end

  // drive MISO on the falling edge
  always @(negedge sd_clk) if (!sd_cs) begin
    if (nbit == 0) begin
      if (qi < qn) begin txb = q[qi]; qi = qi + 1; end else txb = 8'hFF;
    end
    sd_miso = txb[7 - nbit];
  end
  always @(*) if (sd_cs) sd_miso = 1'b1;

  task handle_byte(input [7:0] b);
    begin
      if (wr_wait) begin
        if (b == 8'hFE) begin wr_wait = 0; wr_cnt = 0; end   // data token
      end else if (wr_cnt > 0) begin
        wr_cnt = wr_cnt - 1;
        if (wr_cnt == 0) begin
          qreset; qput(8'hFF); qput(8'h05); qput(8'h00); qput(8'hFF); // accepted
        end
      end else if (infr) begin
        frame[fidx] = b; fidx = fidx + 1;
        if (fidx == 5) begin infr = 0; do_cmd(); end
      end else if (b[7:6] == 2'b01) begin
        frame[0] = b; fidx = 1; infr = 1;
      end
    end
  endtask

  task do_cmd;
    reg [5:0] idx;
    begin
      idx = frame[0][5:0];
      arg = {frame[1], frame[2], frame[3], frame[4]};
      qreset;
      qput(8'hFF);                                   // Ncr gap
      if (expect_acmd && idx == 41) begin
        expect_acmd = 0;
        if (acmd41_left > 0) begin acmd41_left = acmd41_left - 1; qput(8'h01); end
        else qput(8'h00);                            // ready
      end else case (idx)
        0:  qput(8'h01);                             // GO_IDLE -> idle state
        8:  begin qput(8'h01); qput(8'h00); qput(8'h00); qput(8'h01); qput(8'hAA); end
        55: begin qput(8'h01); expect_acmd = 1; end
        58: begin qput(8'h00); qput(8'hC0); qput(8'hFF); qput(8'h80); qput(8'h00); end
        16: qput(8'h00);                             // SET_BLOCKLEN
        17: begin                                    // READ_SINGLE_BLOCK
              qput(8'h00);
              qput(8'hFF); qput(8'hFF);              // a little latency
              qput(8'hFE);                           // data token
              if (fd != 0) begin
                c = $fseek(fd, arg * 512, 0);        // CCS=1 -> arg is a block
                for (i = 0; i < 512; i = i + 1) begin
                  c = $fgetc(fd);
                  qput((c < 0) ? 8'h00 : c[7:0]);
                end
              end else for (i = 0; i < 512; i = i + 1) qput(8'h00);
              qput(8'h00); qput(8'h00);              // CRC16 (ignored)
            end
        24: begin qput(8'h00); wr_wait = 1; wr_cnt = 514; end  // WRITE_BLOCK
        default: qput(8'h04);                        // illegal command
      endcase
    end
  endtask
endmodule
