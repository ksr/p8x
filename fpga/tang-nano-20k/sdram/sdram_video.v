// sdram_video.v -- Stage 1: can a video scanout live off SDRAM?
//
// Stage 0 proved the memory works and that bandwidth is not the problem (3-7% of
// the bus at 480x272). What it did NOT prove is the thing that actually makes
// this hard: block RAM answers in one cycle, every cycle, so the existing
// scanout simply claims the port on phase 0 and knows the byte is there. SDRAM
// cannot promise that -- a read costs a row activate, a CAS latency and a
// precharge, and a refresh can land on top -- while a panel cannot stall. Miss
// a pixel and the picture tears.
//
// The answer is the standard one: never read SDRAM in the pixel's critical path.
// A whole line is fetched AHEAD of time into a small buffer, and the panel is
// fed from that buffer, which IS single-cycle block RAM. Two buffers ping-pong:
// while line N is displayed from one, line N+1 is fetched into the other.
//
// The budget, which is why this fits: a line is 560 pixel clocks at 9 MHz = 1680
// fabric cycles at 27 MHz. A line is 480 bytes = 120 reads on the 32-bit bus,
// and this controller costs ~5-7 cycles an access (it precharges every time --
// see below), so 600-840 cycles. Roughly half the line, with the other half left
// for refresh and, later, the drawing engine.
//
// THE MEASUREMENT, not just the picture: `underruns` counts lines where the
// fetch did not finish before the swap. A tearing screen is obvious, but a
// scanout that underruns once a second is not -- and would be a latent fault
// under a drawing engine competing for the same bus. Zero is the pass mark.
//
// 8 bits per pixel, 3-3-2 direct colour. Deliberately the WORST case of the
// realistic options: if 256 colours holds its timing then 16 certainly does, so
// the final depth stays an open decision rather than something this stage
// forecloses. No palette RAM either, which keeps the block-RAM claim honest.
//
// Note the vendored controller is not optimised for streaming: BURST_LEN is 1
// and it returns to IDLE (precharging) after every access, so it pays a full
// row activation per 4 pixels. A P8X controller that held a row open across a
// line would cut the fetch cost several-fold. That is an argument for stage 2
// writing its own -- not a problem for this stage, which has margin to spare.
module sdram_video #(
  parameter H_ACT = 480, H_FP = 50, H_SYNC = 0, H_BP = 30,   // 560 total (Sipeed)
  parameter V_ACT = 272, V_FP = 20, V_SYNC = 0, V_BP = 5,    // 297 total
  parameter [22:0] FB_BASE = 23'd0
)(
  input             clk,            // 27 MHz fabric clock
  input             rst,

  // SDRAM controller port (shared; this module only ever reads)
  output reg        rd,           // HELD until ack (arbiter request/ack)
  input             ack,
  output reg [22:0] addr,
  input      [31:0] dout32,
  input             data_ready,
  output            want_bus,       // 1 while a line fetch is outstanding

  // to the panel
  output reg        pclk,
  output reg        de,
  output reg [4:0]  r,
  output reg [5:0]  g,
  output reg [4:0]  b,

  output reg [15:0] underruns,
  output            frame_tick      // 1-cycle pulse at the top of a frame
);
  localparam H_TOT   = H_ACT + H_FP + H_SYNC + H_BP;
  localparam V_TOT   = V_ACT + V_FP + V_SYNC + V_BP;
  localparam STRIDE  = H_ACT;                 // 8 bpp -> one byte per pixel
  localparam WORDS   = H_ACT / 4;             // 120 32-bit reads per line

  // ---- line buffers ---------------------------------------------------------
  // 2 x 128 words of 32 bits = 1024 bytes, one BSRAM block. Word-wide rather
  // than byte-wide so a fetched word lands in one write instead of four.
  reg [31:0] lbuf [0:255];
  reg        bank;                            // buffer currently being DISPLAYED

  // ---- timing ---------------------------------------------------------------
  reg [1:0] ph;                               // 0,1,2 -> 9 MHz pixel rate
  reg [9:0] px, py;

  wire      eol = (px == H_TOT-1) && (ph == 2'd2);
  // Exposed rather than let the top reach into this instance: yosys does not
  // support hierarchical references, and a testbench can still peek freely.
  assign frame_tick = (px == 10'd0) && (py == 10'd0) && (ph == 2'd0);

  // The pixel being fetched from the line buffer is one ahead of the one shown,
  // exactly as in video_rgb.v: block RAM is synchronous, so the address has to
  // be presented a cycle early.
  wire [9:0] nx = (px == H_TOT-1) ? 10'd0 : px + 10'd1;
  wire [9:0] ax = (nx < H_ACT) ? nx : 10'd0;

  reg [31:0] lb_q;
  always @(posedge clk) lb_q <= lbuf[{bank, ax[8:2]}];
  wire [7:0] pixel = (ax[1:0] == 2'd0) ? lb_q[7:0]   :
                     (ax[1:0] == 2'd1) ? lb_q[15:8]  :
                     (ax[1:0] == 2'd2) ? lb_q[23:16] : lb_q[31:24];

  // 3-3-2 direct colour, spread over the panel's RGB565. Low bits copy the high
  // ones so full scale really is full scale, the same trick video_rgb.v uses.
  wire [4:0] px_r = {pixel[7:5], pixel[7:6]};
  wire [5:0] px_g = {pixel[4:2], pixel[4:2]};
  wire [4:0] px_b = {pixel[1:0], pixel[1:0], pixel[1]};

  reg        nxt_de;
  reg [4:0]  nxt_r, nxt_b;
  reg [5:0]  nxt_g;

  always @(posedge clk) begin
    if (rst) begin
      ph <= 0; px <= 0; py <= 0; pclk <= 0; de <= 0;
      r <= 0; g <= 0; b <= 0; nxt_de <= 0;
    end else case (ph)
      // Present the pixel fetched during the previous period, and drop pclk.
      2'd0: begin
        ph <= 2'd1; pclk <= 1'b0;
        de <= nxt_de; r <= nxt_r; g <= nxt_g; b <= nxt_b;
      end
      // The line-buffer word has settled; latch what the next period shows.
      2'd1: begin
        ph <= 2'd2;
        nxt_de <= (nx < H_ACT) && ((px == H_TOT-1 ? (py == V_TOT-1 ? 10'd0 : py+10'd1) : py) < V_ACT);
        nxt_r <= px_r; nxt_g <= px_g; nxt_b <= px_b;
      end
      // Data has been stable two cycles (~74 ns); clock it into the panel now.
      // Raising pclk in the same cycle the RGB lines change is the bug that
      // doubled vertical lines on this panel once already -- see video_rgb.v.
      default: begin
        ph   <= 2'd0;
        pclk <= 1'b1;
        px   <= (px == H_TOT-1) ? 10'd0 : px + 10'd1;
        if (px == H_TOT-1) py <= (py == V_TOT-1) ? 10'd0 : py + 10'd1;
      end
    endcase
  end

  // ---- line fetch -----------------------------------------------------------
  // Fetches the line that will be displayed NEXT into the buffer that is not
  // being displayed. Kicked off at every end-of-line.
  reg  [7:0]  fw;                  // words fetched so far this line (0..WORDS)
  reg         inflight;            // a read is taken but not yet answered
  reg         fetching;
  reg         primed;              // a fetch has been started at least once
  reg  [22:0] faddr;

  assign want_bus = fetching;

  wire [9:0] next_line = (py == V_TOT-1) ? 10'd0 : py + 10'd1;
  wire [9:0] fetch_line = (next_line < V_ACT) ? next_line : 10'd0;

  always @(posedge clk) begin
    // The arbiter takes a request when it can, which may not be this cycle, so
    // rd is a LEVEL held until ack -- not the one-cycle pulse the bare
    // controller wanted. Pulsing it here would drop any fetch that arrived
    // while the engine or refresh held the bus, and a dropped fetch is a
    // dropped scanline.
    rd <= rd & ~ack;
    if (ack) inflight <= 1;            // taken by the arbiter, answer still to come
    if (rst) begin
      fetching <= 0; fw <= 0; bank <= 0; underruns <= 0; primed <= 0;
      // rd MUST be reset. It became self-referential (rd <= rd & ~ack) when
      // this moved to the arbiter's request/ack, and a self-referential reg
      // with no reset is X forever in simulation -- which is why this bench saw
      // nothing fetched at all. On hardware the flop powers up at 0 and it
      // limps along, so the fault is invisible on the board and total in sim.
      rd <= 0; inflight <= 0;
    end else if (eol) begin
      // Swap, and judge the fetch that was supposed to have finished by now.
      // `primed` suppresses the very first line, where nothing has been asked
      // for yet -- otherwise every reset would report a phantom underrun.
      if (primed && (fetching || fw != WORDS[7:0]))
        if (underruns != 16'hFFFF) underruns <= underruns + 1'b1;
      bank     <= ~bank;
      primed   <= 1;
      // Explicit width. `fetch_line * STRIDE` in a narrow context is how this
      // project already lost the top of a framebuffer address once: a y*60 that
      // wrapped inside 13 bits and folded the bottom of the screen onto the top.
      faddr    <= FB_BASE + ({13'd0, fetch_line} * STRIDE);
      fw       <= 0;
      fetching <= 1;
      inflight <= 0;
    end else if (fetching) begin
      if (data_ready) begin
        lbuf[{~bank, fw[6:0]}] <= dout32;
        inflight <= 0;
        if (fw == WORDS[7:0]-1) begin fetching <= 0; fw <= WORDS[7:0]; end
        else                          fw <= fw + 1'b1;
      end else if (!rd && !inflight) begin
        // `inflight` is NOT optional. ack means the arbiter TOOK the request,
        // not that it answered it -- and rd clears on ack, so testing !rd alone
        // fires a second read for the same word while the first is still in
        // flight. The extra answer then lands at the NEXT fw, so a line ends up
        // holding every other word twice and half its pixels never arrive.
        // On the panel that is a doubled column at the left edge.
        addr <= faddr + {13'd0, fw, 2'd0};
        rd   <= 1;
      end
    end
  end
endmodule
