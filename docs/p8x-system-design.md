# P8X: An 8-Bit TTL CPU — Bus/Backplane Card Architecture

Reorganized around a passive backplane with six plug-in cards and the 4×16-bit pointer register bank as the architectural centerpiece. The PC, SP, and MAR of the original SAP-8X design are all subsumed by the pointer bank.

**Cards:**
1. Control / Microcode card (clock, reset, sequencer, microcode EPROMs, IR, front-panel run controls)
2. Register Bank card (P0–P3, the 16-bit up/down pointer set)
3. ALU card (A, B, T, T2 registers, 74181 ALU, shifter, flags)
4. Memory card (ROM, RAM, address decode)
5. I/O card (toggle-switch input port, LED output port, RS-232 via 6850 ACIA)
6. CF-IDE card (CompactFlash in 8-bit True IDE mode, memory-mapped at $FF10–$FF17)

Total: ~75 logic ICs across the cards. Each card is independently testable on the backplane.

---

## 1. Programmer's Model

| Register | Width | Role |
|---|---|---|
| P0 | 16 | Program counter |
| P1, P2 | 16 | General pointers (Forth IP/W, BASIC text pointer, etc.) |
| P3 | 16 | Stack pointer (empty-descending: points at next free byte) |
| A | 8 | Accumulator (ALU operand A) |
| B | 8 | Operand register (ALU operand B) |
| FLAGS | 4 | C, Z, N, V |
| T, T2 | 8 | Hidden microcode temporaries (not programmer-visible) |

Every pointer supports synchronous **load, hold, increment, decrement** (full 16-bit carry/borrow). The address bus is *always* driven by the currently selected pointer — there is no separate MAR and no address mux. An instruction fetch is simply "select P0, read memory, increment."

All I/O is memory-mapped in page **$FF00–$FFFF**.

Memory map:
- `$0000–$7FFF` EEPROM (monitor, interpreter)
- `$8000–$FEFF` SRAM
- `$FF00–$FFFF` I/O page (RAM disabled here)

Reset forces P0 to $0000 (pointer clear via 74169 synchronous load of zeros — see §4.2).

---

## 2. Backplane

Passive backplane, **DIN 41612 96-pin (rows A/B/C)** connectors on 100×160 mm Eurocards. Row B is a solid ground guard between the signal rows (B3–B26 = GND); B27 = CLRC, B28–B30 = SPARE9–11 (rev C3). See [p8x-bus-definition.md](../hardware/backplane/p8x-bus-definition.md) for the full pin map.

### 2.1 Bus signals

| Group | Signals | Count | Driven by |
|---|---|---|---|
| Data bus | D0–D7 | 8 | one card per microcycle (one-hot by decode) |
| Address bus | A0–A15 | 16 | Register Bank card (always) |
| Data source select | DOE0–3 | 4 | Control card |
| Data destination select | DLD0–3 | 4 | Control card |
| Pointer select | PSEL0–1 | 2 | Control card |
| Pointer count | PINC, PDEC | 2 | Control card |
| ALU function | ALUS0–3, ALUM, CIN | 6 | Control card |
| Shifter | SH0–SH1 | 2 | Control card |
| Flag latch | LDF | 1 | Control card |
| Clock | CLK, CLK̄ | 2 | Control card |
| Reset | RES̄ | 1 | Control card |
| Power | +5 V, GND | rest | PSU |

≈ 48 signals + power/ground, plus FC/FZ/FN/FV flag lines and 8 spares — fits the 96-pin connector with room to spare.

### 2.2 Distributed field decoding

The 4-bit **DOE** (data output enable) and **DLD** (data load) fields are broadcast *encoded* on the backplane; **each card carries its own 74154 (or 74138) decoder** and responds only to its assigned codes. This keeps the backplane narrow, makes bus contention structurally impossible (one-hot per field), and means adding a card never requires rewiring the others.

**DOE field assignments (who drives D0–D7):**

| Code | Source | Card |
|---|---|---|
| 0 | none (bus idle, pulled up) | — |
| 1 | A | ALU |
| 2 | B | ALU |
| 3 | T | ALU |
| 4 | T2 | ALU |
| 5 | ALU result (via shifter) | ALU |
| 6 | FLAGS | ALU |
| 7 | MEM (read) | Memory / I/O |
| 8 | PTRL — low byte of selected pointer | Reg Bank |
| 9 | PTRH — high byte of selected pointer | Reg Bank |

**DLD field assignments (who latches D0–D7 at the clock edge):**

| Code | Destination | Card |
|---|---|---|
| 0 | none | — |
| 1 | A | ALU |
| 2 | B | ALU |
| 3 | T | ALU |
| 4 | T2 | ALU |
| 5 | FLAGS (restore) | ALU |
| 6 | IR | Control |
| 7 | MEMW — memory/I-O write strobe | Memory / I/O |
| 8 | PTRL — low byte of selected pointer | Reg Bank |
| 9 | PTRH — high byte of selected pointer | Reg Bank |

Note `MEMW` is just another destination: the Memory and I/O cards decode DLD=7 and generate a write pulse (gated with CLK̄ for clean timing).

---

## 3. Control / Microcode Card

### 3.1 Microcode addressing (13 bits → 8K × 32)

| Bits | Source |
|---|---|
| 12–5 | IR (opcode, 74273) |
| 4–1 | Step counter (74161) |
| 0 | Selected condition (74151 mux: 0, 1, C, Z, N, V, …) |

### 3.2 Control word (32 bits, 4× 28C64 EPROM)

| Bits | Field |
|---|---|
| 0–3 | DOE |
| 4–7 | DLD |
| 8–9 | PSEL |
| 10 | PINC |
| 11 | PDEC |
| 12–16 | ALU S0–S3, M |
| 17 | CIN |
| 18–19 | SH (pass / left / right / rotate) |
| 20 | LDF |
| 21–23 | FCOND (condition mux select) |
| 24 | µRESET (step counter → 0, ends instruction) |
| 25 | HALT (gates clock off; resume via front panel) |
| 26–31 | spare |

**Pipeline latch:** the 32 EPROM outputs are registered in 4× **74374** clocked on the opposite edge (CLK̄), so glitching ROM outputs never reach the backplane. Non-negotiable for reliability.

### 3.3 Also on this card
- Crystal oscillator + 74161 divider (÷1/2/4/8 selectable)
- Power-on/pushbutton reset (RC + 7414), drives RES̄ and clears step counter and IR
- **Front-panel run controls:** RUN/HALT toggle, single-STEP pushbutton (debounced 74279), clocked through a 7474 synchronizer so the machine always stops on a microcycle boundary. HALT microcode bit ORs into the same stop logic.

**BOM:** 4× 28C64, 4× 74374, 74273 (IR), 74161 (step), 74161 (clk div), 74151 (cond), 74154 (DLD decode for IR), 7414, 7474, 74279, osc, glue ≈ **15 chips**

---

## 4. Register Bank Card

The biggest card, and the heart of the machine.

### 4.1 Structure
- **16× 74169** synchronous up/down counters: 4 chips per pointer, RCO→ENT cascaded for full 16-bit carry
- **Pointer selection:** PSEL → 74139; the selected pointer's outputs are enabled onto an on-card 16-bit *pointer bus* via 2× 74244 per pointer (8× 74244 total)
- **Address bus drivers:** pointer bus → 2× 74244 → backplane A0–A15 (always enabled — this card owns the address bus)
- **Byte readback:** pointer bus hi/lo → 2× 74257 mux → 74244 → data bus (DOE codes 8/9)
- **Byte loads:** DLD codes 8/9 + PSEL → 74138 → eight load strobes (4 pointers × 2 bytes). A byte load asserts L̄D̄ on just the two 74169s of that byte; the other byte's chips hold
- **Inc/Dec:** PINC ∨ PDEC → count-enable on the selected pointer's slices (gated through the 74139 selection); PDEC drives U/D̄. Count direction/enable apply to all 4 slices so carry propagates 16 bits

### 4.2 Reset behavior
RES̄ forces a synchronous load of $0000 into P0 (gates the P0 load strobes and pulls the load inputs low via the data-bus pull-downs / forced-zero buffer). One 74244 wired to all-zeros, enabled at reset, does this cleanly.

### 4.3 Timing note
74169s are synchronous: during a microcycle the *current* value drives the address bus; load/inc/dec take effect at the clock edge. So "read MEM at P3 and decrement P3" in one microcycle uses the pre-decrement address — which is exactly what the empty-descending stack convention wants (write-then-dec for push, inc-then-read for pop).

**BOM:** 16× 74169, 8× 74244 (select), 2× 74244 (addr drive), 2× 74257 + 74244 (readback), 74139, 74138, zero-buffer 74244, gates ≈ **32 chips**

(If one Eurocard gets crowded, this splits naturally into two half-bank cards — P0/P1 and P2/P3 — sharing the bus pinout.)

---

## 5. ALU Card

- **A, B, T, T2:** each 74377 (load) + 74244 (bus drive) = 8 chips. A and B feed the 74181 inputs directly
- **ALU:** 2× 74181 + 74182, function lines straight from backplane
- **Shifter:** 2× 74157 after the ALU (pass / <<1 / >>1, carry in/out for rotates), then 74244 to the bus
- **Flags:** 74175 (C, Z, N, V), Z from 74260+gate over the shifter output, latched on LDF. FLAGS↔bus paths for push/pop of status
- **Decode:** 1× 74154 for DOE codes 1–6, 1× 74154 for DLD codes 1–5

**BOM:** ≈ **18 chips**

---

## 6. Memory Card

- **28C256** EEPROM, selected when A15 = 0
- **62256** SRAM, selected when A15 = 1 **and not** the I/O page: 7430 (8-input NAND on A8–A15) detects $FFxx and inhibits RAM CS
- **74245** transceiver to the data bus: direction from read (DOE=7) vs write (DLD=7); enabled only for on-card addresses
- Write pulse: DLD=7 ∧ CLK̄ → W̄Ē, giving address/data setup in the first half-cycle and a clean strobe in the second

**BOM:** 28C256, 62256, 74245, 7430, 74154 or 74138 + gates ≈ **6 chips**

---

## 7. I/O Card

Decodes the $FFxx page (same 7430 trick) plus A1–A2 via a 74138 → up to 8 port selects.

| Address | Port |
|---|---|
| $FF00 | **Switch input**: 8 toggle switches → 74244 → data bus on read |
| $FF02 | **LED output**: 74374 latch → 8 LEDs (write) |
| $FF04–05 | **6850 ACIA** control/status + data, RS-232 |

- **6850 ACIA** + **MAX232** (the one non-TTL concession for RS-232 levels — alternatively 1488/1489 with ±12 V) + baud clock from a 74161 divider chain or a dedicated 2.4576 MHz can ÷16
- **Bus-monitor LEDs (passive)**: 3× 74244 permanently buffering A0–A15 and D0–D7 to LED banks. Costs nothing logically, and with the single-step button on the control card it gives you a full Altair-style "watch the machine think" front panel
- Software handles everything: the monitor program in ROM polls the switches and ACIA — no bus-mastering front panel needed since the ROM bootstraps the machine

**BOM:** 6850, MAX232, 74244 (switches), 74374+LEDs, 7430, 74138, baud divider, 3× 74244 monitors ≈ **10 chips**

---

## 8. Microcode Examples

Notation: one line per microcycle. Every instruction begins with the shared fetch cycle.

### Fetch (all instructions, step 0)
```
PSEL=P0, DOE=MEM, DLD=IR, PINC
```

### LDA (P1)+   — load A indirect via P1, post-increment
```
0: fetch
1: PSEL=P1, DOE=MEM, DLD=A, PINC, LDF, µRESET
```
**Two cycles.** This is the instruction that makes the interpreter easy.

### LDA #imm
```
0: fetch
1: PSEL=P0, DOE=MEM, DLD=A, PINC, LDF, µRESET
```

### STA (P2)
```
0: fetch
1: PSEL=P2, DOE=A, DLD=MEMW, µRESET        ; add PINC/PDEC variants as separate opcodes
```

### JMP abs
```
0: fetch                                    ; P0 → operand lo
1: PSEL=P0, DOE=MEM, DLD=T, PINC            ; target lo → T
2: PSEL=P0, DOE=MEM, DLD=PTRH               ; target hi → P0H (no PINC!)
3: PSEL=P0, DOE=T,   DLD=PTRL, µRESET       ; T → P0L
```
Step 2 reads memory using the *old* P0 (synchronous load — value changes at the edge), so loading P0H mid-fetch is safe.

### JZ abs (condition bit selects between two microcode paths)
```
cond=0: steps 1–2 just PINC twice past the operand, µRESET
cond=1: same as JMP abs
```

### JSR abs (pushes address of operand-lo; RTS compensates)
```
0: fetch                                    ; P0 → operand lo = return-2
1: PSEL=P0, DOE=PTRH, DLD=T2                ; return hi → T2
2: PSEL=P0, DOE=PTRL, DLD=T                 ; return lo → T
3: PSEL=P3, DOE=T2,  DLD=MEMW, PDEC         ; push hi
4: PSEL=P3, DOE=T,   DLD=MEMW, PDEC         ; push lo
5: PSEL=P0, DOE=MEM, DLD=T,  PINC           ; target lo → T
6: PSEL=P0, DOE=MEM, DLD=PTRH               ; target hi → P0H
7: PSEL=P0, DOE=T,   DLD=PTRL, µRESET       ; → P0L
```

### RTS
```
0: fetch
1: PSEL=P3, PINC                            ; SP → pushed lo
2: PSEL=P3, DOE=MEM, DLD=T, PINC            ; lo → T
3: PSEL=P3, DOE=MEM, DLD=T2                 ; hi → T2  (wait, hi is at SP now)
   — order: push was hi-then-lo, so pop is lo-then-hi: step 2 reads lo, step 3 reads hi ✓
4: DOE=T2, DLD=PTRH (PSEL=P0)
5: DOE=T,  DLD=PTRL (PSEL=P0)
6: PSEL=P0, PINC
7: PSEL=P0, PINC, µRESET                    ; skip the operand bytes
```

### Forth NEXT (P1 = IP, jump indirect through threaded list)
```
0: fetch (the NEXT opcode itself, if implemented as an instruction)
1: PSEL=P1, DOE=MEM, DLD=T,    PINC         ; word addr lo
2: PSEL=P1, DOE=MEM, DLD=PTRH, PINC → P0H   ; word addr hi
3: DOE=T, DLD=PTRL (PSEL=P0), µRESET
```
**Four cycles for the Forth inner interpreter.** At 2 MHz that's 500k threaded dispatches/sec.

---

## 9. Suggested Instruction Set Additions over Rev 1

Beyond the Rev 1 set (loads/stores, ALU ops, jumps, stack, JSR/RTS):

| Mnemonic | Operation |
|---|---|
| LDA/STA (Pn)+ / (Pn)− / (Pn) | indirect with post-inc / post-dec / plain, n = 1,2 |
| LDP n,#imm16 | load pointer immediate (3 bytes) |
| INP n / DEP n | 16-bit pointer inc/dec |
| TPA n / TAP n (lo/hi) | pointer byte ↔ A transfers |
| PHP / PLP | push/pop flags |
| PSH n / POP n | push/pop a full pointer (microcoded via T/T2) |

Opcode space is wide open (256 slots, ~50 used).

---

## 10. Build & Bring-Up Order

1. **Backplane + PSU**: verify power on every connector, grounds solid
2. **Control card alone**: scope CLK/CLK̄, verify reset, single-step, and that the pipeline latch outputs a stable all-zeros word with blank-pattern EPROMs
3. **+ Register Bank**: burn microcode that does nothing but `PSEL=P0, PINC` forever → watch the address LEDs count. Then test load, dec, each pointer
4. **+ Memory card**: program ROM with $EA-style NOPs, microcode the fetch → IR should track ROM contents (probe IR or temporarily bus it)
5. **+ ALU card**: registers first (bus loopback A→bus→B), then ALU functions against a truth-table program, then flags
6. **+ I/O card**: LED port write from microcode, switch read, then ACIA loopback (TX→RX jumper) before wiring real RS-232
7. **Monitor program** in ROM: hex dump/deposit/go over serial — from there everything else is software

## 11. Power & Practical Notes
- ~75 LS-TTL chips ≈ 1.5–2 A at 5 V; size the PSU at 4–5 A with per-card 10 µF bulk + 0.1 µF per chip
- Keep CLK/CLKB on adjacent backplane pins with guard traces; AC termination (100 Ω + 150 pF to GND) footprints are provided DNP at the far slot — populate only if scope shows ringing. Do not use Thevenin termination: it biases lines into the HCT threshold region and wastes 25 mA per line at idle (see p8x-backplane-design.md §3)
- Wire-wrap or PCB both fine at ≤4 MHz; keep the 74181 carry chain and the 74169 RCO cascades short
- 74169 vs 74193: 74169 is fully synchronous (single clock + direction pin), which is why it's specified here; 74193's dual-clock scheme is glitch-prone in this application
