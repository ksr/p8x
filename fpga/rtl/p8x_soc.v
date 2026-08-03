// p8x_soc.v -- P8X CPU + microcode ROM + 64K memory + minimal sim I/O.
//
// Simulation-oriented (async-read memory, matches the emulator cycle-for-cycle).
// The board build (Milestone 3) swaps in synchronous BRAM and real peripherals;
// the CPU core is unchanged.
//
// I/O modelled to match the emulator for an input-free boot:
//   $FF04 read  -> 0x02 (TDRE set, RDRF clear: "ready to send, no key")
//   $FF05 write -> console byte (swallowed here; the co-sim diffs registers, not
//                  console text, so we keep stdout pure trace)
//   $FF06 write -> raise maskable IRQ
//   writes below $2000 (ROM) ignored; $2000..$FEFF is RAM.

module p8x_soc #(
  parameter UCODE_HEX = "ucode.hex",
  parameter MEM_HEX   = "eeprom.hex"     // 8K monitor image -> mem[0..8191]
)(
  input  clk,
  input  rst,
  output halted);

  // ---- microcode ROM: 8192 x 32-bit, async read ----
  reg [31:0] ucode [0:8191];
  wire [12:0] uc_addr;
  wire [31:0] uc_data = ucode[uc_addr];

  // ---- 64K byte memory, async read / sync write ----
  reg [7:0] mem [0:65535];
  wire [15:0] mem_addr;
  wire [7:0]  mem_dout;
  wire        mem_we;
  wire        is_io = (mem_addr >= 16'hFF00);
  wire [7:0]  io_rd = (mem_addr == 16'hFF04) ? 8'h02 : 8'hFF;
  wire [7:0]  mem_din = is_io ? io_rd : mem[mem_addr];

  wire irq_set = mem_we && (mem_addr == 16'hFF06);

  p8x_cpu CPU(
    .clk(clk), .rst(rst),
    .uc_addr(uc_addr), .uc_data(uc_data),
    .mem_addr(mem_addr), .mem_din(mem_din), .mem_dout(mem_dout), .mem_we(mem_we),
    .irq_set(irq_set), .halted(halted));

  // writes: RAM only ($2000..$FEFF); ROM + I/O side effects are no-ops here
  always @(posedge clk) begin
    if (mem_we && mem_addr >= 16'h2000 && mem_addr < 16'hFF00)
      mem[mem_addr] <= mem_dout;
  end

  integer j;
  initial begin
    for (j = 0; j < 65536; j = j + 1) mem[j] = 8'h00;  // RAM starts zero (as emulator)
    $readmemh(UCODE_HEX, ucode);
    $readmemh(MEM_HEX, mem);                            // monitor ROM -> mem[0..8191]
  end
endmodule
