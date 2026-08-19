// p8x_mdu.v -- stage 8a: the multiply-divide unit ($FF30-$FF3F).
//
// Hardware muldiv, BIT-EXACT to lib_g3d.c's software contract
// (STAGE8-DESIGN.md): q = (a*b)/c, signed, through a 32-bit intermediate,
// truncated toward zero, saturated at +/-32767; 0 when a or b is 0 (even
// with c = 0); +/-32767 when c is 0. The multiply is one combinational
// 16x16 pass (a DSP on the GW2AR-18); the divide is a 16-round restoring
// long division, one round per cycle -- BUSY for ~18 cycles, which is less
// than the CPU takes to reach its first MDQ read, but MDSTAT exists and
// software must poll it: depending on instruction timing instead of a busy
// flag is how the ACIA/GDATA class of hazard is born.
//
// Register conventions match the display's: operands are 16-bit pairs, a
// LOW write CLEARS the high byte, highs sit 9 above their lows. MDID reads
// 'M' ($4D) -- the presence probe; an absent unit floats the bus to $FF.
// MDQ while busy is stale (documented undefined).
//
// This datapath is the stage-8b geometry engine's heart, deliberately
// built and proven CPU-facing first.

module p8x_mdu (
  input             clk,
  input             rst,

  // CPU side, decoded by p8x_top: sel covers $FF30-$FF3F, a is the low nibble.
  input             sel,
  input      [3:0]  a,
  input             wr,
  input      [7:0]  wdata,
  output reg [7:0]  rdata
);

  reg [15:0] mda, mdb, mdc;                 // operands as written (signed)
  reg [15:0] mdq;                           // result (signed)
  reg        busy;
  reg [4:0]  cnt;                           // rounds remaining
  reg        sgn;                           // result sign (a^b^c signs)
  reg [15:0] rem;                           // division remainder accumulator
  reg [15:0] wlo;                           // product low word, shifting out
  reg [15:0] quo;                           // quotient, shifting in
  reg [15:0] dvs;                           // |c| latched for the rounds

  // Sign strip: 16-bit negate, so $8000 stays $8000 = 32768 unsigned --
  // the same wrap the software relies on. All values below are unsigned.
  wire [15:0] ua = mda[15] ? (~mda + 16'd1) : mda;
  wire [15:0] ub = mdb[15] ? (~mdb + 16'd1) : mdb;
  wire [15:0] uc = mdc[15] ? (~mdc + 16'd1) : mdc;
  wire [31:0] prod = ua * ub;               // the DSP multiply

  // One division round: 17-bit trial subtract of {rem, next product bit}.
  wire [16:0] trial = {rem, wlo[15]};
  wire        ge    = (trial >= {1'b0, dvs});

  // Final clamp + sign (applied in the cycle after the last round).
  wire [15:0] qclamp = (quo > 16'd32767) ? 16'd32767 : quo;

  always @(posedge clk) begin
    if (rst) begin
      mda <= 0; mdb <= 0; mdc <= 0; mdq <= 0;
      busy <= 0; cnt <= 0; sgn <= 0;
      rem <= 0; wlo <= 0; quo <= 0; dvs <= 0;
    end else begin
      if (busy) begin
        if (cnt != 0) begin
          rem <= ge ? (trial - {1'b0, dvs}) : trial[15:0];
          quo <= {quo[14:0], ge};
          wlo <= {wlo[14:0], 1'b0};
          cnt <= cnt - 5'd1;
        end else begin
          mdq  <= sgn ? (16'd0 - qclamp) : qclamp;
          busy <= 1'b0;
        end
      end

      if (sel && wr && !busy) begin
        case (a)
          4'h0: mda <= {8'd0, wdata};       // low write CLEARS the high byte
          4'h1: mdb <= {8'd0, wdata};
          4'h2: mdc <= {8'd0, wdata};
          4'h9: mda <= {wdata, mda[7:0]};
          4'hA: mdb <= {wdata, mdb[7:0]};
          4'hB: mdc <= {wdata, mdc[7:0]};
          4'h4: begin                       // MDGO
            sgn <= mda[15] ^ mdb[15] ^ mdc[15];
            if (ua == 0 || ub == 0)
              mdq <= 16'd0;                 // 0 operand: 0, even when c = 0
            else if (uc == 0)
              // /0 saturates; c = 0 contributes no sign, so a^b decides
              mdq <= (mda[15] ^ mdb[15]) ? (16'd0 - 16'd32767) : 16'd32767;
            else if (prod[31:16] >= uc)
              // quotient cannot fit 16 bits: saturate without dividing
              mdq <= (mda[15] ^ mdb[15] ^ mdc[15]) ? (16'd0 - 16'd32767)
                                                   : 16'd32767;
            else begin                      // 16 rounds, then clamp + sign
              rem  <= prod[31:16];
              wlo  <= prod[15:0];
              quo  <= 16'd0;
              dvs  <= uc;
              cnt  <= 5'd16;
              busy <= 1'b1;
            end
          end
          default: ;
        endcase
      end
    end
  end

  // Reads are combinational, like the display's.
  always @(*) begin
    case (a)
      4'h3:    rdata = mdq[7:0];
      4'hC:    rdata = mdq[15:8];
      4'h5:    rdata = {busy, 7'd0};        // MDSTAT
      4'h6:    rdata = 8'h4D;               // MDID: 'M'
      default: rdata = 8'hFF;
    endcase
  end

endmodule
