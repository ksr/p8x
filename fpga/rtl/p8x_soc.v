// p8x_soc.v -- P8X CPU + microcode ROM + 64K memory + minimal sim I/O.
//
// Simulation-oriented (async-read memory, matches the emulator cycle-for-cycle).
// The board build (Milestone 3) swaps in synchronous BRAM and real peripherals;
// the CPU core is unchanged.
//
// I/O modelled to match the emulator cycle for cycle:
//   $FF04 read  -> {TDRE=1, RDRF=rx_avail}: transmitter always ready, receiver
//                  ready exactly while the scripted input still has a byte
//   $FF05 read  -> the current scripted byte; pulses rx_take so the testbench
//                  advances. Keyed off mem_rd, NOT mem_addr, so a multi-microcycle
//                  address does not consume the byte twice
//   $FF05 write -> console byte out (tx_stb/tx_byte; the testbench logs it)
//   $FF06 write -> raise maskable IRQ
//   writes below $2000 (ROM) ignored; $2000..$FEFF is RAM.

module p8x_soc #(
  parameter UCODE_HEX = "ucode.hex",
  parameter MEM_HEX   = "eeprom.hex"     // 8K monitor image -> mem[0..8191]
)(
  input  clk,
  input  rst,
  // console RX: the testbench owns the scripted input and its position, so the
  // whole model stays deterministic. rx_avail is RDRF; rx_take pulses on the
  // cycle the CPU actually reads $FF05, and the testbench advances on it.
  input  [7:0] rx_byte,
  input        rx_avail,
  output       rx_take,
  output       st_rd,          // pulses on a read of $FF04 (ACIA status poll)
  // console TX: pulses with the byte written to $FF05
  output       tx_stb,
  output [7:0] tx_byte,
  // CF-IDE task file $FF10..$FF17: routed out to the testbench, which owns the
  // disk image and the ATA handshake (same split as the console -- no file I/O
  // in the SoC). cf_rd is a strobe, so the data port advances exactly once.
  output       cf_rd,
  output       cf_wr,
  output [2:0] cf_a,
  output [7:0] cf_wdata,
  input  [7:0] cf_rdata,
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
  // ACIA: $FF04 status = TDRE always set, RDRF = "the script still has a byte";
  // $FF05 data = the current script byte. Matches p8xemu's memrd() exactly.
  wire [7:0]  acia_st = {6'b0, 1'b1, rx_avail};      // bit1 TDRE, bit0 RDRF
  wire        is_cf = (mem_addr >= 16'hFF10) && (mem_addr <= 16'hFF17);
  wire        is_gfx = (mem_addr >= 16'hFF20) && (mem_addr <= 16'hFF2F);
  wire [7:0]  gfx_rdata;
  wire [7:0]  io_rd = (mem_addr == 16'hFF04) ? acia_st :
                      (mem_addr == 16'hFF05) ? (rx_avail ? rx_byte : 8'h00) :
                      is_cf                  ? cf_rdata :
                      is_gfx                 ? gfx_rdata : 8'hFF;
  wire [7:0]  mem_din = is_io ? io_rd : mem[mem_addr];

  wire mem_rd;
  assign rx_take = mem_rd && (mem_addr == 16'hFF05) && rx_avail;
  assign st_rd   = mem_rd && (mem_addr == 16'hFF04);
  assign cf_rd    = mem_rd && is_cf;
  assign cf_wr    = mem_we && is_cf;
  assign cf_a     = mem_addr[2:0];
  assign cf_wdata = mem_dout;
  assign tx_stb  = mem_we && (mem_addr == 16'hFF05);
  assign tx_byte = mem_dout;

  wire irq_set = mem_we && (mem_addr == 16'hFF06);

  // Graphics display. No scanout here -- this SoC has no panel; the testbench
  // reads the framebuffer array directly to dump a frame. rd_stb is keyed off
  // mem_rd, not the address, so the IDENT stream cannot be double-consumed by a
  // multi-microcycle address (the same rule the ACIA needs at $FF05).
  gfx GFX(
    .clk(clk), .rst(rst),
    .sel(is_gfx), .a(mem_addr[3:0]), .wr(mem_we && is_gfx),
    .rd_stb(mem_rd && is_gfx), .wdata(mem_dout), .rdata(gfx_rdata),
    .sc_addr(13'd0), .sc_data(), .sc_pen(2'd0), .sc_rgb());

  p8x_cpu CPU(
    .clk(clk), .rst(rst), .cen(1'b1),   // async model: one microcycle per clock
    .uc_addr(uc_addr), .uc_data(uc_data),
    .mem_addr(mem_addr), .mem_din(mem_din), .mem_dout(mem_dout), .mem_we(mem_we),
    .mem_rd(mem_rd),
    .irq_set(irq_set), .halted(halted));

  // writes: RAM only ($2000..$FEFF); ROM + I/O side effects are no-ops here
  always @(posedge clk) begin
    if (mem_we && mem_addr >= 16'h2000 && mem_addr < 16'hFF00)
      mem[mem_addr] <= mem_dout;
  end

  // ROM image is loaded into its own 8K array and copied in: $readmemh straight
  // into mem[] would warn that a 64K range was under-filled on every run.
  reg [7:0] romimg [0:8191];
  integer j;
  initial begin
    for (j = 0; j < 65536; j = j + 1) mem[j]    = 8'h00; // RAM starts zero (as emulator)
    for (j = 0; j < 8192;  j = j + 1) romimg[j] = 8'h00; // short ROMs pad with 0, not x
    $readmemh(UCODE_HEX, ucode);
    $readmemh(MEM_HEX, romimg);
    for (j = 0; j < 8192;  j = j + 1) mem[j] = romimg[j];
  end
endmodule
