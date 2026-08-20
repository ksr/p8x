// p8x_mdu.v -- stage 8a: the CPU-facing multiply-divide unit ($FF30-$FF3F).
//
// Since stage 8b this is a thin REGISTER WRAPPER around mdu_core.v, which
// holds the one silicon definition of the muldiv contract (the geometry
// engine instantiates the same core). See mdu_core.v for the arithmetic and
// STAGE8-DESIGN.md for the whole story.
//
// Register conventions match the display's: operands are 16-bit pairs, a
// LOW write CLEARS the high byte, highs sit 9 above their lows. Write MDGO
// to start, poll MDSTAT bit 7, read MDQ low/high. MDID reads 'M' ($4D) --
// the presence probe; an absent unit floats the bus to $FF. MDQ while busy
// is stale (documented undefined). Writes while busy are dropped.

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

  reg  [15:0] mda, mdb, mdc;
  reg         go;
  wire [15:0] mdq;
  wire        busy;

  mdu_core CORE(.clk(clk), .rst(rst), .go(go),
                .a(mda), .b(mdb), .c(mdc), .q(mdq), .busy(busy));

  always @(posedge clk) begin
    go <= 1'b0;
    if (rst) begin
      mda <= 0; mdb <= 0; mdc <= 0;
    end else if (sel && wr && !busy && !go) begin
      case (a)
        4'h0: mda <= {8'd0, wdata};         // low write CLEARS the high byte
        4'h1: mdb <= {8'd0, wdata};
        4'h2: mdc <= {8'd0, wdata};
        4'h9: mda <= {wdata, mda[7:0]};
        4'hA: mdb <= {wdata, mdb[7:0]};
        4'hB: mdc <= {wdata, mdc[7:0]};
        4'h4: go  <= 1'b1;                  // MDGO
        default: ;
      endcase
    end
  end

  always @(*) begin
    case (a)
      4'h3:    rdata = mdq[7:0];
      4'hC:    rdata = mdq[15:8];
      4'h5:    rdata = {busy | go, 7'd0};   // MDSTAT: busy from the GO cycle
      4'h6:    rdata = 8'h4D;               // MDID: 'M'
      default: rdata = 8'hFF;
    endcase
  end

endmodule
