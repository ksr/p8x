// p8x_sdram.v -- the P8X SDRAM controller: row-open streaming reads.
//
// STAGE 6 STEP 1 (see STAGE6-DESIGN.md). The vendored controller precharges
// after every access, so a word costs ~5-7 cycles whoever asks. That was fine
// for the 8 bpp scanout (120 words in a 1,680-cycle line) and is arithmetic
// death for 16 bpp (240 words -> 1,200-1,680 cycles). This controller opens a
// row once and issues a CAS every cycle, so a line fetch costs roughly its
// word count plus small change -- which is what makes the depth free.
//
// TWO PORTS, one philosophy each:
//
//   WORD port -- the drawing engine. Interface and cycle-for-cycle timing are
//   the vendored controller's, deliberately, including its two documented
//   traps (busy rises the cycle AFTER a command pulse; on reads busy falls in
//   the SAME cycle data_ready rises). sdram_arb encodes those rules once and
//   gfx_mem talks through it; copying the timing means neither changes and
//   the existing model stays honest. Accesses auto-precharge exactly as
//   before. A row-hit fast path for the engine is deliberately NOT here yet
//   -- it is an optimisation with its own state to get wrong, and step 1's
//   deliverable is the stream.
//
//   STREAM port -- the scanout. st_go latches a byte address and a word
//   count; the controller activates the row and issues a READ every cycle,
//   answering st_valid/st_data one word a cycle after the CAS latency, then
//   pulsing st_done. Crossing a row boundary re-activates transparently (a
//   480-byte 8 bpp line is not row-aligned; stage 6's stride 1024 makes it
//   so, but the stream does not get to rely on that). st_go while a stream
//   is running ABORTS the old stream and starts the new one -- that is the
//   underrun case, where the panel has moved on and the stale line's
//   remaining words are worthless; the aborted stream never pulses st_done.
//
// REFRESH IS INTERNAL. The vendored design made it the caller's job, and the
// caller got it right -- but a forgotten refresh is silent data rot, so this
// controller owns its own timer: one AUTO-REFRESH per REF_INTERVAL cycles,
// 400 at 27 MHz against the 421 the 4096-per-64ms spec allows. The arbiter's
// refresh master and p8x_top's timer retire.
//
// THE STREAM YIELDS. An unbroken 240-word burst would starve the engine and
// sit on the refresh deadline, so the run is chopped into CHUNK-word pieces.
// At each chunk boundary the row is closed and: a due refresh runs first
// (hard deadline); then busy drops for two cycles, which is exactly the
// window sdram_arb needs to see !busy and land one engine word-op; then the
// stream re-activates and continues. Cost when nobody wants in: ~10 cycles a
// chunk, ~150 a line at 16 bpp -- noise against the 1,680 budget. The
// engine's worst-case wait shrinks from "the whole fetch" to about a chunk.
//
// THE WINDOW HAS A TRAP, and SGRAB is its answer: the arbiter samples !busy
// and fires its one-cycle pulse on the NEXT edge, so a pulse can arrive in
// the very cycle the window closes. Leaving SNEXT straight to the stream
// would lose that pulse -- and a lost read pulse is the arbiter deadlock
// documented in sdram_arb.v (owner set, answer never comes). So the exit
// path raises busy and then passes through SGRAB for one cycle, which exists
// solely to catch the straggler.
//
// Timing parameters are the vendored ones for this clock (27 MHz): CAS 2,
// tRP/tRCD 1 cycle, tRC 4, tWR 2. tRAS-min (2 cycles) is satisfied by
// construction: a stream row lives at least ACTIVATE + tRCD + a CAS + drain.
`timescale 1ns/1ps
module p8x_sdram #(
    parameter         FREQ = 27_000_000,
    parameter [3:0]   CAS  = 4'd2,
    parameter [3:0]   T_WR = 4'd2,
    parameter [3:0]   T_MRD= 4'd2,
    parameter [3:0]   T_RP = 4'd1,
    parameter [3:0]   T_RCD= 4'd1,
    parameter [3:0]   T_RC = 4'd4,
    parameter [15:0]  REF_INTERVAL = 16'd400,
    parameter [8:0]   CHUNK = 9'd32
)(
    // ---- SDRAM side (same pins as the vendored controller)
    inout      [31:0] SDRAM_DQ,
    output reg [10:0] SDRAM_A,
    output reg  [1:0] SDRAM_BA,
    output            SDRAM_nCS,
    output reg        SDRAM_nWE,
    output reg        SDRAM_nRAS,
    output reg        SDRAM_nCAS,
    output            SDRAM_CLK,
    output            SDRAM_CKE,
    output reg  [3:0] SDRAM_DQM,

    // ---- logic side
    input             clk,
    input             clk_sdram,          // 180/225-degree copy, straight to the pin
    input             resetn,

    // word port (vendored-compatible; no refresh input -- that is internal now)
    input             rd,
    input             wr,
    input             wr_word,
    input      [22:0] addr,
    input       [7:0] din,
    output      [7:0] dout,
    output     [31:0] dout32,
    output reg        data_ready,
    output reg        busy,

    // stream port
    input             st_go,              // 1-cycle pulse; a new one aborts a running stream
    input      [22:0] st_addr,            // byte address, word-aligned
    input       [8:0] st_words,           // 1..256
    output reg        st_valid,           // 1 cycle per word, st_data is yours
    output     [31:0] st_data,
    output reg        st_done             // 1-cycle pulse after the last word
);

  // ---- declarations, all up front --------------------------------------------
  localparam CMD_SetModeReg  = 3'b000;
  localparam CMD_AutoRefresh = 3'b001;
  localparam CMD_PreCharge   = 3'b010;
  localparam CMD_BankActivate= 3'b011;
  localparam CMD_Write       = 3'b100;
  localparam CMD_Read        = 3'b101;
  localparam CMD_NOP         = 3'b111;
  localparam [10:0] MODE_REG = {4'b0, CAS[2:0], 1'b0, 3'b0};  // sequential, BL=1

  localparam INIT   = 4'd0,  CONFIG = 4'd1,  IDLE  = 4'd2,
             WREAD  = 4'd3,  WWRITE = 4'd4,  REF   = 4'd5,
             SACT   = 4'd6,  SRUN   = 4'd7,  SDRAIN= 4'd8,
             SCLOSE = 4'd9,  SNEXT  = 4'd10, SACT2 = 4'd11,
             SGRAB  = 4'd12;

  reg [3:0]  state;
  reg [3:0]  cycle;

  reg        dq_oen;
  reg [31:0] dq_out;
  reg [1:0]  off;
  reg [7:0]  dout_buf;

  reg [7:0]  din_buf;                     // word-op latches (vendored)
  reg        word_buf;
  reg [22:0] addr_buf;

  reg [20:0] s_wptr;                      // running stream position, WORD address:
                                          //   {bank[1:0], row[10:0], col[7:0]}
  reg [8:0]  s_left;
  reg [8:0]  s_chunk;
  reg [20:0] n_wptr;                      // latched st_go, not yet started
  reg [8:0]  n_left;
  reg        s_pend;

  reg        p0, p1;                      // CAS-deep issue pipeline for st_valid

  // A latched word-op pulse, and the invariant that makes ONE latch enough.
  //
  // The client fires rd/wr the cycle after it saw !busy. Once this controller
  // does autonomous work (internal refresh, streams), it can start something
  // in that one-cycle gap, and the pulse lands mid-operation. Latching it is
  // half the answer; the other half is that BUSY STAYS HIGH UNTIL THE LATCHED
  // OP COMPLETES. Without that, the client's wait-for-!busy returns when the
  // BLOCKING op finishes, it believes its own op is done, fires the next one
  // -- and the second pulse overwrites the latch, silently losing a write.
  // The bench caught exactly that: three writes lost at refresh cadence, X on
  // read-back. With busy held, !busy means "your op is done" again -- the
  // vendored contract, exactly -- and only the sample-then-fire race can ever
  // fill the latch, whose client then blocks. One deep is provably enough.
  reg        q_rd, q_wr, q_word;
  reg [22:0] q_addr;
  reg [7:0]  q_din;
  reg        resume;                      // a service op returns to the stream
  reg [15:0] ref_cnt;
  reg        ref_due;
  reg [1:0]  win;

  reg [14:0] rst_cnt;                     // 200 us power-on delay (vendored)
  reg        rst_done, rst_done_p1, cfg_now;

  // ---- DQ and the shared data-path idiom -------------------------------------
  assign SDRAM_DQ  = dq_oen ? 32'hzzzz_zzzz : dq_out;
  wire [31:0] dq_in = SDRAM_DQ;
  assign SDRAM_CLK = clk_sdram;
  assign SDRAM_CKE = 1'b1;
  assign SDRAM_nCS = 1'b0;
  assign dout32    = dq_in;
  assign st_data   = dq_in;

  wire [7:0] next_dout = off == 0 ? dq_in[7:0]   :
                         off == 1 ? dq_in[15:8]  :
                         off == 2 ? dq_in[23:16] : dq_in[31:24];
  assign dout = data_ready ? next_dout : dout_buf;

  wire [1:0]  s_bank = s_wptr[20:19];
  wire [10:0] s_row  = s_wptr[18:8];
  wire [7:0]  s_col  = s_wptr[7:0];

  // what an acceptance point sees: the live pulse, or the latched one
  wire        e_rd   = rd | q_rd;
  wire        e_wr   = wr | q_wr;
  wire [22:0] e_addr = (q_rd | q_wr) ? q_addr : addr;
  wire [7:0]  e_din  = (q_rd | q_wr) ? q_din  : din;
  wire        e_word = (q_rd | q_wr) ? q_word : wr_word;

  always @(posedge clk) begin
    cycle <= cycle == 4'd15 ? 4'd15 : cycle + 4'd1;
    {SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} <= CMD_NOP;
    st_valid   <= p1;
    p1         <= p0;
    p0         <= 1'b0;
    st_done    <= 1'b0;
    data_ready <= 1'b0;

    // the refresh clock never stops
    if (ref_cnt == REF_INTERVAL) begin ref_due <= 1'b1; ref_cnt <= 0; end
    else ref_cnt <= ref_cnt + 1'b1;

    // st_go always latches; the FSM picks it up at its next safe point. A
    // pulse during a running stream leaves s_pend set, which SRUN treats as
    // one more reason to wind down -- that is the abort.
    if (st_go) begin
      n_wptr <= st_addr[22:2];
      n_left <= st_words;
      s_pend <= 1'b1;
    end

    // a pulse the FSM cannot consume this edge is latched, never lost
    if ((rd | wr) && state != IDLE && state != SNEXT && state != SGRAB) begin
      q_rd <= rd; q_wr <= wr; q_addr <= addr; q_din <= din; q_word <= wr_word;
    end

    case (state)
      INIT: if (cfg_now) begin state <= CONFIG; cycle <= 0; busy <= 1'b1; end

      // vendored configuration sequence, verbatim
      CONFIG: begin
        if (cycle == 4'd0) begin
          {SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} <= CMD_PreCharge;
          SDRAM_A[10] <= 1'b1;
        end
        if (cycle == T_RP)
          {SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} <= CMD_AutoRefresh;
        if (cycle == T_RP+T_RC)
          {SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} <= CMD_AutoRefresh;
        if (cycle == T_RP+T_RC+T_RC) begin
          {SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} <= CMD_SetModeReg;
          SDRAM_A <= MODE_REG;
        end
        if (cycle == T_RP+T_RC+T_RC+T_MRD) begin
          state <= IDLE; busy <= 1'b0;
        end
      end

      // Order of acceptance, and the reasoning is load-bearing:
      //   1. a LIVE rd/wr pulse -- fired because the client just saw !busy,
      //      lost if not taken this edge, and a lost pulse is the deadlock
      //      in sdram_arb's header;
      //   2. a due refresh -- hard deadline, but sticky, so it only needs to
      //      outrank things that can wait;
      //   3. a LATCHED pulse -- already safe in the latch, so it CAN wait.
      //      Ranking it above refresh looks harmless and is not: a client
      //      saturating the word port phase-locks against the latch (each
      //      op's successor lands during the op and is consumed the instant
      //      IDLE returns), and refresh then starves indefinitely. The bench
      //      caught that as a 1,375-cycle refresh gap;
      //   4. a pending stream.
      IDLE: begin
        if (rd | wr) begin
          {SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} <= CMD_BankActivate;
          SDRAM_BA <= addr[22:21];
          SDRAM_A  <= addr[20:10];
          addr_buf <= addr;
          if (wr) begin din_buf <= din; word_buf <= wr_word; end
          resume <= 1'b0;
          state <= rd ? WREAD : WWRITE; cycle <= 4'd1; busy <= 1'b1;
        end else if (ref_due) begin
          {SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} <= CMD_AutoRefresh;
          ref_due <= 1'b0; resume <= 1'b0;
          state <= REF; cycle <= 4'd1; busy <= 1'b1;
        end else if (q_rd | q_wr) begin
          {SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} <= CMD_BankActivate;
          SDRAM_BA <= q_addr[22:21];
          SDRAM_A  <= q_addr[20:10];
          addr_buf <= q_addr;
          if (q_wr) begin din_buf <= q_din; word_buf <= q_word; end
          q_rd <= 1'b0; q_wr <= 1'b0;
          resume <= 1'b0;
          state <= q_rd ? WREAD : WWRITE; cycle <= 4'd1; busy <= 1'b1;
        end else if (s_pend) begin
          if (n_left == 9'd0) s_pend <= 1'b0;   // a zero-length stream is a no-op,
                                                // not a 512-word runaway
          else begin
            {SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} <= CMD_BankActivate;
            SDRAM_BA <= n_wptr[20:19];
            SDRAM_A  <= n_wptr[18:8];
            s_wptr <= n_wptr; s_left <= n_left; s_pend <= 1'b0;
            s_chunk <= CHUNK;
            state <= SACT; cycle <= 4'd1; busy <= 1'b1;
          end
        end
      end

      // ---- word read/write: the vendored sequences, cycle for cycle ----------
      WREAD: begin
        if (cycle == T_RCD) begin
          {SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} <= CMD_Read;
          SDRAM_A[10] <= 1'b1;                          // auto-precharge
          SDRAM_A[9:0] <= {2'b0, addr_buf[9:2]};
          SDRAM_DQM <= 4'b0;
          off <= addr_buf[1:0];
        end
        if (cycle == T_RCD+CAS) data_ready <= 1'b1;
        if (cycle == T_RCD+CAS+4'd1) begin
          dout_buf <= next_dout;
          if (resume) state <= SACT2;
          else begin busy <= (q_rd | q_wr | rd | wr); state <= IDLE; end
        end
      end

      WWRITE: begin
        if (cycle == T_RCD) begin
          {SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} <= CMD_Write;
          SDRAM_A[10] <= 1'b1;
          SDRAM_A[9:0] <= {2'b0, addr_buf[9:2]};
          SDRAM_DQM <= word_buf              ? 4'b0000 :
                       addr_buf[1:0] == 2'd0 ? 4'b1110 :
                       addr_buf[1:0] == 2'd1 ? 4'b1101 :
                       addr_buf[1:0] == 2'd2 ? 4'b1011 : 4'b0111;
          off <= addr_buf[1:0];
          dq_out <= {din_buf, din_buf, din_buf, din_buf};
          dq_oen <= 1'b0;
        end
        if (cycle == T_RCD+4'd1) dq_oen <= 1'b1;
        if (cycle == T_RCD+T_WR+T_RP) begin
          if (resume) state <= SACT2;
          else begin busy <= (q_rd | q_wr | rd | wr); state <= IDLE; end
        end
      end

      REF: if (cycle == T_RC) begin
        if (resume) state <= SACT2;
        else begin busy <= (q_rd | q_wr | rd | wr); state <= IDLE; end
      end

      // ---- the stream --------------------------------------------------------
      // The ACTIVATE was issued on the way in; wait out tRCD, then run.
      SACT: if (cycle == T_RCD) state <= SRUN;

      // One READ a cycle, no auto-precharge. Four reasons to wind down --
      // done, end of row, chunk exhausted, refresh due or an abort pending --
      // and they all take the same exit: drain the pipe, close the row, let
      // SNEXT decide what happens next.
      SRUN: begin
        {SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} <= CMD_Read;
        SDRAM_A[10] <= 1'b0;
        SDRAM_A[9:0] <= {2'b0, s_col};
        SDRAM_BA <= s_bank;
        SDRAM_DQM <= 4'b0;
        p0 <= 1'b1;
        s_wptr  <= s_wptr + 21'd1;
        s_left  <= s_left - 9'd1;
        s_chunk <= s_chunk - 9'd1;
        if (s_left == 9'd1 || s_col == 8'hFF || s_chunk == 9'd1
            || ref_due || s_pend) begin
          state <= SDRAIN; cycle <= 4'd1;
        end
      end

      // let the last CAS answers land before touching the row
      SDRAIN: if (cycle == CAS+4'd1) begin
        {SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} <= CMD_PreCharge;
        SDRAM_A[10] <= 1'b1;                            // all banks; only ours is open
        state <= SCLOSE; cycle <= 4'd1;
      end

      SCLOSE: if (cycle == T_RP) begin
        if (s_left == 9'd0) begin
          st_done <= 1'b1;                              // genuine completion
          if (s_pend) begin state <= SNEXT; win <= 2'd2; end
          else begin busy <= (q_rd | q_wr | rd | wr); state <= IDLE; end
        end else begin
          // more to fetch -- or an abort pending, which SACT2 will pick up
          s_chunk <= CHUNK;
          state <= SNEXT; win <= 2'd2;
        end
      end

      // The chunk boundary: refresh first (deadline), then the engine window.
      SNEXT: begin
        if (ref_due) begin
          {SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} <= CMD_AutoRefresh;
          ref_due <= 1'b0; resume <= 1'b1;
          state <= REF; cycle <= 4'd1; busy <= 1'b1;
        end else if (e_rd | e_wr) begin
          {SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} <= CMD_BankActivate;
          SDRAM_BA <= e_addr[22:21];
          SDRAM_A  <= e_addr[20:10];
          addr_buf <= e_addr;
          if (e_wr) begin din_buf <= e_din; word_buf <= e_word; end
          q_rd <= 1'b0; q_wr <= 1'b0;
          resume <= 1'b1;
          state <= e_wr ? WWRITE : WREAD; cycle <= 4'd1; busy <= 1'b1;
        end else if (win == 2'd0) begin
          busy <= 1'b1;                                 // close the window...
          state <= SGRAB;                               // ...but expect a straggler
        end else begin
          busy <= 1'b0;
          win <= win - 2'd1;
        end
      end

      // One cycle: catch the pulse the arbiter may have fired into the closing
      // window (see the header). Otherwise resume the stream.
      SGRAB: begin
        if (e_rd | e_wr) begin
          {SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} <= CMD_BankActivate;
          SDRAM_BA <= e_addr[22:21];
          SDRAM_A  <= e_addr[20:10];
          addr_buf <= e_addr;
          if (e_wr) begin din_buf <= e_din; word_buf <= e_word; end
          q_rd <= 1'b0; q_wr <= 1'b0;
          resume <= 1'b1;
          state <= e_wr ? WWRITE : WREAD; cycle <= 4'd1;
        end else
          state <= SACT2;
      end

      // Re-activate for the stream: the running one, or -- if a new st_go is
      // pending (start or abort-restart) -- that one.
      SACT2: begin
        {SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} <= CMD_BankActivate;
        if (s_pend) begin
          SDRAM_BA <= n_wptr[20:19];
          SDRAM_A  <= n_wptr[18:8];
          s_wptr <= n_wptr; s_left <= n_left; s_pend <= 1'b0;
        end else begin
          SDRAM_BA <= s_bank;
          SDRAM_A  <= s_row;
        end
        s_chunk <= CHUNK;
        resume <= 1'b0; busy <= 1'b1;
        state <= SACT; cycle <= 4'd1;
      end

      default: state <= IDLE;
    endcase

    // An abort must not leak the old stream's in-flight answers into the new
    // stream's consumer: the client (scanout) resets its write index at st_go,
    // so a stale st_valid would land at index 0 and shift the whole new line.
    // Killing the pipe here -- AFTER the case, so it wins over SRUN's issue --
    // silences everything from this edge on; the client flushes the one
    // answer that can predate it. Harmless when no stream is running: the
    // pipe is already empty.
    if (st_go) begin
      p0 <= 1'b0; p1 <= 1'b0; st_valid <= 1'b0;
    end

    if (~resetn) begin
      busy <= 1'b1; dq_oen <= 1'b1; SDRAM_DQM <= 4'b0;
      state <= INIT; cycle <= 4'd0;
      s_pend <= 0; s_left <= 0;
      p0 <= 0; p1 <= 0; st_valid <= 0; st_done <= 0;
      ref_cnt <= 0; ref_due <= 0; resume <= 0; win <= 0;
      q_rd <= 0; q_wr <= 0;
    end
  end

  // ---- 200 us power-on delay (vendored) --------------------------------------
  always @(posedge clk) begin
    rst_done_p1 <= rst_done;
    cfg_now     <= rst_done & ~rst_done_p1;
    if (rst_cnt != FREQ / 1000 * 200 / 1000) begin
      rst_cnt  <= rst_cnt + 15'd1;
      rst_done <= 1'b0;
    end else
      rst_done <= 1'b1;
    if (~resetn) begin
      rst_cnt <= 15'd0; rst_done <= 1'b0;
    end
  end
endmodule
