# SAP-8X: An 8-Bit TTL CPU Design

A complete, buildable 8-bit CPU using only 74-series TTL logic, plus standard SRAM/EEPROM for memory and microcode. Roughly 45 logic ICs. Target clock: 2–4 MHz with 74LS, faster with 74F or 74HCT.

---

## 1. Architecture Overview

| Parameter | Choice |
|---|---|
| Data width | 8 bits |
| Address width | 16 bits (64 KB) |
| Architecture | Von Neumann, single internal data bus |
| Control | Microcoded (EPROM-based), horizontal-ish |
| Registers | A (accumulator), B (operand), X (index), SP, PC, MAR, IR, FLAGS |
| ALU | 2× 74181 + 74182 carry lookahead |
| Stack | Hardware SP, stack fixed in page $01 (6502-style) |
| Memory | 32 KB EEPROM (28C256) + 32 KB SRAM (62256) |

**Bus discipline:** One 8-bit internal data bus. Every register that can drive the bus does so through a tri-state buffer (74244/74245) or has built-in tri-state outputs (74374). Exactly one output-enable is asserted per microcycle — enforced by using a 74138 decoder to generate OE signals, which makes bus contention structurally impossible.

The 16-bit address bus is driven by either PC or MAR, selected with 74257 quad 2:1 muxes (4 chips), so you don't need a separate MAR-load cycle for instruction fetches.

---

## 2. Module-by-Module Design

### 2.1 Clock and Reset
- Crystal oscillator can (4 MHz) → 74161 as divide-by-2/4 for selectable speed
- Debounced single-step pushbutton via 74279 (SR latches), selected with a toggle
- Power-on reset: RC + 7414 Schmitt inverter, also drives microcode-sequencer clear

**Chips: 3** (osc can, 74161, 7414; 74279 optional for single-step)

### 2.2 Program Counter (PC)
- 4× **74161** synchronous 4-bit counters, cascaded with RCO → ENT
- Parallel load from the data bus for jumps: low byte latched into a temp register first, then both bytes loaded together (handled in microcode via the transfer register, §2.8)
- Outputs drive address mux directly (74161 outputs are always active; the mux provides isolation)

**Chips: 4**

### 2.3 Memory Address Register (MAR)
- 2× **74273** octal D-registers (MARL, MARH), loaded from the internal bus one byte per microcycle
- Feeds the address mux

**Chips: 2**

### 2.4 Address Mux
- 4× **74257** quad 2:1 mux with tri-state outputs, selecting PC vs MAR onto the external address bus
- Select line `ASEL` comes straight from the microcode word

**Chips: 4**

### 2.5 Memory
- **28C256** EEPROM at $0000–$7FFF (A15=0), **62256** SRAM at $8000–$FFFF (A15=1)
- Address decode: A15 + 1 gate of a 7400 → chip selects. (Invert for ROM CS.)
- **74245** transceiver between external memory data pins and the internal bus, direction controlled by `R/W̄` from microcode

**Chips: 2 memory + 1 transceiver + shared glue**

### 2.6 Instruction Register (IR)
- 1× **74273**, loaded from the bus during fetch
- Outputs go only to the microcode address inputs (never back onto the bus)

**Chips: 1**

### 2.7 Register File: A, B, X
Each register is:
- 1× **74377** octal register with clock-enable (load when its LD line is low at the clock edge)
- 1× **74244** tri-state buffer for driving the bus

A and B also feed the ALU inputs directly (hardwired, in parallel with their bus buffers — the ALU has its own output buffer, so no conflict).

**Chips: 6** (3 registers × 2)

### 2.8 Transfer Register (T)
One extra hidden 74377+74244 pair. Microcode uses it to stage the low byte of 16-bit operands (jump targets, absolute addresses) and as ALU scratch. Invisible to the programmer, enormously simplifies microcode.

**Chips: 2**

### 2.9 ALU
- 2× **74181** (4-bit ALU slices) + 1× **74182** carry-lookahead generator
- Inputs: A register (operand A), B register (operand B) — hardwired
- 5 function-select lines (S0–S3, M) + carry-in come from microcode
- Output → 74244 tri-state buffer → bus
- Gives you ADD, SUB (via A + B̄ + 1), AND, OR, XOR, INC, DEC, pass-through, and more for free

**Shift/rotate:** the 74181 doesn't shift. Cheapest trick: route ALU output through a pair of **74157** muxes that select either straight-through or shifted-by-one wiring before the bus buffer. Carry flag supplies/receives the end bit for rotates.

**Chips: 4 (core) + 2 (shifter, optional)**

### 2.10 Flags Register
- 1× **74175** quad D flip-flop storing **C, Z, N, V**
- Z: 8-input NOR of ALU output via 74260 + gate (or a 74688 comparator against $00)
- N: ALU bit 7. C/V: from 74181/74182 carry chain
- Loaded only when microcode asserts `LDF`
- C and Z feed the microcode address (conditional branching), N and V available via a mux if you extend

**Chips: 2–3**

### 2.11 Stack Pointer (SP)
- 2× **74193** up/down counters = 8-bit SP
- High address byte hardwired to $01 → stack lives at $0100–$01FF
- Microcode asserts `SPINC`/`SPDEC`; SP drives MARL via its own 74244 when `SPOE` is asserted

**Chips: 3**

### 2.12 Control Unit (the heart)
Microcode ROM approach — no random-logic decoding:

**Microcode address (13 bits → fits a 28C64 ×3):**
| Bits | Source |
|---|---|
| 12–5 | IR opcode (8 bits) |
| 4–1 | Step counter (74161, cleared by `µRESET` microinstruction bit) |
| 0 | Selected condition flag (via 74151 mux: C, Z, N, V, 0, 1) |

**Control word (24 bits = 3× 28C64 EPROMs):**

| Bits | Function |
|---|---|
| 0–3 | Bus output-enable select → 74154 decoder (A, B, X, T, ALU, MEM, SP, FLAGS→bus, none…) |
| 4–7 | Register load select → second 74154 (A, B, X, T, IR, MARL, MARH, FLAGS, MEM-write, PCL, PCH, none…) |
| 8–12 | ALU S0–S3, M |
| 13 | ALU carry-in |
| 14 | PC increment |
| 15 | PC load |
| 16 | ASEL (PC/MAR onto address bus) |
| 17 | R/W̄ |
| 18–19 | SP inc / dec |
| 20–21 | Flag-condition mux select |
| 22 | LDF (latch flags) |
| 23 | µRESET (end of instruction → step counter to 0) |

Using decoders for the OE/LD fields (one-hot by construction) is what keeps the chip count and the bus-contention risk down.

**Chips: 3 EPROM + 1 step counter + 2× 74154 + 1× 74151 + glue ≈ 8**

---

## 3. Instruction Set (example, easily extended)

Opcodes are free choices since microcode decodes them. A practical starter set:

| Mnemonic | Operation | Bytes | ~Cycles |
|---|---|---|---|
| NOP | — | 1 | 2 |
| LDA #imm / LDA abs / LDA abs,X | A ← operand | 2–3 | 3–6 |
| LDB / LDX (same modes) | B/X ← operand | 2–3 | 3–6 |
| STA abs / abs,X | mem ← A | 3 | 5–6 |
| ADD / ADC / SUB / SBC | A ← A op B | 1 | 3 |
| AND / OR / XOR | A ← A op B | 1 | 3 |
| INC / DEC / CMP | flags / A | 1 | 3 |
| SHL / ROL / SHR / ROR | shift A | 1 | 3 |
| JMP abs | PC ← addr | 3 | 5 |
| JZ / JNZ / JC / JNC abs | conditional | 3 | 4–5 |
| PHA / PLA | stack push/pop A | 1 | 4 |
| JSR abs / RTS | call/return | 3/1 | 8/6 |
| HLT | stop clock (gate via flip-flop) | 1 | — |

**Indexed addressing** (abs,X) works by running the fetched address-low byte and X through the ALU (B temporarily ↔ X via the bus, or add a second ALU input mux if you want it clean), with carry propagated into the high byte — two extra microcycles.

### Sample microcode: `LDA abs` (opcode fetch already standard)
```
step 0: ASEL=PC, MEM→bus, LD IR, PC++        ; fetch opcode (common to all)
step 1: ASEL=PC, MEM→bus, LD T,  PC++        ; addr low → T
step 2: ASEL=PC, MEM→bus, LD MARH, PC++      ; addr high → MARH
step 3: T→bus, LD MARL                       ; addr low → MARL
step 4: ASEL=MAR, MEM→bus, LD A, LDF, µRESET ; A ← mem, done
```

---

## 4. Bill of Materials (logic)

| Function | Parts | Qty |
|---|---|---|
| Clock/reset | osc, 74161, 7414, (74279) | 3–4 |
| PC | 74161 | 4 |
| MAR | 74273 | 2 |
| Addr mux | 74257 | 4 |
| Mem transceiver | 74245 | 1 |
| IR | 74273 | 1 |
| A, B, X, T regs | 74377 + 74244 | 8 |
| ALU | 74181 ×2, 74182 | 3 |
| Shifter (opt) | 74157 | 2 |
| Flags | 74175, 74260, gates | 3 |
| SP | 74193 ×2, 74244 | 3 |
| Control | 28C64 ×3, 74161, 74154 ×2, 74151 | 7 |
| Glue | 7400/7404/7408 | 3 |
| **Total logic** | | **~44–48** |
| Memory | 28C256, 62256 | 2 |

---

## 5. Design Notes & Gotchas

1. **One driver per bus, always.** The 74154 one-hot decoding of the OE field guarantees this. If you ever hand-wire OEs instead, a momentary two-driver overlap will work on the bench and fail intermittently forever.
2. **Registered control outputs.** EPROMs glitch while their address settles. Either (a) latch the 24-bit control word in 3× 74374 clocked on the opposite clock edge, or (b) use a two-phase clock where ROM outputs settle in φ1 and registers clock on φ2. Option (a) costs 3 chips and saves your sanity.
3. **74181 subtraction** is A − B − 1 + Cin: set Cin=1 for SUB, pass the flag for SBC. Easy to get backwards; verify with a logic probe before writing more microcode.
4. **EEPROM speed**: a 150 ns 28C256 limits fetch timing more than the TTL does. Budget your clock around ROM access + transceiver + register setup; at 2 MHz (500 ns) you have huge margin, at 8 MHz you don't.
5. **Decoupling**: 0.1 µF per chip, no exceptions, plus bulk caps per board. TTL ground bounce on a 45-chip wire-wrap board is the #1 source of "haunted" behavior.
6. **Bring-up order**: clock → PC free-running on the address bus → ROM fetch into IR → NOP loop → one register → ALU → flags → jumps → stack. Each stage is observable with LEDs on the buses before the next exists.

## 6. Possible Extensions
- Second ALU-input mux (74157 ×2) so the ALU B-side can take X or T → cleaner indexed addressing and 16-bit pointer math
- Memory-mapped I/O at $FF00–$FFFF: one 74688 comparator + 74138 gives 8 I/O selects (UART via 6850, output latch, input buffer)
- Interrupts: latch an IRQ line, force opcode $FF into IR at fetch (one 74244 forcing the bus), microcode it as "push PC, jump to vector"
