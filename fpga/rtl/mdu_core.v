// mdu_core.v -- THE muldiv datapath: q = (a*b)/c per the stage-8a contract
// (signed, 32-bit intermediate, truncate toward zero, saturate +/-32767,
// 0 when a or b is 0 even with c=0, +/-32767 when c is 0). Extracted from
// p8x_mdu.v (stage 8b) so the CPU-facing MDU and the geometry engine share
// ONE definition of the arithmetic in silicon -- the same reason the
// emulator has one mdu_exec(). One combinational DSP multiply; a 16-round
// restoring divider; busy ~17 cycles worst case, 1 for the early-outs.
//
// go is a 1-cycle pulse, honoured only when idle; a, b, c must be stable
// from go until busy falls; q is valid when busy is low.

module mdu_core (
  input             clk,
  input             rst,
  input             go,
  input      [15:0] a,
  input      [15:0] b,
  input      [15:0] c,
  output reg [15:0] q,
  output reg        busy
);

  reg [4:0]  cnt;
  reg        sgn;
  reg [15:0] rem, wlo, quo, dvs;

  // Sign strip: 16-bit negate, $8000 stays $8000 = 32768 unsigned -- the
  // same wrap the software relies on. Everything below is unsigned.
  wire [15:0] ua = a[15] ? (~a + 16'd1) : a;
  wire [15:0] ub = b[15] ? (~b + 16'd1) : b;
  wire [15:0] uc = c[15] ? (~c + 16'd1) : c;
  wire [31:0] prod = ua * ub;               // the DSP multiply

  wire [16:0] trial = {rem, wlo[15]};
  wire        ge    = (trial >= {1'b0, dvs});
  wire [15:0] qclamp = (quo > 16'd32767) ? 16'd32767 : quo;

  always @(posedge clk) begin
    if (rst) begin
      q <= 0; busy <= 0; cnt <= 0; sgn <= 0;
      rem <= 0; wlo <= 0; quo <= 0; dvs <= 0;
    end else if (busy) begin
      if (cnt != 0) begin
        rem <= ge ? (trial - {1'b0, dvs}) : trial[15:0];
        quo <= {quo[14:0], ge};
        wlo <= {wlo[14:0], 1'b0};
        cnt <= cnt - 5'd1;
      end else begin
        q    <= sgn ? (16'd0 - qclamp) : qclamp;
        busy <= 1'b0;
      end
    end else if (go) begin
      sgn <= a[15] ^ b[15] ^ c[15];
      if (ua == 0 || ub == 0)
        q <= 16'd0;                         // 0 operand: 0, even when c = 0
      else if (uc == 0)
        q <= (a[15] ^ b[15]) ? (16'd0 - 16'd32767) : 16'd32767;
      else if (prod[31:16] >= uc)
        q <= (a[15] ^ b[15] ^ c[15]) ? (16'd0 - 16'd32767) : 16'd32767;
      else begin
        rem  <= prod[31:16];
        wlo  <= prod[15:0];
        quo  <= 16'd0;
        dvs  <= uc;
        cnt  <= 5'd16;
        busy <= 1'b1;
      end
    end
  end

endmodule
