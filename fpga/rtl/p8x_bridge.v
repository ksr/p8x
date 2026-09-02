// p8x_bridge.v -- the card-edge bridge FSM (CARD-EDGE-DESIGN.md, v1).
//
// Sits where the CPU used to: decodes the host's serial protocol and
// drives the geometry engine's GL register port -- the ONE graphics
// interface since the single-interface migration closed the $FF20
// device door (device-window idx are dead: writes are swallowed,
// reads answer $FF like a floating bus).
// Byte-level interface (rxd/rxv in, txd/txs/txb out) so it neither
// knows nor cares that a UART is behind it -- the card top wires the
// real uart_rx/uart_tx, the bench pokes bytes directly.
//
//   $00           PING    -> "P8XG" + VERSION
//   $80|idx <v>   WRITE   -> (nothing)
//   $40|idx       READ    -> one byte
//   $01 <n> <b..> BURST   -> $06 after the last byte is ACCEPTED by
//                            the GL FIFO. The host sends the chunk
//                            blind (<=64), so the bytes land in a
//                            local buffer as they arrive and DRAIN to
//                            GLDATA under FIFO backpressure in
//                            parallel; the ack is the flow control.
//   $02           STATUS  -> GLSTAT (fast-poll alias, no pop)
//
// idx = I/O address - $FF20: $30-$37 the GL port; $00-$0F was the 2D
// device, retired. BRIDGEV ($35) and BRIDGID ($36) answer HERE -- they
// identify the bridge front-end, absent on the all-in-one build and on
// a future TTL-bus card. Unknown commands are swallowed in one byte.
module p8x_bridge(
  input             clk,
  input             rst,

  // host byte stream (uart_rx / uart_tx shaped)
  input      [7:0]  rxd,
  input             rxv,
  output reg [7:0]  txd,
  output reg        txs,
  input             txb,

  // the geometry engine's GL port
  output reg        gl_sel,
  output reg        gl_wr,
  output reg        gl_rd,
  input      [7:0]  gl_rdata,

  // address/data (as mem_addr[3:0]/mem_dout were)
  output reg [3:0]  a,
  output reg [7:0]  wdata
);
  localparam [7:0] VERSION = 8'd1;

  localparam I=0,   WV=1,  BN=2,  BD=3,  RD1=4, TX=5;
  reg [2:0] st;
  reg [5:0] idx;                  // target register of WRITE/READ
  reg [6:0] cnt;                  // burst length
  reg [7:0] brx [0:63];           // burst landing buffer
  reg [6:0] brw, brd;             // arrived / drained counts
  reg       bph;                  // drain sub-phase: peek, then push
  reg [7:0] tq [0:4];             // reply queue (PING is 5 bytes)
  reg [2:0] tqn, tqi;

  wire idx_gl  = (idx[5:3] == 3'b110);           // $30-$37

  always @(posedge clk) begin
    // strobes are one-shot; selects idle low unless a state drives them
    gl_sel <= 0; gl_wr <= 0; gl_rd <= 0;
    txs <= 0;

    if (rst) begin
      st <= I; tqn <= 0; tqi <= 0; brw <= 0; brd <= 0; bph <= 0;
    end else case (st)

      I: if (rxv) begin
        if (rxd == 8'h00) begin                       // PING
          tq[0] <= "P"; tq[1] <= "8"; tq[2] <= "X"; tq[3] <= "G";
          tq[4] <= VERSION; tqn <= 3'd5; tqi <= 0; st <= TX;
        end
        else if (rxd == 8'h01) st <= BN;              // BURST
        else if (rxd == 8'h02) begin                  // STATUS = peek GLSTAT
          idx <= 6'h31; gl_sel <= 1; a <= 4'h1; st <= RD1;
        end
        else if (rxd[7]) begin                        // WRITE
          idx <= rxd[5:0]; st <= WV;
        end
        else if (rxd[6]) begin                        // READ
          idx <= rxd[5:0];
          if (rxd[5:0] == 6'h35 || rxd[5:0] == 6'h36) begin
            tq[0] <= (rxd[5:0] == 6'h35) ? VERSION : "B";
            tqn <= 3'd1; tqi <= 0; st <= TX;
          end else begin
            // present the address a cycle ahead of the strobe so the
            // combinational rdata mux is settled when we sample
            a <= rxd[3:0];
            gl_sel <= (rxd[5:3] == 3'b110);
            st <= RD1;
          end
        end
        // anything else: swallowed
      end

      WV: if (rxv) begin                              // the write value
        wdata <= rxd; a <= idx[3:0];
        gl_sel <= idx_gl;  gl_wr <= idx_gl;
        st <= I;                     // off-window (device idx included): dropped
      end

      BN: if (rxv) begin
        cnt <= (rxd == 0 || rxd > 8'd64) ? 7'd64 : rxd[6:0];
        brw <= 0; brd <= 0; bph <= 0;
        if (rxd == 0) begin                           // degenerate: ack now
          tq[0] <= 8'h06; tqn <= 3'd1; tqi <= 0; st <= TX;
        end else st <= BD;
      end

      BD: begin
        if (rxv && brw < cnt) begin                   // land arrivals
          brx[brw[5:0]] <= rxd; brw <= brw + 7'd1;
        end
        if (brd == cnt) begin                         // fully drained: ack
          tq[0] <= 8'h06; tqn <= 3'd1; tqi <= 0; st <= TX;
        end else if (!bph) begin                      // peek FIFO-full
          gl_sel <= 1; a <= 4'h1; bph <= 1;
        end else begin                                // push one if room
          bph <= 0;
          if (brd < brw && !gl_rdata[7]) begin
            gl_sel <= 1; gl_wr <= 1; a <= 4'h0;
            wdata <= brx[brd[5:0]]; brd <= brd + 7'd1;
          end
        end
      end

      RD1: begin                                      // sample, queue reply
        gl_sel <= idx_gl || idx == 6'h31;             // hold sel this cycle
        a <= idx[3:0];
        gl_rd <= idx_gl;                              // pop semantics where
                                                      //   the window has them
        tq[0] <= idx_gl ? gl_rdata : 8'hFF;           // device idx: floating $FF
        tqn <= 3'd1; tqi <= 0; st <= TX;
      end

      TX: if (tqi == tqn) st <= I;
          else if (!txb && !txs) begin
            txd <= tq[tqi]; txs <= 1; tqi <= tqi + 3'd1;
          end

      default: st <= I;
    endcase
  end
endmodule
