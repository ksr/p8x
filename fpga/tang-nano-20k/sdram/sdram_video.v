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

  // p8x_sdram stream port (this module only ever reads). One st_go per line;
  // issuing the next line's st_go while the previous fetch is still running is
  // the ABORT the controller defines for exactly this client: the panel has
  // moved on and the stale line's remaining words are worthless.
  output reg        st_go,
  output reg [22:0] st_addr,
  output     [8:0]  st_words,
  input             st_valid,
  input      [31:0] st_data,
  input             st_done,

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
  // Stride 1024, not 960 (STAGE6-DESIGN.md): a 960-byte 16 bpp line at a 1024
  // stride starts every line on an SDRAM row boundary -- ONE activation per
  // line -- and makes the line address {y, 10'b0}, pure wiring.
  localparam STRIDE  = 1024;
  localparam WORDS   = H_ACT / 2;             // 240 32-bit reads per line

  // ---- line buffers ---------------------------------------------------------
  // 2 x 240 words of 32 bits = 1,920 bytes in a 512x32 array -- still ONE
  // BSRAM (16Kbit of data). Word-wide so a fetched word lands in one write.
  reg [31:0] lbuf [0:511];
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
  // The pixel fetched during the LAST period of a line belongs to the NEXT
  // line, and the next line lives in the other buffer -- but the swap does not
  // happen until end-of-line, one phase later. Reading `bank` there hands back
  // the previous line's first pixel, which is why column 0 of every row showed
  // stale data while columns 1..479 were perfect.
  wire rd_bank = bank ^ (px == H_TOT-1);
  always @(posedge clk) lb_q <= lbuf[{rd_bank, ax[8:1]}];
  // RGB565: the pixel IS the panel's wiring. Half-word select, no palette,
  // no expansion -- the bits go straight to the pins.
  wire [15:0] pixel = ax[0] ? lb_q[31:16] : lb_q[15:0];

  wire [4:0] px_r = pixel[15:11];
  wire [5:0] px_g = pixel[10:5];
  wire [4:0] px_b = pixel[4:0];

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
  // being displayed. One st_go per end-of-line; the controller streams the
  // words back and the only bookkeeping left HERE is writing them down in
  // order. The request/ack/inflight machinery this section used to carry
  // lived to work around a word-at-a-time controller, and went with it.
  reg  [8:0]  fw;                  // words landed this line (0..WORDS)
  reg         fetching;            // st_go issued, st_done not yet seen
  reg         primed;              // a fetch has been started at least once
  // The flush window: for two cycles after eol, arriving st_valid words are
  // DISCARDED. They can only be the tail of an aborted fetch (in-flight CAS
  // answers the controller could not retract), and writing them would land at
  // fw=0 and shift the whole replacement line by one. A genuine word from the
  // new stream cannot arrive this early -- the controller has an activate and
  // the CAS latency to get through first.
  reg  [1:0]  flush;

  assign st_words = WORDS[8:0];

  // A fetch started at the end of line py runs DURING line py+1 and is
  // displayed during line py+2 -- because the swap at that same end-of-line
  // hands over the buffer filled during py, not the one about to be filled. So
  // the line to fetch is py+2, not py+1. Fetching py+1 puts every row on the
  // panel one line late: the top row is duplicated (it is still there while the
  // pipeline fills) and the last row falls off the bottom, which is exactly how
  // it presented -- a thick top line and no bottom line on a full-screen box.
  // Which framebuffer line the NEXT fetch should load, tracked explicitly
  // rather than derived from py. Deriving it needed modular arithmetic whose
  // wrap boundary disagreed with the blanking clamp, and the two together were
  // wrong by one in opposite directions depending on the constant -- which is a
  // sign the expression was encoding two different ideas at once.
  //
  // A fetch issued at end-of-line is displayed TWO swaps later: the swap at
  // that same end-of-line hands over the buffer filled during the previous
  // line, not the one about to be filled. The counter is primed during vertical
  // blanking so it reaches 0 the right number of lines before active video.
  // (The row lag this section once documented is fixed and verified on
  // hardware -- see 75e166a and the bench's row-mapping check.)
  reg [9:0] nextf;

  always @(posedge clk) begin
    st_go <= 1'b0;
    if (flush != 2'd0) flush <= flush - 2'd1;

    // Words stream in; the only job left is writing them down in order. The
    // index reads ~bank BEFORE the eol swap below (non-blocking), so a word
    // landing exactly at eol still goes to the buffer its fetch belongs to.
    if (st_valid && flush == 2'd0 && fw != WORDS[8:0]) begin
      lbuf[{~bank, fw[7:0]}] <= st_data;
      fw <= fw + 1'b1;
    end
    if (st_done) fetching <= 0;

    if (rst) begin
      fetching <= 0; fw <= 0; bank <= 0; underruns <= 0; primed <= 0;
      st_go <= 0; nextf <= 0; flush <= 0;
    end else if (eol) begin
      // Swap, and judge the fetch that was supposed to have finished by now.
      // `primed` suppresses the very first line, where nothing has been asked
      // for yet -- otherwise every reset would report a phantom underrun.
      // st_done is the fetch's word; fw is the audit of what actually landed.
      if (primed && (fetching || fw != WORDS[8:0]))
        if (underruns != 16'hFFFF) underruns <= underruns + 1'b1;
      bank     <= ~bank;
      primed   <= 1;
      // Stride 1024 makes the line address pure wiring: {nextf, 10 zeros}.
      // The y*STRIDE multiply -- and the 13-bit-wrap class of bugs this
      // project paid for twice -- is gone rather than survived.
      st_addr  <= FB_BASE + {3'd0, nextf, 10'd0};
      st_go    <= 1'b1;                // starts the fetch -- or aborts a stale one
      // prime so that the fetch two lines before active video loads line 0
      if (py == V_TOT-3) nextf <= 10'd0;
      else if (nextf < V_ACT-1) nextf <= nextf + 10'd1;
      fw       <= 0;
      fetching <= 1;
      flush    <= 2'd2;                // discard any aborted fetch's tail
    end
  end
endmodule
