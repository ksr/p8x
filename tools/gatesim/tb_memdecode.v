// tb_memdecode.v -- gate-level check of the memory card's ADDRESS DECODE and
// its data-bus buffer enable, on the card as built (rev F, from mem_revf.py).
// Sweeps all 64K addresses through the as-drawn decode gates (netlist2v output)
// and verifies:
//   (1) no address selects two memory chips at once (no contention on MD0-7);
//   (2) the ROM chip-select covers exactly $0000-$17FF (the rev-F 6K decode);
//   (3) no memory chip is selected in the I/O page $FF00-$FFFF;
//   (4) the data-bus buffer U3 (!OE = -BOE) is OFF for every $FF00-$FFFF
//       address on a read and on a write, so the card never drives D0-D7
//       while the I/O, CF or PS/2 card answers (fixed 2026-11-26);
//   (5) U3 is ON for every other address on a read and on a write, and OFF
//       in an idle cycle (no -RD, no -MEMW).
// Chip selects and -BOE are active-LOW.
`timescale 1ns/1ns
module tb;
  reg [15:0] A; reg [3:0] DOE, DLD; reg CLK, VCC, GND;
  memoryncard dut(
    .A0(A[0]),.A1(A[1]),.A2(A[2]),.A3(A[3]),.A4(A[4]),.A5(A[5]),.A6(A[6]),.A7(A[7]),
    .A8(A[8]),.A9(A[9]),.A10(A[10]),.A11(A[11]),.A12(A[12]),.A13(A[13]),.A14(A[14]),.A15(A[15]),
    .D0(1'b0),.D1(1'b0),.D2(1'b0),.D3(1'b0),.D4(1'b0),.D5(1'b0),.D6(1'b0),.D7(1'b0),
    .DOE0(DOE[0]),.DOE1(DOE[1]),.DOE2(DOE[2]),.DOE3(DOE[3]),
    .DLD0(DLD[0]),.DLD1(DLD[1]),.DLD2(DLD[2]),.DLD3(DLD[3]),
    .CLK(CLK),.VCC(VCC),.GND(GND));

  integer a, cyc, nsel, errors, contention, iosel, boe_io, boe_mem, boe_idle;
  integer rom_lo, rom_hi, rom_cnt, ram_cnt, ram2_cnt;
  initial begin
    VCC=1; GND=0; CLK=1;
    errors=0; contention=0; iosel=0; boe_io=0; boe_mem=0; boe_idle=0;
    rom_lo=-1; rom_hi=-1; rom_cnt=0; ram_cnt=0; ram2_cnt=0;
    // cyc 0: read (DOE=7 MEM -> -RD), 1: write (DLD=7 MEMW -> -MEMW), 2: idle
    for (cyc=0; cyc<3; cyc=cyc+1) begin
      DOE = (cyc==0) ? 4'd7 : 4'd0;
      DLD = (cyc==1) ? 4'd7 : 4'd0;
      for (a=0; a<65536; a=a+1) begin
        A = a[15:0]; #1;
        if (cyc == 0) begin
          nsel = (dut.ROMCE==0) + (dut.nRAMCE==0) + (dut.nRAM2CE==0);   // active-low selects
          if (nsel > 1) begin
            contention = contention + 1;
            if (contention <= 4)
              $display("  CONTENTION @ $%04h: ROM=%b RAMhi=%b RAMlo=%b", A,
                       ~dut.ROMCE, ~dut.nRAMCE, ~dut.nRAM2CE);
          end
          if (a >= 16'hFF00 && nsel != 0) begin
            iosel = iosel + 1;
            if (iosel <= 4) $display("  CHIP SELECTED IN I/O PAGE @ $%04h", A);
          end
          if (dut.ROMCE==0) begin
            rom_cnt = rom_cnt + 1;
            if (rom_lo < 0) rom_lo = a;
            rom_hi = a;
          end
          if (dut.nRAMCE==0) ram_cnt  = ram_cnt  + 1;
          if (dut.nRAM2CE==0)ram2_cnt = ram2_cnt + 1;
        end
        if (cyc == 2) begin
          if (dut.nBOE !== 1'b1) begin
            boe_idle = boe_idle + 1;
            if (boe_idle <= 4) $display("  BUFFER ON WHEN IDLE @ $%04h", A);
          end
        end else if (a >= 16'hFF00) begin
          if (dut.nBOE !== 1'b1) begin
            boe_io = boe_io + 1;
            if (boe_io <= 4)
              $display("  BUFFER ON IN I/O PAGE @ $%04h (%s)", A, cyc==0 ? "read" : "write");
          end
        end else begin
          if (dut.nBOE !== 1'b0) begin
            boe_mem = boe_mem + 1;
            if (boe_mem <= 4)
              $display("  BUFFER OFF FOR MEMORY @ $%04h (%s)", A, cyc==0 ? "read" : "write");
          end
        end
      end
    end
    $display("gate-sim: memory-card rev F decode + buffer enable (64K sweep x read/write/idle)");
    $display("  ROM  (U1)  : %0d addrs, range $%04h-$%04h", rom_cnt, rom_lo[15:0], rom_hi[15:0]);
    $display("  RAM  (U2)  : %0d addrs", ram_cnt);
    $display("  RAM2 (U10) : %0d addrs", ram2_cnt);
    $display("  contention : %0d addr(s) select >1 chip", contention);
    $display("  I/O page   : %0d addr(s) select a chip, %0d read/write cycle(s) turn U3 on",
             iosel, boe_io);
    $display("  memory     : %0d read/write cycle(s) leave U3 off; idle: %0d turn it on",
             boe_mem, boe_idle);
    if (contention != 0) begin $display("  FAIL: bus contention in the decode"); errors=errors+1; end
    if (!(rom_lo==0 && rom_hi==16'h17FF && rom_cnt==16'h1800)) begin
      $display("  FAIL: ROM decode is not exactly $0000-$17FF"); errors=errors+1; end
    if (rom_cnt + ram_cnt + ram2_cnt != 16'hFF00) begin
      $display("  FAIL: the chips do not cover $0000-$FEFF exactly once"); errors=errors+1; end
    if (iosel != 0) begin $display("  FAIL: a memory chip answers in the I/O page"); errors=errors+1; end
    if (boe_io != 0) begin $display("  FAIL: U3 drives the bus in the I/O page"); errors=errors+1; end
    if (boe_mem != 0) begin $display("  FAIL: U3 off for a memory access"); errors=errors+1; end
    if (boe_idle != 0) begin $display("  FAIL: U3 on in an idle cycle"); errors=errors+1; end
    if (errors==0) $display("  PASS: exclusive decode, ROM = $0000-$17FF (6K), U3 off in $FF00-$FFFF");
    else           $display("  %0d CHECK(S) FAILED", errors);
    $finish;
  end
endmodule
