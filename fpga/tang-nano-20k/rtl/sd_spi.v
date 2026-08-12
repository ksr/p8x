// sd_spi.v -- microSD card in SPI mode: init, read block, write block.
//
// Presents a simple block interface upward:
//   rd_req/wr_req + lba  -> busy, then done/err
//   read : each incoming byte appears on d_out with d_stb (512 of them)
//   write: each byte is pulled from d_in via d_req (512 of them)
//
// The card is clocked slowly (~400 kHz) until initialisation completes, then
// fast (~6.75 MHz), which is what the SD spec requires -- cards only guarantee
// the 100-400 kHz range before they are in a known state.
//
// SDHC/SDXC cards address in BLOCKS, older SDSC cards address in BYTES. CMD58's
// CCS bit tells us which, and `blk_addr` records it; getting this wrong reads
// from an address 512x off, which looks like a corrupt filesystem rather than an
// obvious failure.

module sd_spi #(
  parameter CLKFREQ = 27_000_000,
  parameter DIV_SLOW = 34,          // ~400 kHz  (27M / (2*34))
  parameter DIV_FAST = 2            // ~6.75 MHz (27M / (2*2))
)(
  input             clk,
  input             rst,
  // block interface
  input             rd_req,
  input             wr_req,
  input      [31:0] lba,
  output reg        busy,
  output reg        done,
  output reg        err,
  output reg [7:0]  d_out,          // read data
  output reg        d_stb,
  input      [7:0]  d_in,           // write data
  output reg        d_req,
  output reg        ready,          // card initialised
  // SPI pins
  output reg        sd_clk,
  output reg        sd_mosi,
  input             sd_miso,
  output reg        sd_cs);

  // ---------------- byte-level SPI engine (mode 0) ----------------
  reg  [7:0] shift_o, shift_i;
  reg  [3:0] bitc;
  reg [15:0] divc;
  reg  [7:0] divn;
  reg        bbusy, bgo;
  reg  [7:0] btx;
  wire [7:0] brx = shift_i;

  always @(posedge clk) begin
    if (rst) begin
      sd_clk <= 1'b0; sd_mosi <= 1'b1; bbusy <= 1'b0; bitc <= 0; divc <= 0;
    end else if (bgo && !bbusy) begin
      shift_o <= btx; bitc <= 4'd8; bbusy <= 1'b1; divc <= 0;
      sd_clk  <= 1'b0; sd_mosi <= btx[7];
    end else if (bbusy) begin
      if (divc >= divn) begin
        divc <= 0;
        if (!sd_clk) begin
          sd_clk  <= 1'b1;                       // rising: card samples MOSI,
          shift_i <= {shift_i[6:0], sd_miso};    // we sample MISO
        end else begin
          sd_clk <= 1'b0;                        // falling: shift next bit out
          bitc   <= bitc - 1'b1;
          if (bitc == 4'd1) bbusy <= 1'b0;
          else begin shift_o <= {shift_o[6:0], 1'b0}; sd_mosi <= shift_o[6]; end
        end
      end else divc <= divc + 1'b1;
    end
  end

  // ---------------- command / init state machine ----------------
  localparam S_RESET=0, S_PWRUP=1, S_CMD=2, S_CMDW=3, S_R1=4, S_R1W=5,
             S_INIT=6,  S_TOKEN=7, S_DATA=8, S_CRC=9, S_DONE=10, S_ERR=11,
             S_WTOK=12, S_WDATA=13, S_WCRC=14, S_WRESP=15, S_WBUSY=16, S_IDLE=17;

  reg [4:0]  st, ret;
  reg [7:0]  cmd_idx, cmd_crc;
  reg [31:0] cmd_arg;
  reg [7:0]  r1;
  reg [9:0]  cnt;
  reg [15:0] tries;
  reg        blk_addr;               // 1 = SDHC/SDXC: lba is a block number
  reg        acmd41_stage;           // 0 = send CMD55, 1 = send CMD41
  reg        is_write;

  task spi_send(input [7:0] b);
    begin btx <= b; bgo <= 1'b1; end
  endtask

  always @(posedge clk) begin
    if (rst) begin
      st <= S_RESET; busy <= 1'b0; done <= 1'b0; err <= 1'b0; ready <= 1'b0;
      sd_cs <= 1'b1; bgo <= 1'b0; d_stb <= 1'b0; d_req <= 1'b0;
      divn <= DIV_SLOW; blk_addr <= 1'b0; cnt <= 0; tries <= 0;
    end else begin
      done <= 1'b0; d_stb <= 1'b0; d_req <= 1'b0;
      if (bgo && bbusy) bgo <= 1'b0;             // one-shot the byte engine

      case (st)
        // 80+ clocks with CS high puts the card into a known state
        S_RESET: begin
          busy <= 1'b1; sd_cs <= 1'b1; cnt <= 10; divn <= DIV_SLOW;
          st <= S_PWRUP;
        end
        S_PWRUP: if (!bbusy && !bgo) begin
          if (cnt == 0) begin
            sd_cs <= 1'b0;
            cmd_idx <= 8'd0; cmd_arg <= 32'd0; cmd_crc <= 8'h95;  // CMD0
            ret <= S_INIT; acmd41_stage <= 1'b0; tries <= 0;
            st  <= S_CMD;
          end else begin cnt <= cnt - 1'b1; spi_send(8'hFF); end
        end

        // ---- issue a 6-byte command frame, then read R1 ----
        S_CMD: if (!bbusy && !bgo) begin cnt <= 0; spi_send({2'b01, cmd_idx[5:0]}); st <= S_CMDW; end
        S_CMDW: if (!bbusy && !bgo) begin
          case (cnt)
            0: spi_send(cmd_arg[31:24]);
            1: spi_send(cmd_arg[23:16]);
            2: spi_send(cmd_arg[15:8]);
            3: spi_send(cmd_arg[7:0]);
            4: spi_send(cmd_crc);
            default: begin st <= S_R1; cnt <= 0; end
          endcase
          if (cnt <= 4) cnt <= cnt + 1'b1;
        end
        S_R1: if (!bbusy && !bgo) begin spi_send(8'hFF); st <= S_R1W; end
        S_R1W: if (!bbusy && !bgo) begin
          if (!brx[7]) begin r1 <= brx; st <= ret; cnt <= 0; end   // MSB clear = R1
          else if (cnt > 10'd200) begin st <= S_ERR; end
          else begin cnt <= cnt + 1'b1; st <= S_R1; end
        end

        // ---- initialisation ladder ----
        S_INIT: begin
          if (r1[0] && cmd_idx == 8'd0) begin                 // CMD0 -> idle
            cmd_idx <= 8'd8; cmd_arg <= 32'h000001AA; cmd_crc <= 8'h87;
            st <= S_CMD;                                     // CMD8
          end else if (cmd_idx == 8'd8) begin
            // R7 has 4 more bytes; flush them, then start ACMD41
            if (cnt < 4) begin
              if (!bbusy && !bgo) begin spi_send(8'hFF); cnt <= cnt + 1'b1; end
            end else begin
              cmd_idx <= 8'd55; cmd_arg <= 0; cmd_crc <= 8'hFF;
              acmd41_stage <= 1'b0; st <= S_CMD;
            end
          end else if (cmd_idx == 8'd55) begin
            cmd_idx <= 8'd41; cmd_arg <= 32'h40000000;        // HCS: we support SDHC
            cmd_crc <= 8'hFF; acmd41_stage <= 1'b1; st <= S_CMD;
          end else if (cmd_idx == 8'd41) begin
            if (r1 == 8'h00) begin                            // card is ready
              cmd_idx <= 8'd58; cmd_arg <= 0; cmd_crc <= 8'hFF; cnt <= 0;
              st <= S_CMD;
            end else if (tries > 16'd20000) st <= S_ERR;
            else begin
              tries   <= tries + 1'b1;
              cmd_idx <= 8'd55; cmd_arg <= 0; cmd_crc <= 8'hFF; st <= S_CMD;
            end
          end else if (cmd_idx == 8'd58) begin
            // OCR: bit 30 (CCS) of the first response byte pair -> block addressing
            if (cnt == 0) begin
              if (!bbusy && !bgo) begin spi_send(8'hFF); cnt <= cnt + 1'b1; end
            end else if (cnt == 1) begin
              blk_addr <= brx[6];                             // CCS
              if (!bbusy && !bgo) begin spi_send(8'hFF); cnt <= cnt + 1'b1; end
            end else if (cnt < 4) begin
              if (!bbusy && !bgo) begin spi_send(8'hFF); cnt <= cnt + 1'b1; end
            end else begin
              sd_cs <= 1'b1; divn <= DIV_FAST;
              ready <= 1'b1; busy <= 1'b0; st <= S_IDLE;
            end
          end else st <= S_ERR;
        end

        // ---- idle: wait for a block request ----
        S_IDLE: begin
          busy <= 1'b0;
          if (rd_req || wr_req) begin
            busy     <= 1'b1;
            err      <= 1'b0;
            is_write <= wr_req;
            sd_cs    <= 1'b0;
            cmd_idx  <= wr_req ? 8'd24 : 8'd17;
            cmd_arg  <= blk_addr ? lba : (lba << 9);
            cmd_crc  <= 8'hFF;
            ret      <= wr_req ? S_WTOK : S_TOKEN;
            cnt      <= 0; tries <= 0;
            st       <= S_CMD;
          end
        end

        // ---- read: wait for the 0xFE data token, then 512 bytes + CRC ----
        S_TOKEN: if (!bbusy && !bgo) begin
          if (r1 != 8'h00) st <= S_ERR;
          else if (brx == 8'hFE) begin cnt <= 0; spi_send(8'hFF); st <= S_DATA; end
          else if (tries > 16'd30000) st <= S_ERR;
          else begin tries <= tries + 1'b1; spi_send(8'hFF); end
        end
        S_DATA: if (!bbusy && !bgo) begin
          d_out <= brx; d_stb <= 1'b1;
          cnt   <= cnt + 1'b1;
          spi_send(8'hFF);
          if (cnt == 10'd511) begin cnt <= 0; st <= S_CRC; end
        end
        S_CRC: if (!bbusy && !bgo) begin
          if (cnt == 0) begin cnt <= 1; spi_send(8'hFF); end
          else st <= S_DONE;
        end

        // ---- write: token, 512 bytes, dummy CRC, response, busy-wait ----
        S_WTOK: if (!bbusy && !bgo) begin
          if (r1 != 8'h00) st <= S_ERR;
          else begin spi_send(8'hFE); cnt <= 0; d_req <= 1'b1; st <= S_WDATA; end
        end
        S_WDATA: if (!bbusy && !bgo) begin
          spi_send(d_in);
          cnt <= cnt + 1'b1;
          if (cnt == 10'd511) begin cnt <= 0; st <= S_WCRC; end
          else d_req <= 1'b1;
        end
        S_WCRC: if (!bbusy && !bgo) begin
          if (cnt < 2) begin spi_send(8'hFF); cnt <= cnt + 1'b1; end
          else begin spi_send(8'hFF); cnt <= 0; st <= S_WRESP; end
        end
        S_WRESP: if (!bbusy && !bgo) begin
          if ((brx & 8'h11) == 8'h01) begin                   // xxx0RRR1
            if ((brx & 8'h0E) == 8'h04) begin spi_send(8'hFF); st <= S_WBUSY; end
            else st <= S_ERR;                                 // CRC or write error
          end else if (cnt > 10'd200) st <= S_ERR;
          else begin cnt <= cnt + 1'b1; spi_send(8'hFF); end
        end
        S_WBUSY: if (!bbusy && !bgo) begin
          if (brx == 8'hFF) st <= S_DONE;                     // card released busy
          else spi_send(8'hFF);
        end

        S_DONE: begin sd_cs <= 1'b1; busy <= 1'b0; done <= 1'b1; st <= S_IDLE; end
        S_ERR:  begin sd_cs <= 1'b1; busy <= 1'b0; err  <= 1'b1; done <= 1'b1;
                      st <= ready ? S_IDLE : S_ERR; end
        default: st <= S_ERR;
      endcase
    end
  end
endmodule
