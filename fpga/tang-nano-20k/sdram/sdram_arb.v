// sdram_arb.v -- one SDRAM, three masters.
//
// The scanout cannot stall (a panel does not wait), refresh cannot be deferred
// indefinitely (the memory forgets), and the engine can wait as long as it
// likes. So the priority is fixed and needs no cleverness:
//
//     scanout  >  refresh  >  engine
//
// Starvation is not a live risk at these numbers: the scanout uses about half a
// line's budget and refresh is a single access every 15 us, so the engine gets
// most of the bus. If that ever changes the fix is an ageing counter on f_req,
// not a rethink.
//
// WHY REQUEST/ACK RATHER THAN EXPOSING THE CONTROLLER'S HANDSHAKE:
// that handshake has a trap in it -- `busy` does not rise until the cycle AFTER
// the controller sees rd/wr, so a master testing `!busy` alone will issue a
// second command into the gap, where it is silently swallowed. It cost two
// debugging rounds in stage 0 (exactly half of memory reading back wrong, which
// looks like a broken data bus rather than a handshake bug). Rather than have
// every master reimplement the rule and get it wrong independently, the rule
// lives HERE, once. A master raises req and holds it until ack; it never sees
// busy at all.
//
// THE OTHER RULE, which is the one that deadlocks if broken: once a read has
// been forwarded, NOTHING else may be issued until its data_ready has come back.
// The controller drops busy in the same cycle it raises data_ready, so an
// arbiter that only watched busy would hand the bus to someone else in exactly
// the cycle the answer arrives, and the read that was already in flight would
// wait forever. `owner` exists for that: it is set when a read is forwarded and
// cleared only when the answer is routed home.
module sdram_arb(
  input             clk,
  input             rst,

  // ---- controller side
  output reg        c_rd,
  output reg        c_wr,
  output reg        c_wr_word,
  output reg        c_refresh,
  output reg [22:0] c_addr,
  output reg [15:0] c_din,
  input      [15:0] c_dout,
  input      [31:0] c_dout32,
  input             c_ready,
  input             c_busy,

  // ---- master 0: scanout. Reads only, always wins.
  input             s_req,        // hold high until s_ack
  input      [22:0] s_addr,
  output reg        s_ack,        // 1 cycle: forwarded to the controller
  output reg        s_ready,      // 1 cycle: c_dout32 is yours

  // ---- master 1: refresh
  input             f_req,
  output reg        f_ack,

  // ---- master 2: engine. Reads and writes, lowest priority.
  input             e_req,
  input             e_we,         // 1 = write, 0 = read
  input             e_word,       // write both halves (span fill: a pixel pair)
  input      [22:0] e_addr,
  input      [15:0] e_din,
  output reg        e_ack,
  output reg        e_ready       // 1 cycle: c_dout is yours
);

  localparam OWN_NONE = 2'd0, OWN_SCAN = 2'd1, OWN_ENG = 2'd2;
  reg [1:0] owner;                // who has a READ in flight

  // The controller is ready for a new command only when it is idle AND our own
  // previous pulse has cleared. See the header.
  wire can_issue = !c_busy && !c_rd && !c_wr && !c_refresh;

  always @(posedge clk) begin
    c_rd <= 0; c_wr <= 0; c_refresh <= 0;
    s_ack <= 0; f_ack <= 0; e_ack <= 0;
    s_ready <= 0; e_ready <= 0;

    if (rst) begin
      owner <= OWN_NONE; c_wr_word <= 0;
    end else if (owner != OWN_NONE) begin
      // A read is outstanding. Route its answer home and free the bus; issue
      // nothing meanwhile, however idle the controller looks.
      if (c_ready) begin
        if (owner == OWN_SCAN) s_ready <= 1;
        else                   e_ready <= 1;
        owner <= OWN_NONE;
      end
    end else if (can_issue) begin
      if (s_req) begin
        c_addr <= s_addr; c_rd <= 1; s_ack <= 1; owner <= OWN_SCAN;
      end else if (f_req) begin
        c_refresh <= 1; f_ack <= 1;         // no answer to wait for
      end else if (e_req) begin
        c_addr <= e_addr; e_ack <= 1;
        if (e_we) begin
          c_din <= e_din; c_wr_word <= e_word; c_wr <= 1;   // no answer either
        end else begin
          c_rd <= 1; owner <= OWN_ENG;
        end
      end
    end
  end
endmodule
