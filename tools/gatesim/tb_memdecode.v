// tb_memdecode.v -- gate-level check of the memory card's ADDRESS DECODE.
// Sweeps all 64K addresses through the as-drawn decode gates (netlist2v output)
// and verifies: (1) no address selects two memory chips at once (no bus
// contention), and (2) the ROM chip-select covers exactly $0000-$1FFF (the
// rev-E 8K decode in the gen_eagle netlist). Chip selects are active-LOW.
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

  integer a, nsel, errors, contention;
  integer rom_lo, rom_hi, rom_cnt, ram_cnt, ram2_cnt;
  initial begin
    VCC=1; GND=0; CLK=1; DOE=4'd7; DLD=4'd7;   // a read cycle: DOE=7 -> -RD active
    errors=0; contention=0; rom_lo=-1; rom_hi=-1; rom_cnt=0; ram_cnt=0; ram2_cnt=0;
    for (a=0; a<65536; a=a+1) begin
      A = a[15:0]; #1;
      nsel = (~dut.ROM8CE) + (~dut.nRAMCE) + (~dut.nRAM2CE);   // count active-low selects
      if (nsel > 1) begin
        contention = contention + 1;
        if (contention <= 4)
          $display("  CONTENTION @ $%04h: ROM=%b RAMlo=%b RAMhi=%b", a,
                   ~dut.ROM8CE, ~dut.nRAMCE, ~dut.nRAM2CE);
      end
      if (~dut.ROM8CE) begin
        rom_cnt = rom_cnt + 1;
        if (rom_lo < 0) rom_lo = a;
        rom_hi = a;
      end
      if (~dut.nRAMCE)  ram_cnt  = ram_cnt  + 1;
      if (~dut.nRAM2CE) ram2_cnt = ram2_cnt + 1;
    end
    $display("gate-sim: memory-card address decode (64K sweep, read cycle)");
    $display("  ROM  select: %0d addrs, range $%04h-$%04h", rom_cnt, rom_lo, rom_hi);
    $display("  RAM  (U2)  : %0d addrs", ram_cnt);
    $display("  RAM2 (U10) : %0d addrs", ram2_cnt);
    $display("  contention : %0d addr(s) select >1 chip", contention);
    // checks
    if (contention != 0) begin $display("  FAIL: bus contention in the decode"); errors=errors+1; end
    if (!(rom_lo==0 && rom_hi==16'h1FFF && rom_cnt==16'h2000)) begin
      $display("  FAIL: ROM decode is not exactly $0000-$1FFF"); errors=errors+1; end
    if (errors==0) $display("  PASS: exclusive decode, ROM = $0000-$1FFF (8K)");
    else           $display("  %0d CHECK(S) FAILED", errors);
    $finish;
  end
endmodule
