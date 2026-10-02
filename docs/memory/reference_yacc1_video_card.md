---
name: reference-yacc1-video-card
description: "YACC1 Video card V1.0 (6845 + IDT7134 dual-port RAM on the YACC1 bus) - where the exported design lives, its address decode, jumper settings for $D000, and the design issues found in the netlist"
metadata: 
  node_type: memory
  type: reference
  originSessionId: 05007751-a1c3-49f6-8fff-5b14d1ceec67
  modified: 2026-09-19T04:22:06.669Z
---

**Real YACC1 video card = `~/Documents/YACCS/video/Video_1.0.sch` + `Blank V3.1.brd`** (Eagle 9.7 XML,
exported from Fusion 360 on 2026-09-18; Fusion is the master, the export is a snapshot). It was NOT in the
YACCS tree before that. Do not confuse with the 1802 ELF 6845 card in
`~/Documents/Projects/1802/Netronics ELF Recreation/video_card` (same video engine, ELF bus, TPA/TPB).
Targets the deliberately undecoded $D000 block of the memory card ([[project-yacc1]]).

**Parts:** X1 FABC96R bus connector, IC17 6845 CRTC, IC15 IDT7134 dual-port RAM (4Kx8; CPU-side A11R tied
to GND so CPU sees 2K), IC25 2732 char ROM, IC18 74x85 comparator, SV3 2x4 jumper header + RN2 pull-ups,
SV4 1x3 dot-clock jumper, IC1 74x08, IC19 74x00, IC20 74x04, IC26 74x86, IC27 74x16 (open-collector
inverters), IC2 74x373 + JP1 2x7 header (a readable config/ID byte), R1 10K + C1 = E-pulse RC.
Only DATA0-7 used. Bus pins used: ADDR0-15, DATA0-7, -VMA (C12), -MEM-RD (B23), -MEM-WR (B24), -RESET (C30).

**Decode (verified on both sch and brd):**
- IC18 7485: B3..B0 = ADDR15..12; A3..A0 = SV3 pins 1,3,5,7 (pulled up by RN2, paired with GND pins
  2,4,6,8). JUMPER INSTALLED = bit 0, OPEN = bit 1. Cascade A=B_I = NOT(-VMA). A=B_O = BOARDSEL.
- **$D000 (1101): SV3 1-2 open, 3-4 open, 5-6 JUMPERED, 7-8 open.** (identical scheme to the ELF card)
- RAM -CER = NAND(BOARDSEL, /ADDR11) -> $D000-$D7FF (2K). RAM -OER = -MEM-RD, R/-WR = -MEM-WR.
- 6845 -CS = NAND(BOARDSEL, ADDR11 AND /ADDR0); RS = ADDR0; R/W = -MEM-WR; E = pulse generator
  (XOR(-MEM-RD,-MEM-WR) AND RC-delayed inverse, R1 10K/C1).
- 74373 output enable (odd addresses in the top half): OC = /(BOARDSEL AND ADDR11 AND ADDR0) -> reading
  $D801 (any odd $D8xx) returns the JP1 byte. JP1: pins 1,2,4,6,8,10,12,14 -> 1D..8D, pin 3 = VCC,
  pin 5 = GND, pin 13 = latch enable ENC (must be high), pins 7,9,11 unconnected.
- SV4: 1-2 = crystal direct, 2-3 = crystal/2 (74x90) dot clock.

**DESIGN ISSUES found 2026-09-18 (as built):**
1. **6845 data register unreachable.** CS needs ADDR0=0 but RS=ADDR0, so RS is always 0: only the
   address register can ever be selected. Fix: select the CRTC on /ADDR1 (or ADDR1=0) and the 373 on
   ADDR1=1, keep RS=ADDR0 -> 6845 at $D800/$D801, ID byte at $D802/$D803. Cut-and-jumper: move
   IC27[D].I (pin 9) and IC1[C].I1 (pin 10) from ADDR0 to ADDR1 (X1 A4).
2. Open-collector 7416 outputs with NO pull-ups on N$5 (/ADDR0), N$16 (373 /OC), N$3 (E-pulse RC feed):
   they rely on LS inputs floating high. Add 4.7K-10K pull-ups.
3. JP1 config bits have no pull-ups and no per-bit GND/VCC pairing (2x7 pairs are 1-2,3-4,...); ENC (13)
   has no pull-up. Works only because LS inputs float high; unjumpered = reads $FF.
4. E pulse width = R1*C1 (C1 value "1", unit unknown); verify >= 6845 min E high before relying on it.

**HARDWARE TEST 2026-09-18 (card on the bus, SV3 5-6 jumpered, NO 6845 fitted):** BOARDSEL/-VMA decode
works, RAM answers at $D000-$D7FF, all 11 address lines independent, no interference with memory card
RAM/ROM. BUT data bits 1 and 2 are OPEN between bus DATA1/DATA2 (X1 A20/A21) and the 7134 I/O1R/I/O2R
(IC15 pins 26/27): writes lost those bits and reads returned whatever the bus last carried. CAUSE: two
bent pins on the 7134 in its socket. FIXED same day; full retest (blocks, address lines, walking bits
with the bus driven to the inverse between write and read) PASSES. Video RAM $D000-$D7FF is good. With no CRTC
fitted the top half $D800+ floats, as expected. The left port (CEL/OEL grounded, MA lines floating with
the socket empty) did not disturb the right port.

**OPEN ISSUE (2026-09-18, sampled whole-memory test):** bus WRITES to block 0 ($0000-$07FF) and block 9
($9000-$97FF) with A0=0 ALSO write the video RAM cell with the same A1-A10 (same data). Rules found:
A0=1 never; blocks 1-8, A-C never; A11=1 never (A11 term honoured); reads never; needs -VMA (comparator
cascade) but NOT -BUS-EN; edge-triggered: only when -MEM-WR FALLS while the address is already static
(holding -MEM-WR low and then changing the address to $0010 does NOT write). No comparator-input fault can
produce {0,9,D}. PROVED EDGE-ONLY: with -MEM-WR held low and the data changed, the video cell keeps the
FIRST value (block D keeps the last = a normal level write); a second edge writes again; ordering and
settle time irrelevant; happens even with -MEM-RD held low (XOR=0, no E-pulse), so the E-pulse RC is
NOT the cause. RN2 was 10K; user swapped to 1K on 2026-09-18: NO CHANGE (still exactly blocks 0 and 9).
So the chip-enable glitches low for ~ns at the strobe edge for those two blocks. Reproduces after a
power cycle (2026-09-19, `alias_min.py`); independent of the data value and of D8-15; block 9 obeys
the same A0=0 rule. Exact rule: A14=0, A13=0, A15==A12 (i.e. high nibble 0000 or 1001), A11=0, A0=0,
-MEM-WR falling edge, -VMA asserted. Relative to the jumper code 1101 that means: bit2 UNEQUAL and
bits 3 and 0 either both equal or both unequal. 2026-09-19 WITH THE MEMORY CARD REMOVED the fault is unchanged (still exactly blocks 0 and 9), so it
is entirely on the video card (+ bus tester as the bus master). A bare -MEM-WR pulse with the data bus
floating writes FF into the cell (the glitch writes whatever is on the bus). Video card alone: still
needs -VMA (5/5), which only feeds the 7485 cascade input -> the false select passes through IC18's
A=B output. Triggers ONLY on the -MEM-WR falling edge at a static alias address; NOT on -VMA edges,
A0 edges, or address transitions with WE held low (the earlier "9010->0010 wrote" was the WE edge at
9010). Rule in comparator terms (A=1101): bit2 UNEQUAL (A14=0) and bit3-eq == bit0-eq (A15==A12).
Next: scope IC18 pin 6 / IC19 pin 6 vs -MEM-WR; or simply swap IC18 (74LS85) and retest; also try a
74HCT85. Software discriminators are exhausted. The only glitch
sequence that yields exactly {D,9,0} is the comparator's A side passing 1101 -> 1001 -> 0000 (A2 dips
first, then A0+A3), or equivalent on B. Next step needs a scope: BOARDSEL (IC18 pin 6) triggered on the
-MEM-WR falling edge during a block-0 write; also check IC18's decoupling and the card's ground pins.
Design note (not a bug): 7134 left-port I/O6 (pin 22, VDATA6) is intentionally unconnected; char ROM
2732 gets VDATA0-5 (64-char set) + VROWS0-2, A9-A11 grounded; VDATA7 = cursor/inverse XOR. Harmless for the video card's own use; matters because block-0 writes
(zero page, stack region) will scribble on the screen RAM.

In YACC1-D (2026-09-20): hardware/cards/video/eagle/v1.0-fusion-export-2026-09-18/ holds Video_1.0.sch + Video_1.0.brd
(the export's 'Blank V3.1.brd' renamed by the migration RENAMES table so Eagle pairs them); README there lists the known issues.

**2026-09-21 UPDATE:** the KiCad netlist proof found the card's `+5V` net (IC1 74ALS08, IC2 74LS373, IC15 pin 2, RN2,
R10/R12, all decoupling caps) has NO source - separate from `VCC` (bus pins + implicit 74xx power pins), nothing joins
them. Ken wired +5V to VCC -> the block-0/9 WRITE-THROUGH FAULT IS GONE: `tests/video/video_ram_test.py` 8/8 on the full
1K, `tools/alias_min.py` = no fault. 6845 A0 issue precisely: -CS = NAND(BOARDSEL, A11 AND /A0) (IC19.3 <- IC1.11 <- IC27.8
= /A0 via the pull-up-less 7416), RS = A0 -> only the address register reachable; bench fix = IC1 pin 13 tied high, then
$D400 = address reg, $D401 = data reg. Bus tester FTDI port = /dev/cu.usbserial-AB6WZCQX (flaky enumeration: appeared,
dropped, came back). Commit 741b26e.

**PENDING BENCH JOB (Ken, planned for 2026-09-22): fit the 6845 with RS moved from A0 to A1.** The earlier idea (tie IC1
pin 13 high) is WRONG - odd addresses in the CRTC half drive the JP1 read-back latch IC2 (74LS373) onto the bus, so RS
must move instead. Procedure = hardware/cards/video/docs/fix-6845-register-select.md (commit b2af139): bend 6845 pin 24
(RS) out of the socket, wire it to IC15 pin 41 (ADDR1; alt pickup = bus connector X1 pin A4 solder tail). Result: $D400 =
address reg, $D402 = data reg, $D401/$D403 = JP1 latch. Verify with tests/video/hold_address.py D402 (pin 25 low, pin 24
high) and, chip fitted, write/read R12 via $D400/$D402. Also still open: 10k RN2 is back in (done), +5V/VCC bench wire in.

**KICAD IS THE MASTER FOR THE VIDEO CARD (Ken 2026-09-21; Fusion abandoned):** `hardware/cards/video/kicad/v1.1/` =
hand-maintained project (MASTER marker file; eagle_to_kicad_all.py refuses to touch it; audit bucket). Done in v1.1: +5V
net folded into VCC (76 pads/tracks renamed, joining F.Cu track beside C28, proof 116/116, commit 05cbf0b). Still to do
in v1.1: RS to A1 (after the bench job), 7416 pull-ups. v1.0-fusion-export folder = record of the built card.
2026-09-25: ROM 2026-09-25 (MD5 3ebc6789..., NOT burned) adds video unit: reset probe of $D000 -> VIDPRES $0FF0, VIDMIR $0FF1 (mirror off by default, VIDAUTO EQU 0), monitor V command (VS VP VI VC VM VW VB VF VD VR), entry $FFBC (JSR vidctl), /BIN/VIDEO, emulator -V/-W/-N. CRTC $D800/$D802 CONFIRMED by Ken 2026-09-25 (RAM $D000-$D7FF); 80x24 assumed, 2513-style charset assumed, 10 MHz dot clock assumed. Commits 3a7e5ae, 9a94082.
SUPERSEDED: every older line above that puts the 6845 at $D400/$D401/$D402 is wrong - Ken 2026-09-25: video RAM $D000-$D7FF, 6845 half $D800-$DFFF, address reg $D800, data reg $D802 (RS on A1), odd = JP1 latch (docs fixed in dcef1ee).
