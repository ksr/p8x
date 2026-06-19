# P8X Glossary — acronyms & signals

A reference for the abbreviations, signal names, and register/bus terms used
across the P8X project. Authoritative sources where a term has one:
- control word / opcodes → `microcode/genucode.py`
- bus pinout → `hardware/backplane/p8x-bus-definition.md`
- monitor/BIOS ABI → `docs/p8x-monitor.md`
- parts → `hardware/p8x-bom.csv` (from `generators/gen_bom.py`)

---

## General abbreviations

| Term | Meaning |
|------|---------|
| **P8X** | The project: a hand-built 8-bit microcoded TTL CPU (~130 74HCT chips, 10-slot DIN 41612 backplane). |
| **ISA** | Instruction Set Architecture — the opcodes/registers a programmer sees. |
| **ABI** | Application Binary Interface — the fixed binary contracts (entry addresses, layouts, conventions) that let separately-built code interoperate. See the BIOS jump table, the TPA, SBUF/LBA. |
| **API** | Application Programming Interface — the *source*-level contract (vs ABI, the binary one). |
| **BIOS** | The monitor's published service routines (jump table at `$0100`). |
| **TPA** | Transient Program Area — RAM where `RUN`-loaded programs and the OS's `>`-redirect buffer live. `$B000` (rev C; was `$A000`). |
| **BOM** | Bill of Materials — the orderable parts list (`hardware/p8x-bom.csv`). |
| **DNP** | Do Not Populate — a footprint laid down on the board but left unstuffed (provisioned for later). |
| **DRC** | Design Rule Check — the EDA tool's electrical/clearance verification of a routed board. |
| **THT / SMD** | Through-Hole Technology / Surface-Mount Device. P8X is all THT. |
| **NOS** | New Old Stock — obsolete parts bought new from old inventory (e.g. the 6850, 74181). |
| **R/A** | Right-Angle (connector mounting orientation). |
| **LSB / MSB** | Least / Most Significant Byte (or Bit). |
| **TTL / HCT** | Transistor-Transistor Logic; 74HCT = high-speed CMOS, TTL-compatible levels (5 V). |

---

## Registers & pointers

| Name | Meaning |
|------|---------|
| **A** | Accumulator — ALU operand A and primary result register. |
| **B** | Operand register — the ALU's second (B-side) operand. |
| **T, T2** | Microcode scratch byte registers. `T` is also selectable as the ALU B operand via **BSEL** (rev C); `LDT` loads it. |
| **P0–P3** | The 4×16-bit pointer bank. **P0** = PC (program counter), **P3** = SP (stack pointer, empty-descending from `$FEFF`); P1/P2 are general pointers. |
| **PT** | Hidden microcode-only scratch pointer (PSEL=4), used for absolute addressing; not programmer-visible. |
| **IR** | Instruction Register — holds the current opcode. |
| **FLAGS** | The 4-bit status register (C, Z, N, V). |

---

## Flags

| Flag | Meaning |
|------|---------|
| **C** | Carry. Conventional active-high (rev B): `C=1` = carry-out (ADD) / no-borrow i.e. `A≥B` (SUB/CMP). Unsigned ordering. |
| **Z** | Zero — result was 0. |
| **N** | Negative — result bit 7 set. |
| **V** | Overflow — signed arithmetic overflow (rev C). Valid after ADD/SUB/CMP. Signed ordering uses `N^V`. |

---

## Microcode control word (32 bits)

The word burned to the 4× 28C64 EPROMs and interpreted by the emulator. Bit map
(authoritative: `genucode.py`); each bit is latched in control-card pipeline
`U14–U17` and, where needed, routed across the backplane.

| Bits | Signal | Meaning |
|------|--------|---------|
| 0–3 | **DOE** | Data-Output Enable — which source drives the data bus (idle/A/B/T/T2/ALU/FLAGS/MEM/PTRL/PTRH). |
| 4–7 | **DLD** | Data-LoaD — which destination latches the bus at the clock edge. |
| 8–10 | **PSEL** | Pointer SELect (P0–P3 + PT=4; 3-bit since rev B). |
| 11 | **PINC** | Increment the selected pointer. |
| 12 | **PDEC** | Decrement the selected pointer. |
| 13–16 | **ALUS** | 74181 ALU function select S0–S3. |
| 17 | **ALUM** | 74181 mode (M): logic vs arithmetic. |
| 18 | **CIN** | Carry-IN pin to the 74181 (active-low carry). |
| 19 | **SH0** | Shifter: shift left. |
| 20 | **SH1** | Shifter: shift right. |
| 21 | **LDF** | Latch Flags — load all four flags from the ALU. |
| 22–24 | **FCOND** | Condition-mux select for branches: never/always/C/Z/N/V/LT/LE. |
| 25 | **µRST / URST** | Microcode reset — step counter → 0, ends the instruction. |
| 26 | **HALT** | Gate the clock off (resume via front panel / reset). |
| 27 | **LDZN** | Latch Z,N from the bus on loads (without touching C/V). |
| 28 | **SHCIN** | Shifter shift-in = current C (rotate-through-carry). |
| 29 | **SETC** | Force C = 1 (SEC). |
| 30 | **CLRC** | Force C = 0 (CLC). |
| 31 | **BSEL** | ALU B-input mux select (rev C): 0 = B register, 1 = T register. |

**FCOND conditions:** `LT` = `N^V` (signed A<B), `LE` = `(N^V)|Z` (signed A≤B).

---

## Backplane bus signals

(Full pin map: `hardware/backplane/p8x-bus-definition.md`.)

| Signal | Meaning |
|--------|---------|
| **D0–D7** | 8-bit data bus (one driver per microcycle). |
| **A0–A15** | 16-bit address bus (always driven by the register-bank card's selected pointer). |
| **DOE0–3 / DLD0–3** | The encoded DOE/DLD fields, broadcast on the bus; each card decodes its own codes. |
| **PSEL0–2, PINC, PDEC, ALUS0–3, ALUM, CIN, SH0/1, LDF, LDZN, SHCIN, SETC, CLRC, BSEL** | Control signals (see the control-word table) routed control-card → consuming cards. |
| **FC, FZ, FN, FV** | The four flag lines, ALU card → control card (read by the condition mux). |
| **CLK, CLKB** | System clock and its complement (CLKB = "CLK-bar"; write strobes gate on it). |
| **-RES / RES̄** | System reset, active low. |
| **IRQ** | Maskable interrupt request (rev C, B29; controller is DNP). |
| **SPARE11** | Last uncommitted bus line (B30). |

> Naming: a leading `-` (or overbar) means active-low (e.g. `-RES`, `-RD`, `!OE`).

---

## Memory map & BIOS ABI

| Term | Meaning |
|------|---------|
| **EEPROM** | `$0000–$7FFF` — monitor at `$0000`, ROM BASIC at `$2000` (combined ROM). |
| **SRAM / RAM** | `$8000–$FEFF`. |
| **SBUF** | 512-byte sector buffer at `$9E00` (fixed by the BIOS — `CFWRITE` reads from it). |
| **LBA** | Logical Block Address — the CF sector number; the BIOS reads the target LBA byte from a fixed `$9D47`. |
| **RBUF** | The OS's `>`-redirect capture buffer (= the TPA, `$B000`). |
| **CONIN / CONOUT / CONST** | BIOS console in / out / status (`$0100/$0103/$0106`). |
| **CFINIT / CFREAD / CFWRITE** | BIOS CompactFlash init / read-sector / write-sector (`$0109/$010C/$010F`). |
| **PUTS / PHEX8** | BIOS print-string / print-byte-as-hex (`$0112/$0115`). |

---

## Filesystem (P8XFS) & OS

| Term | Meaning |
|------|---------|
| **P8XFS** | The P8X File System on CompactFlash. v1 = flat directory; v2 = hierarchical (directories-are-files, `.`/`..`, paths). |
| **boot block** | LBA 0 — signature, version byte, OS sector count, free pointer. |
| **extent** | A file/directory's contiguous run of data sectors. |
| **PACK** | Compaction — reclaim the gaps left by deleted files by sliding extents down. |
| **fsck** | Filesystem consistency check (host tool `p8xfs.py fsck`). |
| **F_FILE / F_DIR** | Directory-entry flag bytes: regular file ($01) / subdirectory ($02). ($FF = deleted.) |
| **OS / monitor / BASIC** | P8X/OS (disk shell), the ROM monitor (`$0000`), and the integer BASIC interpreter. |

---

## Components & chips

| Part | Role |
|------|------|
| **74181** | 4-bit ALU slice (×2 for 8-bit), with **74182** carry-look-ahead. |
| **74HCT00/02/08/32/86** | NAND / NOR / AND / OR / XOR quad gates (generic 14-pin). |
| **74HCT10/30** | Triple-3-input NAND / 8-input NAND. |
| **74HCT138/139** | 3-to-8 / dual 2-to-4 decoders (field decode, port/load select). |
| **74HCT151** | 8:1 mux (condition mux). |
| **74HCT157 / 257** | Quad 2:1 mux (157) / with tri-state (257) — shifters, B-mux, readback. |
| **74HCT161** | Binary counter (clock divider, baud, step counter). |
| **74HCT169** | Up/down counter — the pointer-bank building block (16 of them). |
| **74HCT175 / 7474** | Quad / dual D flip-flop (flag register; C-flag FF; sync). |
| **74HCT244 / 245** | Octal buffer / bus transceiver. |
| **74HCT260** | Dual 5-input NOR (bus zero-detect for Z). |
| **74HCT374 / 377** | Octal D register (pipeline latches; output port; A/B/T/T2). |
| **6850 (ACIA)** | Asynchronous Communications Interface Adapter — the serial UART (console, 9600 8N1). |
| **MAX232** | RS-232 line driver/receiver (logic ↔ ±12 V). |
| **28C256 / 28C64** | Parallel EEPROM — program ROM ($8000-class) / microcode ROMs. |
| **62256** | 32K×8 SRAM. |
| **DS1302** | Serial real-time clock (rev C, DNP). |
| **DIN 41612** | The 96-pin backplane connector standard. **FABC96R** = the card-edge connector part; the backplane has the mating receptacles. |
| **CF / IDE** | CompactFlash storage in 8-bit True IDE mode (`$FF10–$FF17`). |

---

## Generator footprint & device codes (`generators/gen_eagle.py`)

| Code | Meaning |
|------|---------|
| **DEV** | Device table — logical pin names + pin→pad map + package, per part type. |
| **PKG** | Package table — pad geometry (name, x, y, drill, dia) per footprint. |
| **DIP8/14/16/20/24W/28W** | Dual In-line Package, N pins. `W` = wide (0.6″ row spacing). |
| **SIP9/16** | Single In-line Package (resistor networks). |
| **DIN96 / DIN96C** | DIN 41612 96-pin: backplane receptacle / card edge connector (the `C` variant carries the FABC96R mounting holes). |
| **HDR3/4/40** | 0.1″ pin headers, N pins. |
| **TB4** | 4-position terminal block. |
| **LED5 / LEDARR8** | 3 mm LED footprint / 8-segment LED bar array (DIP). |
| **OSC4** | Full-can oscillator (4-pin DIP-style). |
| **SW2P / SW2** | 2-pin switch footprint / device (RESET/RUN/STEP). |
| **RNISO8** | Isolated 8-resistor network (SIP). |
| **R_AXIAL** | Axial-lead resistor. |
| **C_DISC / CP_RADIAL** | Disc ceramic cap / radial polarised (electrolytic) cap. |
| **MEM28K8** | The wide memory footprint shared by the 28C256 EEPROM and 62256 SRAM. |
| **GATES14 / HEX14** | Generic 14-pin quad-gate (74HCT00/08/32/86) / hex inverter (74HCT14). |
| **MHn** | Mounting Hole — non-plated mechanical hole (e.g. on `DIN96C`). |
| **CDn** | The per-IC 100 nF decoupling **C**ap, one beside each chip (`CD1`, `CD2`, …). |
| **Un / Jn / Xn** | Reference designators: IC / connector / crystal-or-oscillator. |
| **busnet() / mnet() / card() / fp_box()** | Generator helpers: bus-pin→net map / memory-card net add / build-a-card / footprint bounding box. |

## Hardware register / protocol bits

| Bit | Meaning |
|-----|---------|
| **RDRF** | ACIA Receive Data Register Full — a byte arrived (read `$FF04` status). |
| **TDRE** | ACIA Transmit Data Register Empty — OK to send the next byte. |
| **RW / RS / CS / E** | ACIA Read/Write, Register Select, Chip Select, Enable control lines. |
| **BSY** | CF/IDE Busy — drive is processing; poll before access. |
| **DRQ** | CF/IDE Data Request — drive ready to transfer a data word. |
| **DRDY / DASP / PDIAG / IORDY** | CF/IDE drive-ready / drive-active-slave-present / passed-diagnostic / I/O-ready. |
| **PC / SP / MAR** | Program Counter / Stack Pointer / Memory Address Register — the classic roles, all subsumed by the P0–P3 pointer bank here (no separate MAR). |
| **UART** | Universal Asynchronous Receiver/Transmitter — the serial-port role the 6850 ACIA fills. |

## BASIC internals (`basic/p8xbasic.asm`)

| Term | Meaning |
|------|---------|
| **BASORG / BASRAM** | Build parameters: code origin / data (variables + program text) base. |
| **PBUF** | Rebuild scratch buffer (fixed at `$C000`). |
| **VARTAB** | Variable symbol table. |
| **NAMLEN / NVARS** | Tunable limits: significant chars per name (6) / max variables (32). |
| **CRUNCH / MATCHKW** | Tokenizer: crush a line to tokens / match a keyword. |
| **EVAL / TERM / FACTOR** | Recursive-descent expression parser levels. |
| **TOK_xxx** | Keyword token bytes (e.g. `TOK_FOR`, `TOK_BYE`). |
| **LCG** | Linear Congruential Generator — the `RND()` pseudo-random algorithm. |

## Code identifiers & internal abbreviations (OS / monitor)

| Term | Meaning |
|------|---------|
| **CWD / CWDPATH** | Current Working Directory / its textual path (for the prompt). |
| **REDIRF** | Redirect Flag — 1 while OS output is being captured to a file. |
| **OUTCH / OPUTS / OPHEX8** | The OS output sink and its string / hex-byte helpers (route through it for redirection). |
| **SDIR / DLBA / ECNT / ENTP** | Directory op state: scanned-dir start/count / dir-sector LBA / entries-left / entry pointer. |
| **FREELO/FREEHI / SECCNT** | Boot-block free pointer (next free LBA) / sector count for a transfer. |
| **RESOLVE / DESCEND / FINDENT / FINDSLOT / WRENT / MKEXT / SAVECORE** | OS directory routines: split a path → parent+leaf / walk into a subdir / find an entry by name / find a free slot / write an entry / init a new dir extent / copy memory→file. |
| **GETHEX / GETLN / PARSEW / CONIN/CONOUT** | parse a hex arg / read a line / parse the command word / BIOS console I/O. |

## Toolchain

| Tool | Role |
|------|------|
| **genucode.py** | Microcode generator — single source of truth for the control word + opcode table; emits the four `u*.bin` EPROM images (burned *and* interpreted). |
| **p8xasm.py** | Two-pass assembler (imports the opcode table from `genucode.py`). |
| **p8xemu.c** | Cycle-level emulator — interprets the same `u*.bin` the hardware burns. |
| **p8xfs.py** | Host tool for P8XFS images (create/boot/put/get/ls/mkdir/tree/fsck). |
| **gen_eagle.py** | Board (schematic + layout) generator for all 7 cards. |
| **gen_bom.py / render_board_pdf.py / gen_bus_pdf.py** | BOM, placement-view PDFs, bus-map PDF. |
