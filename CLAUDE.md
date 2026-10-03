# P8X — 8-bit TTL homebrew CPU

Hand-built 8-bit CPU, ~130 chips of 74HCT logic, microcoded, on an 8-slot
DIN41612 backplane. Six CPU cards: control/microcode, register bank, ALU,
memory, I/O, CF-IDE; plus a PS/2 keyboard card and a bus test card. All nine
boards (with the backplane) are designed and routed in KiCad, none fabricated
yet; the same microarchitecture also runs as an FPGA build (fpga/).

## Architecture quick reference
- 8-bit data, 16-bit address. Address bus is ALWAYS driven by one of four
  16-bit pointer registers (74169 counters): P0=PC, P1/P2=general, P3=SP
  (empty-descending; push = write-then-decrement).
- Registers A, B (ALU operands), hidden temps T/T2, FLAGS (C,Z,N,V).
- Bus discipline: 4-bit encoded DOE (data output enable) and DLD (data
  load) fields, decoded per card. DOE: 0 idle, 1 A, 2 B, 3 T, 4 T2,
  5 ALU, 6 FLAGS, 7 MEM, 8 PTRL, 9 PTRH. DLD: 1-5 A/B/T/T2/FLAGS-restore,
  6 IR, 7 MEMW, 8/9 PTRL/PTRH.
- Memory map (rev E; single source `generators/gen_memmap.py`): $0000-$17FF ROM
  (6K — shrunk from 8K on 2026-09-14; monitor+BIOS use ~5.2K), $1800-$FEFF RAM
  (2x 62256), $FF00-$FFFF I/O (switches $FF00, LEDs $FF02, ACIA $FF04/05,
  CF-IDE $FF10-17). The $1800-$1FFF low island freed by the ROM shrink holds
  relocated OS/BIOS scratch (IBUF/PATHBUF/APBUF, SBUF $1D00, BIOS scratch $1F00).
  The OS still loads at $2000; its syscall jump table moved to $20xx. Transient
  programs load at TPABASE $5900 (~39.8K TPA up to $F7FF; the C stack grows down
  from $F7FF, fixed system buffers sit above $F800). P8XFS is v2-only (hierarchical).
- Microcode: ROM address = IR | step<<8 | cond<<12. Step 0 of every opcode
  is the fetch cycle. The FCOND field of the executing word selects the
  flag driving A12 for the NEXT lookup (pipeline timing).

## Hard rules
1. **Generators are canon.** Never hand-edit the KiCad boards
   (hardware/<board>/kicad/), their netlists or the ROM binaries — they are
   build artifacts of generators/ (gen_eagle.py still produces the netlists;
   generators/build.sh turns them into KiCad boards) and
   firmware/microcode/genucode.py. Edit the generator, regenerate. The Eagle
   files of the first generation are frozen in each board's eagle-deprecated/.
2. **The emulator interprets the same ROM images burned to the EPROMs**
   (firmware/microcode/u0-u3.bin). Never give the emulator private opcode
   knowledge; all instruction semantics live in the microcode.
3. **The assembler (when built) must share genucode.py's opcode table** —
   one source of truth for mnemonics/encodings.
4. Active-low signals use a leading dash: -RES, -RD, -MEMW.
5. **C flag quirk (deliberate, matches hardware):** the flag register
   latches the RAW 74181 Cn+4 pin, which is active-LOW carry
   (C=1 means NO carry out). Do not "fix" this in the emulator; it is a
   VERIFY item in BACKLOG.md (invert in rev B vs adopt as convention).
6. V flag is hardwired 0 in rev A (matches the ALU card).
7. Check BACKLOG.md before and after working; keep it current
   (NEXT / IDEAS / VERIFY / WONT-DO sections — live work only). Completed items
   move OUT to BACKLOG-DONE.md; don't let finished work pile up in BACKLOG.md.
   Read WONT-DO / SUPERSEDED before starting anything that looks obviously
   missing — several entries there are decisions NOT to do something, and one of
   them (signed compares in p8cc) shipped a buffer overflow when acted on.

8. **`emulator/test/` and `fpga/tang-nano-20k/sim/` are .gitignore ALLOW-LISTS**
   — everything is ignored, the hand-written sources are named. The tests write
   scratch files (images, .bin/.asm twins, traces) next to their sources, and a
   deny-list could not keep up: it reached ~200 lines and still leaked, letting
   generated .asm twins get tracked and go stale, which silently made the
   os_cmdbuild byte-compare check an out-of-date build.
   So: **adding a new hand-written test source needs a `!` line in .gitignore**
   (or a name matching the existing convention — `*.sh`, `test*.asm`). If `git
   add` appears to do nothing, that is why. Never "fix" it by deleting the
   `emulator/test/*` line; add the exception.

9. **Documentation voice: the docs are Ken Rother's own project documentation.**
   Write every doc, man page, comment and docstring in the plain documentation
   voice — the subject is the machine, the card, the tool or the document.
   - A decision is a dated fact ("chosen 2026-09-24", "X was dropped
     (2026-09-12)"), never "Ken's pick" or "the user decided".
   - A procedure is in the imperative ("Flash the Tang Nano with ...").
   - First person ("I", meaning Ken) only where a person truly has to be in the
     sentence, such as a first-hand bench observation; keep it rare.
   - Never narrate requests or collaborators: no "Ken asked / wants / said /
     prefers", "Ken's pick", "at Ken's request", "per Ken", "confirmed by Ken",
     "the user" meaning Ken, and no "Claude", "the agent", "the assistant" or
     "this session". "Ken's Macs" is "either Mac". History keeps its fact in
     neutral words. ("The user" meaning a program's user — a key the user
     presses — is fine.)
   - Claude's involvement is stated once, by Ken, in README.md's "Who made it"
     line; do not add credit claims elsewhere.
   - A voice edit changes voice only: keep every fact, number, date, hash, path
     and link.
   Exempt: this CLAUDE.md, commit messages, `docs/memory/` (a deliberate mirror
   of Claude's memory notes), any `deprecated/`, `parked/` or `eagle-deprecated/`
   tree, `logs/`, third-party files, and generated files (fix prose in a
   generated file by editing its generator — rule 1).

## Build & test
- `cd emulator && make`         — build the emulator
- `make ucode`                  — regenerate u0-u3.bin (UC var = microcode dir)
- `make test`                   — assemble the smoke test and run it
  (expects "P8X lives! same ucode as the EPROMs" then HALT)
- After ANY microcode change: regenerate images and re-run both tests
  (message print; JSR/RTS round trip in emulator/test/).

FPGA (needs `iverilog`; the board flow needs oss-cad-suite):
- `fpga/sim/run.sh 20000`                        — co-sim vs the emulator
- `fpga/sim/run.sh 60000 isa_test.asm`           — the original 88 opcodes (143 today)
- `fpga/sim/run.sh 200000 "" console_in.txt`     — driven monitor + console diff
- `fpga/sim/console.sh "" os/run-disk.img`       — interactive console on the RTL
- `fpga/tang-nano-20k/build.sh cpu load`         — build + program the board
- After ANY change to fpga/rtl/ or the microcode: re-run all three co-sims. The
  emulator is the golden model; a divergence names the exact microcycle.

## Layout
- hardware/<board>/ — everything for one board in one place: kicad/ (the
  generated board, Gerbers, renders; see rule 1), eagle-deprecated/ (frozen),
  README + theory/design docs. One dir per board: backplane, control-card,
  regbank-card, alu-card, memory-card, io-card, cf-card, ps2-card, bustest-card.
  Status of every board: hardware/KICAD-BOARDS.md; build readiness:
  hardware/RECONCILIATION.md. Build/check one: `sh generators/build.sh <card>`,
  `sh generators/check_card.sh <card>` (KiCad 10 + a Freerouting jar)
- docs/         — cross-cutting docs only: p8x-system-design.md,
  p8x-card-standards.md, p8x-programmers-guide.pdf
- generators/   — Python generators for CAD + schematic PDF renderers (run from hardware/)
- website/      — the project website: MkDocs + Material over these docs (website/README.md;
  `website/build.sh [serve|publish]`); published at https://p8x.cottageworker.com
  by .github/workflows/website.yml on every push to main (strict build)
- microcode/    — genucode.py + u0-u3.bin images + gen_progguide.py
- assembler/    — p8xasm.py (two-pass assembler)
- firmware/     — p8xmon.asm (ROM monitor source)
- basic/        — p8xbasic.asm (BASIC interpreter; skeleton REPL so far)
- emulator/     — p8xemu.c, Makefile, test/
- fpga/         — the standalone FPGA P8X (parallel track to the TTL build, not a
  replacement). fpga/rtl/ is the board-independent core (p8x_cpu.v, p8x_soc.v);
  fpga/sim/ is the co-simulation harness that diffs the RTL against the emulator
  cycle-for-cycle; fpga/tang-nano-20k/ is the Sipeed Tang Nano 20K board build
  (p8xasm.py and gen_progguide.py locate genucode.py automatically; the
   emulator Makefile's UC variable points at the microcode directory)

## Near-term roadmap (see BACKLOG.md)
(The original three items — assembler sharing the opcode table, CF-IDE emulation,
the decoupling-cap generator pass — are all long done; see BACKLOG-DONE.md.)
1. TTL build: the register bank rev D (PT2 for MOVW, a counting PT for
   PHW/PLW/LPW — the routed rev B cannot run today's microcode), then footprint
   confirmation and ordering (the backplane first); the KiCad DRC is already clean.
2. FPGA build: first the RAM write window — the RTL writes RAM only from $2000,
   but since the 6K ROM (2026-09-14) RAM starts at $1800 and the monitor/OS keep
   scratch in $1800-$1FFF; move both boundaries to RAMBASE and bring the co-sim
   file list up to date (BACKLOG NEXT). Then Milestone 5 — clock up (currently 9 MHz against a ~50 MHz Fmax,
   three fabric phases per microcycle) and wire IRQ through.
3. OS: multi-stage pipes (`a | b | c`); a `path` command.
