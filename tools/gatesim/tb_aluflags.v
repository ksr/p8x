// tb_aluflags.v -- gate-level check of the ALU card's FLAG REGISTER loads, on
// the as-drawn netlist (netlist2v output). Added 2026-11-27 with the RTI flag
// restore (DLD=5 -> -LDFL on U21.Y5 -> restore mux U36, enable gate U37.1).
// Checks:
//   (1) DLD=5 restores C,Z,N,V from D0-D3 (the DOE=6 flag byte order), for all
//       16 values, with LDF and LDZN low;
//   (2) no other DLD code (0-4, 6-15) touches the flags on a clock;
//   (3) LDZN still loads Z and N from the bus byte (Z = byte==0, N = bit 7)
//       and leaves C alone;
//   (4) LDF still clocks all four flags, and the restore mux then passes the
//       normal sources (ALU carry, Z/N mux, V logic) to the flip-flops;
//   (5) -RES clears the flags;
//   (6) V (U26's second half since 2026-11-27) keeps its value through an LDZN
//       load, takes VSRC on LDF and D3 on the DLD=5 restore, and -RES clears it.
//       On the earlier board V sat in U17 and an LDZN cycle loaded VSRC, which
//       is 0 in every LDZN microword (the ALU passes A), so a load cleared V.
// The 74181s are not modelled, so the ALU-derived sources are X here: check (4)
// compares the mux outputs to their sources and the clock enables, and check (6)
// forces VSRC to a known value; the full ALU-to-flag path is covered by the
// emulator / FPGA co-sims.
`timescale 1ns/1ns
module tb;
  reg [7:0] D; reg [3:0] DLD, DOE; reg CLK, nRES, LDF, LDZN, SETC, CLRC;
  reg VCC, GND;
  aluncard dut(
    .D0(D[0]),.D1(D[1]),.D2(D[2]),.D3(D[3]),.D4(D[4]),.D5(D[5]),.D6(D[6]),.D7(D[7]),
    .DLD0(DLD[0]),.DLD1(DLD[1]),.DLD2(DLD[2]),.DLD3(DLD[3]),
    .DOE0(DOE[0]),.DOE1(DOE[1]),.DOE2(DOE[2]),.DOE3(DOE[3]),
    .CLK(CLK),.nRES(nRES),.LDF(LDF),.LDZN(LDZN),.SETC(SETC),.CLRC(CLRC),
    .ALUM(1'b0),.ALUS0(1'b0),.ALUS1(1'b0),.ALUS2(1'b0),.ALUS3(1'b0),
    .BSEL(1'b0),.CIN(1'b0),.SH0(1'b0),.SH1(1'b0),.SHCIN(1'b0),
    .FC(),.FZ(),.FN(),.FV(),.VCC(VCC),.GND(GND));

  wire [3:0] F = {dut.FQV, dut.FQN, dut.FQZ, dut.FQC};   // V N Z C = D3..D0
  integer v, c, errors, n_restore, n_other, n_ldzn, n_ldf, n_v;
  task clk; begin #5 CLK = 1; #5 CLK = 0; #5; end endtask
  task restore(input [3:0] val); begin   // RTI's T -> FLAGS step
    DLD = 4'd5; D = {4'b0, val}; #5; clk; DLD = 4'd0;
  end endtask

  initial begin
    VCC=1; GND=0; CLK=0; LDF=0; LDZN=0; SETC=0; CLRC=0; DOE=0; DLD=0; D=0;
    errors=0; n_restore=0; n_other=0; n_ldzn=0; n_ldf=0; n_v=0;
    nRES=0; #10;
    if (F !== 4'b0000) begin $display("  FAIL: -RES leaves flags %b", F); errors=errors+1; end
    nRES=1; #10;

    // (1) restore every value, from every previous value
    for (v=0; v<16; v=v+1) begin
      restore(v[3:0]);
      if (F !== v[3:0]) begin
        n_restore = n_restore + 1;
        if (n_restore <= 4) $display("  RESTORE %b gave VNZC=%b", v[3:0], F);
      end
    end

    // (2) every other DLD code, with the opposite pattern on the bus
    for (c=0; c<16; c=c+1) if (c != 5) begin
      restore(4'b1010);
      DLD = c[3:0]; D = 8'h05; #5; clk; DLD = 0;
      if (F !== 4'b1010) begin
        n_other = n_other + 1;
        if (n_other <= 4) $display("  DLD=%0d changed the flags to %b", c, F);
      end
    end

    // (3) LDZN: Z,N from the byte, C kept (V comes from the unmodelled ALU: not checked)
    restore(4'b0001);                                    // C=1
    LDZN=1; DLD=4'd1; D=8'h00; #5; clk; LDZN=0; DLD=0;   // e.g. LDA #0
    if (!(dut.FQZ===1 && dut.FQN===0 && dut.FQC===1)) begin n_ldzn=n_ldzn+1;
      $display("  LDZN $00: C=%b Z=%b N=%b", dut.FQC, dut.FQZ, dut.FQN); end
    restore(4'b0000);
    LDZN=1; DLD=4'd1; D=8'h80; #5; clk; LDZN=0; DLD=0;
    if (!(dut.FQZ===0 && dut.FQN===1 && dut.FQC===0)) begin n_ldzn=n_ldzn+1;
      $display("  LDZN $80: C=%b Z=%b N=%b", dut.FQC, dut.FQZ, dut.FQN); end

    // (4) LDF: both clock enables on, mux passes the normal sources through
    LDF=1; DLD=4'd0; #5;
    if (dut.FENC !== 1 || dut.FENALL !== 1) n_ldf = n_ldf + 1;
    if (dut.RC !== dut.NC || dut.RZ !== dut.ZSRC || dut.RN !== dut.NSRC || dut.RV !== dut.VSRC)
      n_ldf = n_ldf + 1;
    CLK=1; #1;
    if (dut.CLKFC !== 1 || dut.CLKFZN !== 1) n_ldf = n_ldf + 1;
    CLK=0; LDF=0; #5;
    // and with LDF, LDZN, DLD=5 all low, no flag clock at all
    CLK=1; #1;
    if (dut.CLKFC !== 0 || dut.CLKFZN !== 0) n_ldf = n_ldf + 1;
    CLK=0; #5;
    if (n_ldf) $display("  LDF path: %0d check(s) wrong", n_ldf);

    // (6) V: held through LDZN, loaded by LDF and by the restore, cleared by -RES
    restore(4'b0000);                                    // V=0
    force dut.VSRC = 1'b1;                               // the ALU would say V=1
    LDZN=1; DLD=4'd1; D=8'h42; #5; clk; LDZN=0; DLD=0;   // LDA #$42
    if (dut.FQV !== 1'b0) begin n_v=n_v+1; $display("  LDZN loaded V (V=0 -> %b)", dut.FQV); end
    restore(4'b1000);                                    // V=1
    force dut.VSRC = 1'b0;
    LDZN=1; DLD=4'd1; D=8'h00; #5; clk; LDZN=0; DLD=0;   // LDA #0
    if (dut.FQV !== 1'b1) begin n_v=n_v+1; $display("  LDZN loaded V (V=1 -> %b)", dut.FQV); end
    LDF=1; #5; clk; LDF=0;                               // ALU op, VSRC=0
    if (dut.FQV !== 1'b0) begin n_v=n_v+1; $display("  LDF with VSRC=0 left V=%b", dut.FQV); end
    force dut.VSRC = 1'b1;
    LDF=1; #5; clk; LDF=0;                               // ALU op, VSRC=1
    if (dut.FQV !== 1'b1) begin n_v=n_v+1; $display("  LDF with VSRC=1 left V=%b", dut.FQV); end
    force dut.VSRC = 1'b0;
    restore(4'b1000);                                    // restore wins over VSRC
    if (dut.FQV !== 1'b1) begin n_v=n_v+1; $display("  restore V=1 gave V=%b", dut.FQV); end
    SETC=1; #5; SETC=0; CLRC=1; #5; CLRC=0; #5;          // SEC/CLC touch C only
    if (dut.FQV !== 1'b1) begin n_v=n_v+1; $display("  SETC/CLRC changed V to %b", dut.FQV); end
    nRES=0; #10; nRES=1; #10;
    if (dut.FQV !== 1'b0) begin n_v=n_v+1; $display("  -RES left V=%b", dut.FQV); end
    release dut.VSRC;

    $display("gate-sim: alu-card flag register (DLD=5 restore, LDZN, LDF, -RES)");
    $display("  restore    : %0d of 16 values wrong", n_restore);
    $display("  other DLD  : %0d of 15 codes touched the flags", n_other);
    $display("  LDZN load  : %0d wrong", n_ldzn);
    $display("  LDF enable : %0d wrong", n_ldf);
    $display("  V flag     : %0d of 7 checks wrong", n_v);
    errors = errors + n_restore + n_other + n_ldzn + n_ldf + n_v;
    if (errors==0) $display("  PASS: DLD=5 restores C,Z,N,V from D0-D3; LDZN keeps C and V; LDF unchanged");
    else           $display("  FAIL: %0d check(s) failed", errors);
    $finish;
  end
endmodule
