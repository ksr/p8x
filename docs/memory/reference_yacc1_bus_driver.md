---
name: reference-yacc1-bus-driver
description: "YACC1 Bus Test Card (\"bus driver\") serial protocol, where its firmware, signal table and test scripts live, and the planned drive-the-bus-from-the-Mac experiment"
metadata: 
  node_type: memory
  type: reference
  originSessionId: 05007751-a1c3-49f6-8fff-5b14d1ceec67
  modified: 2026-09-19T00:58:00.632Z
---

YACC1's Bus Test Card (PCB "Bus Tester" V3.1 prod / V3.11 working) is an on-board ATmega (Arduino
bootloader) + six MCP23017 I2C expanders; it is the ancestor of the P8X bus-driver idea. With the
sequencer/control card removed it can drive or read every bus line. See [[project-yacc1]].

**Talk to it:** FTDI cable (DTR-RESET jumper resets the chip on port open), **19200 baud**, 8N1.
Commands are `CMD:OPERAND#` with NO line ending (`#` is the terminator). Card prints `>>` as the
prompt after each command; special (read/write) commands print `Data: <decimal>` then `Complete`.
Operand on the WIRE is decimal (firmware atoi); operands in the Command Sender SCRIPTS are HEX
(host unhex()s them and sends decimal; `!expected` values are hex too). Host waits 50 ms per command
and then reads lines until `>>`. Firmware: `Software-vs/Bus Test Card/bus-driver/bus-driver.ino`
(2020-09-10, identical in every copy). Signal table is NOT in the repo: it is
`~/Documents/Arduino/libraries/YACC/YACC_Common_header.h` (2020-09-01, bus V3.2 naming; the
`-pre3-2.h` sibling is the older bus). Names starting with `-` are active-low and the firmware
inverts for you: `-RESET:1#` asserts reset (drives the pin low).

**Vocabulary** (chip 0 = address bus, 1 = data bus, 2..5 = control):
- register card: -REG-FUNC-RD/-LD, REG-RD-ID0..3, REG-LD-ID0..3, -REG-RD-LO/-HI, -REG-LD-LO/-HI, -REG-UP/-DN
- memory/io: -MEM-RD, -MEM-WR, -IO-RD, -IO-WR, -TMP-REG-RD0/LD0/RD1/LD1, ADDR-REG-ID0..3, IOADDR0..3,
  -IO-ADDR-LD, -VMA, -INT, -INTA
- ALU: -ALU-FUNC, ALU0..3, -AC-LD-INV, -AC-RD, -AC-LD, -SR-LD, BR-COND(in), -HL-SWAP, IN(in)
- system: OUT, -BUS-EN, -RUN, -RESET; card-local: OUT-LED, IN-SWITCH, LEDS-LD, SWITCHES-RD, BIT0..7
- specials: RD-DATABUS / RD-DATABUS-L / -H, WR-DATABUS:n, RD-ADDRBUS, WR-ADDRBUS:n, DATABUS-RD-MODE /
  -WR-MODE, ADDRBUS-RD-MODE / -WR-MODE, RBR-COND, RD-IN, READ-SWITCHES, SET-LEDS:n.
  Read/write a bus in the wrong mode = firmware `doError` -> blinks an LED forever (needs reset).

**Host side:** Processing sketch `Command sender/command_sender_8.pde` (script language: WAIT, :label,
GOTO, LET/FOR/NEXT, `CMD:OP#EXPECTED!VAR`, DUMP:start-end# implemented host-side). Example scripts
in `Command sender/tests/` (Memory Card Tests, ALU, IO/serialout = UART init sequence, Index Register).
Memory write idiom: DATABUS-WR-MODE, WR-ADDRBUS:a, WR-DATABUS:d, -MEM-WR:1#, -MEM-WR:0#. Memory read:
DATABUS-RD-MODE, WR-ADDRBUS:a, -MEM-RD:1#, RD-DATABUS, -MEM-RD:0#. Set -VMA:1# first for RAM/ROM select
(memory card v1.1+). Reset = 0x0000 reads ROM ($F000 image) until $F000 accessed.

**PROVEN 2026-09-18 from this Mac:** pyserial 3.5 installed (--user). Driver script `busdrv.py`
(BusDriver class: cmd/pulse/readmem/writemem/dump; --probe/--reset/--dump/--raw) lived in the session
scratchpad; recreate from the protocol above if needed. Port `/dev/cu.usbserial-AB6WZCQX`. The FTDI
cable did NOT enumerate through the user's USB hub/dock (empty USB tree); plug DIRECTLY into the Mac.
Listen (bus-monitor) and drive (bus-driver) are SEPARATE sketches, no switch mode; the card shipped
running bus-monitor. Build with the IDE-bundled arduino-cli, `--fqbn arduino:avr:uno` (115200 optiboot;
the pro/57600 profile fails "not in sync"), against the LEGACY MCP23017 1.1.0 lib in
~/Documents/Arduino/old-libraries (installed 2.3.2 has a different header/API) via `--libraries <dir>`
holding that lib + YACC header; flashing needs the user (auto-mode denies arduino-cli upload).
MUST assert `-BUS-EN:1#` (and `-VMA:1#`) before any memory cycle or every read is FF.
Test rig that day: switch-ROM card at $0000 (16 bytes; read 70 01 91 61 B0 01 61 A2 00 04 A0 00...) and a
16-byte RAM card at $0010; both verified (two-pattern write/read-back OK); all other addresses FF.

**2026-09-21 firmware "blocks-1" (commit 4e57871, FLASHED to the card 2026-09-21 per docs/system/MACHINE.md; the working board is v1.1 with the May-2020 rework, Ken 2026-09-20; v3.1/v3.11 never built):** `RDBLK:addr,count#` (1-64 bytes, reply
`Data: hh hh ...`) and `WRBLK:addr,count,hex#` (1-32 bytes) = one round trip per block instead of 4 commands per byte
(~40 ms per command: ~22 ms serial at 19200 + 16 ms FTDI latency + I2C). Banner `bus-driver blocks-1 2026-09-21` before
the first prompt; `tools/busdrv.py` sets `bd.blocks` from it and `read_block/write_block` fall back per byte. NEVER send
RDBLK to the old firmware: unknown opcode -> doError() halts (blink loop) until reset. busdrv.cmd() now resends on
timeout and reopens a vanished port (on_reopen callback re-does the setup). Signal table is vendored in
YACC1-D/embedded/libraries/YACC/. Per-byte full-RAM tests run ~4 h per 52K pattern; with blocks minutes.
