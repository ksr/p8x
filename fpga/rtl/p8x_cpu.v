// p8x_cpu.v -- P8X CPU core, one microcycle per clock.
//
// A faithful RTL transliteration of the C emulator's microcycle loop
// (emulator/p8xemu.c, lines ~272-356). Same microcode ROM, same 74181 model,
// same shifter/flag/condition semantics -- so RTL and emulator cannot drift.
// This is the reference-matching core; board timing adaptations (synchronous
// BRAM) come in Milestone 3, but the logic here is the contract.
//
// Memory interface is ASYNCHRONOUS-read (combinational mem_din at mem_addr),
// which makes the core cycle-for-cycle identical to the emulator. Writes assert
// mem_we/mem_dout and are committed by the surrounding SoC on the clock edge.
//
// Control word (32 bits, from microcode/genucode.py):
//  0-3 DOE | 4-7 DLD | 8-10 PSEL | 11 PINC | 12 PDEC | 13-16 ALUS | 17 ALUM |
//  18 CIN(active-low pin) | 19 SH0 | 20 SH1 | 21 LDF | 22-24 FCOND | 25 uRST |
//  26 HALT | 27 LDZN | 28 SHCIN | 29 SETC | 30 CLRC | 31 BSEL

module p8x_cpu(
  input             clk,
  input             rst,          // synchronous, active-high
  // Clock enable: the CPU advances one microcycle per enabled edge. Tie high for
  // the async-memory simulation model (p8x_soc.v). The board build holds it low
  // while it walks the two DEPENDENT block-RAM reads a microcycle needs -- the
  // microcode word first, because its PSEL field chooses which pointer drives
  // mem_addr, and only then the memory byte. One clock edge cannot do both.
  input             cen,
  // microcode ROM (13-bit addr = {cond, stp[3:0], IR[7:0]}), 32-bit word
  output     [12:0] uc_addr,
  input      [31:0] uc_data,
  // main memory / IO (async read)
  output     [15:0] mem_addr,     // = P[psel]
  input      [7:0]  mem_din,
  output     [7:0]  mem_dout,
  output            mem_we,
  output            mem_rd,       // this microcycle sources the bus from memory
  input             irq_set,      // pulse: raise a maskable IRQ (models a device)
  output            halted);

  // ---- architectural state ----
  reg [15:0] P [0:5];             // P0=PC P1 P2 P3=SP P4=PT P5=PT2
  reg [7:0]  A, B, T, T2, IR;
  reg [3:0]  stp;
  reg        fC, fZ, fN, fV;
  reg        IE, irqp, halt_r;
  reg [2:0]  prev_fcond;
  reg [63:0] cyc;                 // cycle counter (trace only)

  assign halted = halt_r;

  // ---- condition mux (from the PREVIOUS word's FCOND) ----
  reg cond;
  always @* case (prev_fcond)
    3'd1: cond = 1'b1;      3'd2: cond = fC;
    3'd3: cond = fZ;        3'd4: cond = fN;
    3'd5: cond = fV;        3'd6: cond = fN ^ fV;         // signed <  (BLT)
    3'd7: cond = (fN ^ fV) | fZ;                          // signed <= (BLE)
    default: cond = 1'b0;
  endcase

  assign uc_addr = {cond, stp, IR};
  wire [31:0] cw = uc_data;

  // ---- decode ----
  wire [3:0] doe   = cw[3:0];
  wire [3:0] dld   = cw[7:4];
  wire [2:0] psel  = cw[10:8];
  wire       pinc  = cw[11];
  wire       pdec  = cw[12];
  wire [3:0] alus  = cw[16:13];
  wire       m     = cw[17];
  wire       cinp  = cw[18];      // active-low carry pin
  wire       sh0   = cw[19];
  wire       sh1   = cw[20];
  wire       ldf   = cw[21];
  wire [2:0] fcond = cw[24:22];
  wire       urst  = cw[25];
  wire       halt  = cw[26];
  wire       ldzn  = cw[27];
  wire       shcin = cw[28];
  wire       setc  = cw[29];
  wire       clrc  = cw[30];
  wire       bsel  = cw[31];

  // ---- 74181 (active-high data). Arithmetic carry computed regardless of M. ----
  function [8:0] alu_arith(input [7:0] a, input [7:0] b, input [3:0] s, input ci);
    reg [7:0] nb; reg [8:0] r;
    begin
      nb = ~b;
      case (s)
        4'h0: r = a;                  4'h1: r = a | b;
        4'h2: r = a | nb;             4'h3: r = 9'h0FF;
        4'h4: r = a + (a & nb);       4'h5: r = (a | b) + (a & nb);
        4'h6: r = a + nb;             4'h7: r = (a & nb) + 8'hFF;
        4'h8: r = a + (a & b);        4'h9: r = a + b;
        4'hA: r = (a | nb) + (a & b); 4'hB: r = (a & b) + 8'hFF;
        4'hC: r = a + a;              4'hD: r = (a | b) + a;
        4'hE: r = (a | nb) + a;       4'hF: r = a + 8'hFF;
      endcase
      alu_arith = r + ci;             // bit 8 = conventional carry-out (rev B)
    end
  endfunction
  function [7:0] alu_logic(input [7:0] a, input [7:0] b, input [3:0] s);
    reg [7:0] nb;
    begin
      nb = ~b;
      case (s)
        4'h0: alu_logic = ~a;         4'h1: alu_logic = ~(a | b);
        4'h2: alu_logic = ~a & b;     4'h3: alu_logic = 8'h00;
        4'h4: alu_logic = ~(a & b);   4'h5: alu_logic = nb;
        4'h6: alu_logic = a ^ b;      4'h7: alu_logic = a & nb;
        4'h8: alu_logic = ~a | b;     4'h9: alu_logic = ~(a ^ b);
        4'hA: alu_logic = b;          4'hB: alu_logic = a & b;
        4'hC: alu_logic = 8'hFF;      4'hD: alu_logic = a | nb;
        4'hE: alu_logic = a | b;      4'hF: alu_logic = a;
      endcase
    end
  endfunction

  wire [7:0] bop  = bsel ? T : B;                 // ALU B-input mux
  wire       cin  = ~cinp;                        // logical carry-in
  wire [8:0] arith = alu_arith(A, bop, alus, cin);
  wire       cout = arith[8];
  wire [7:0] f    = m ? alu_logic(A, bop, alus) : arith[7:0];

  // ---- shifter ----
  wire       sin   = shcin ? fC : 1'b0;
  wire [7:0] g     = sh0 ? {f[6:0], sin} : f;     // stage 1: left
  wire [7:0] rres  = sh1 ? {sin, g[7:1]} : g;     // stage 2: right
  wire       shout = sh0 ? f[7] : (sh1 ? f[0] : 1'b0);
  wire       cc    = (sh0 | sh1) ? shout : cout;  // next-C
  wire       zz    = (rres == 8'h00);
  wire       nn    = rres[7];
  // V: sign-bit method (isadd = ~ALUS2)
  wire       isadd = ~alus[2];
  wire       vv    = (A[7] ^ f[7]) & (A[7] ^ bop[7] ^ isadd);

  // ---- address + bus source (DOE mux) ----
  wire [15:0] addr = P[psel];
  reg  [7:0]  bus;
  always @* begin
    case (doe)
      4'd1: bus = A;                4'd2: bus = B;
      4'd3: bus = T;                4'd4: bus = T2;
      4'd5: bus = rres;             4'd6: bus = {4'b0, fV, fN, fZ, fC};
      4'd7: bus = mem_din;          4'd8: bus = addr[7:0];
      4'd9: bus = addr[15:8];       default: bus = 8'hFF;   // idle
    endcase
    // rev C interrupt forcing buffer: at fetch inject $08; the $08 routine drives $08
    if (stp == 4'd0 && doe == 4'd7 && IE && irqp) bus = 8'h08;
    else if (IR == 8'h08 && doe == 4'd0)          bus = 8'h08;
  end

  assign mem_addr = addr;
  assign mem_dout = bus;
  assign mem_we   = (dld == 4'd7) && !halt_r;
  // A read happens on exactly the microcycles that source the bus from memory --
  // the same points at which the emulator calls memrd(). Peripherals with
  // read side effects (the ACIA data register pops a byte) must key off this,
  // not off mem_addr alone, which can linger across microcycles.
  assign mem_rd   = (doe == 4'd7) && !halt_r;

  // ---- next flags. Emulator order: DLD=5 loads flags from bus first, then
  // ldf/ldzn override, then setc/clrc force C. ----
  reg nfC, nfZ, nfN, nfV;
  always @* begin
    nfC = fC; nfZ = fZ; nfN = fN; nfV = fV;
    if (dld == 4'd5) {nfV, nfN, nfZ, nfC} = bus[3:0];   // DLD=FLAGS (RTI / pop flags)
    if (ldf)       begin nfC = cc; nfZ = zz; nfN = nn; nfV = vv; end
    else if (ldzn) begin nfZ = (bus == 8'h00); nfN = bus[7]; end
    if (setc) nfC = 1'b1;
    if (clrc) nfC = 1'b0;
  end

  // ---- next value of the selected pointer (DLD byte-load, then pinc/pdec) ----
  reg [15:0] nP;
  always @* begin
    nP = P[psel];
    if (dld == 4'd8)      nP = {P[psel][15:8], bus};
    else if (dld == 4'd9) nP = {bus, P[psel][7:0]};
    if (pinc) nP = nP + 16'd1;
    if (pdec) nP = nP - 16'd1;
  end

  integer i;
  always @(posedge clk) begin
    if (rst) begin
      P[0]<=0; P[1]<=0; P[2]<=0; P[3]<=16'hFEFF; P[4]<=0; P[5]<=0;
      A<=0; B<=0; T<=0; T2<=0; IR<=0; stp<=0;
      fC<=0; fZ<=0; fN<=0; fV<=0; IE<=0; irqp<=0; halt_r<=0;
      prev_fcond<=0; cyc<=0;
    end else if (cen && !halt_r) begin
`ifdef P8X_TRACE
      // canonical machine trace: one line per cycle, pre-commit state.
      // MUST match the emulator's `-T` output for line-by-line co-sim diff.
      $display("%0d %02x %x %02x %02x %02x %02x %04x %04x %04x %04x %04x %04x %0d%0d%0d%0d",
               cyc, IR, stp, A, B, T, T2, P[0], P[1], P[2], P[3], P[4], P[5],
               fC, fZ, fN, fV);
`endif
      // register commits (CLK edge)
      case (dld)
        4'd1: A  <= bus;   4'd2: B  <= bus;
        4'd3: T  <= bus;   4'd4: T2 <= bus;
        4'd6: IR <= bus;
        // 5 = flags (folded into nfC/.. above); 7 = memory write (SoC via mem_we);
        // 8/9 pointer bytes fold into nP below
      endcase
      P[psel] <= nP;                          // covers DLD 8/9 + pinc/pdec
      fC<=nfC; fZ<=nfZ; fN<=nfN; fV<=nfV;
      // EI/DI/RTI: opcode decode at retire (not a microcode bit)
      if (urst) begin
        if (IR == 8'h02 || IR == 8'h04) IE <= 1'b1;
        else if (IR == 8'h03)           IE <= 1'b0;
      end
      // IRQ acknowledge / external set
      if (stp == 4'd0 && doe == 4'd7 && IE && irqp) irqp <= 1'b0;
      if (irq_set) irqp <= 1'b1;
      prev_fcond <= fcond;
      stp <= urst ? 4'd0 : stp + 4'd1;
      if (halt) halt_r <= 1'b1;
      cyc <= cyc + 1;
    end
  end
endmodule
