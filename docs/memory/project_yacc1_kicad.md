---
name: project-yacc1-kicad
description: "YACC1 Eagle-to-KiCad conversion (ALL boards done 2026-09-20 via tools/eagle_to_kicad_all.py, proofs, converter gotchas) and the YACC1-D repo state/pipeline"
metadata: 
  node_type: memory
  type: project
  originSessionId: 05007751-a1c3-49f6-8fff-5b14d1ceec67
  modified: 2026-09-19T21:45:12.859Z
---

**Pilot conversion DONE 2026-09-19:** `~/Documents/YACCS/kicad/memory-card-v1.3/` = KiCad 10 project
(memory-card-v1.3.kicad_pro/.kicad_sch + 6 sub-sheets/.kicad_pcb, project libs `memory-card-v1.3-eagle.kicad_sym`
+ `.pretty`, `eagle-source/` = byte-identical copies of the Eagle .sch/.brd/notes, `reports/` = ERC/DRC/
netlist/PDF/renders, `tools/`). The Eagle originals in the YACCS tree were never touched.
- `tools/eagle_sch_to_kicad.py` (mine): Eagle 9 XML .sch -> KiCad hierarchical schematic. KiCad has NO
  headless schematic importer (kicad-cli only imports boards); the GUI importer exists but can't be
  scripted. Gotchas learned: Eagle gate x/y offsets are placement hints (ignore them); rotations map 1:1;
  power gates (all pins 'pwr') -> hidden unit-0 power_in pins when unplaced, visible unit when placed;
  hidden pins are `(hide yes)` not bare `hide`; refs must end in a digit (Eagle "PWR" -> "PWR0", matching
  kicad-cli's board importer); labels go on FREE wire ends; add a PWR_FLAG per supply net or ERC flags
  power_pin_not_driven (KiCad's own importer leaves the same 2 errors).
- `tools/compare_netlists.py`: PROOF = KiCad netlist vs the pad netlist embedded in the imported board,
  as partitions of (ref,pad). Memory card: 115/115 identical, MATCH.
- `tools/finish_board.py` (KiCad bundled python + pcbnew): extract footprints to .pretty, move the
  connector's stray Edge.Cuts line, OSH Park 4-layer rules (6 mil/10 mil/4 mil annular, 5 mil clr),
  link footprints to symbol UUIDs, refill zones. kicad-cli imports the .brd fine (4-layer, planes on In1/In2).
- Residual ERC (cosmetic, explained): 43 isolated_pin_label, IC5/IC14 hidden-power-pin notes, unused gates.
  DRC: 100 "unconnected" = IC26-29/RN5/RN6/C9 (the 16-bit temp registers) are UNPLACED in Eagle v1.3
  too (airwires), plus silk-over-pad warnings.

**ALL BOARDS CONVERTED 2026-09-20 (commit e5f421b):** `tools/eagle_to_kicad_all.py` (runs under KiCad's python; `make kicad`)
converts every Eagle design under hardware/ into `<item>/kicad/<rev>/` (deprecated/<rev>/ mirrored), each with sch+pcb+libs,
.kicad_pro from tools/kicad/project-template.kicad_pro, reports/ (netlist proof, ERC, DRC, PDF, renders) and a README;
index hardware/KICAD.md. The flat memory pilot folder is GONE (regenerated as kicad/v1.3, still 115/115). Output is
regenerated from scratch each run - once Ken edits a card in KiCad it must leave the generator's list. Proof: 34/35 pairs
MATCH; the ONLY mismatch is the VIDEO card and it is genuine (board feeds IC1/14, IC2/20 from +5V; schematic's implicit VCC),
noted in its README + BACKLOG. Converter gotchas learned from the proofs (all fixed in tools/kicad/eagle_sch_to_kicad.py):
Eagle MRnn = KiCad (mirror y) same angle; two nets' wires may share an endpoint on a bus (pull the later net back 0.635 mm);
hidden power pins must sit OFF-GRID (a +5V label on IC15's hidden VCC pin merged the supplies); KiCad's board importer
prefixes digit-leading refs with UNK and turns '/' in package names into '_'; Eagle implicitly connects unwired 'pwr' pins
of placed gates and supply-on-pin (wire-less) segments -> emit global labels; 'request' gates with a stray non-pwr pin are
still power gates; Eagle 'nc' pins get wired (2764 VPP) -> passive; a supply symbol takes the Eagle NET name when they
differ. ERC noise that remains: isolated_pin_label (my per-net labels), silk DRC from the Eagle drawings.
**NEWER-THAN-ACTIVE DESIGNS (tools/compare_eagle.py, 2026-09-20, report hardware/NEWER-DESIGNS-vs-ACTIVE.txt):** ALU V3.3 = V3.2
(only bus label renamed); Registers 1.2 = 1.1 byte-identical renamed; vertical jumper V3.1 = V3.0; IO/backplane/address-tmp
working-edits = electrically identical (IO: 4 nets renamed ADDR-REG-ID0..3 -> -ADDR-REG-LD/RD); bus-tester V3.11 = V3.1 netlist,
unfinished re-route. REAL new designs: ALU V3.3-16 (16-bit, +58 parts, 32 device swaps, 0 vias = unrouted) and bus-tester V3.1
(+28 parts: latches IC11-IC15 replace MCP23017 direct drive, -BUF-EN/-SOFT-BUS-EN/-SOFT-RESET, bypass caps, no reset switch).
**CLEANUP PATTERN (Ken approved 2026-09-20, done for vertical + horizontal jumpers):** a 'version' that only changes silk text
or is byte-identical gets folded into the active folder (keep just its .brd beside the active one, drop its identical .sch
and empty Notes), via RULES edit -> dryrun -> purge -> run -> gen_fabricated -> gen_provenance -> pdf -> audit; card README
says what was folded. Index Registers 1.2 folded 2026-09-20 (only its Notes were new). ALU V3.3 folded 2026-09-20 (nothing new). ALL -16 WORK (ALU V3.3-16 x3 snapshots, Assembler-16, emulator-16,
opcodes-16.h) DELETED from YACC1-D on Ken's instruction 2026-09-20 ('useless') via skip rules; originals remain in YACCS only. Jumpers, registers, ALU, bus tester, IO, memory, sequencers, mem-switch, mem-register, video (brd renamed Video_1.0.brd), backplane (v1.1 Eagle-9 re-save dropped), blank card, address-tmp (working copy = +1 "test text", dropped), protocard all cleaned 2026-09-20; Blank V3.2 derived; fab/ zips are the record (extracted copies dropped by a hash-verified rule) (seq: old-YACC1 gen-1 dupes dropped, orig-size intermediates kept; test.ctl autorouter file consolidated to hardware/libraries/eagle) (memory v1.3 folder = V1.3 only now; generators prune orphan PDFs) (IO draft folded: only its Notes with the V1.2 ideas kept): bus-tester = v1.1 (built, 2018 board) + v3.1
(July-2020 redesign, never ordered; V3.11 = reshape, folded in as v3.1/v3.11-horizontal-unrouted/). Remaining folders are real designs. pdf/SKIP.txt in a folder lists design files that get no PDF.
RULE MODES: skip = unwanted (bytes never resurface from backups); drop = duplicate of content kept elsewhere (path not
copied, other holders untouched) - use drop for 'identical to archive' cases or the archive copy vanishes too. File rules
(no trailing /) match exactly; first match wins so file rules precede folder rules.
hardware/PROVENANCE.md (tools/gen_provenance.py) = source folder + oldest-identical-copy date per design file.
**DOCS TREE CLEANED 2026-09-20:** docs/system/connector/ = the 4 bus-spec PDF versions (V3.2 canonical) + per-card table;
20 scattered copies dropped from card folders. 2021 repo README/status/PCB readme -> docs/history. Datasheets kept (19 MB).
Ken 2026-09-20: bus jumper boards NOT FITTED (obsolete, older bus); EEPROM adaptor fitted; TWO register cards
(R0-R3, R4-R7); video RN2 = 1k left in; mem-switch + mem-register bring-up cards REMOVED from the bus; IC7-pin-4 wire purpose unknown; ATmega firmware unsure -> reflash from tree.
docs/system/MACHINE.md = machine state (with (confirm) marks: jumpers fitted, register-card count, RN2, ATmega firmware);
BACKLOG.md at root = all unbuilt/open work. ALL TREES WALKED (hardware, software, firmware, embedded, tests, docs). NEXT: git init (no LFS) + first commit + GitHub.
**TESTS TREE CLEANED 2026-09-20:** bus-tester-scripts = 2020 '.new' ALU scripts + IO/Index/Memory tests + Gen Test Vectors;
2016 gen-1 scripts (old signal names) + the 'fix' sed converter under deprecated/gen1-2016; address-register test deprecated;
tests/basic/test = BASIC program; tests/assembler = yacc1test.asm + history-2020.
**MAKEFILES 2026-09-20:** every C tool has a plain Makefile (NetBeans one kept as Makefile.netbeans); root `make` builds all
six, `make check` = audit + verify_firmware + verify_embedded + assembler/ucodegen checks. All six binaries work from a Finder
double-click (inputs/outputs resolved relative to the executable via _NSGetExecutablePath). Edited sources are listed in
tools/patched_files.txt (emulator, disasm2, ucodegen, ubasic, asm). purge never deletes hand-written files at stale paths.
**EMBEDDED VERIFIED 2026-09-20:** tools/verify_embedded.py = arduino-cli (bundled in Arduino IDE 2 at /Applications/Arduino IDE.app/...)
compiles all 12 sketches for Uno against ONLY embedded/libraries (private user-libs dir); WIP MCP23X17 port = expected fail.
extEEPROM 3.4.1 vendored for deprecated sequencer2. rtf notes have .md twins (tools/rtf_to_md.py).
**EMBEDDED TREE CLEANED 2026-09-20:** current = bus-tester sketches, command_sender_8, sequencer3 (+ IO.ino 2024 pull-ups off),
simple_microcode_sender_64 (115200, reads test.hexz/cache), dumpram, test-eeprom, clocker; older generations under
embedded/*/deprecated/. Sketches use Adafruit_MCP23017 1.x API + YACC_Common_header.h (vendored in embedded/libraries).
**FIRMWARE VERIFIED 2026-09-20:** tools/verify_firmware.py rebuilds monitor.img, basic.img, rom (== burned EEPROM) and
microcode test.hex from the migrated sources - ALL byte-identical. asm gotcha: `asm monitor -d=yacc1` (source BEFORE -d, the
-d handler does i++). microcode: test.hexz = loader input (== test.hex), cache = last image sent to the card.
**SOFTWARE TREE CLEANED 2026-09-20:** software/assembler = tool only (+upstream/rcasm-2.2, yacc1.def = 2025 'equ' version);
firmware pieces moved to firmware/*/candidates + firmware/rom/builds; tests/assembler = yacc1test.asm + history-2020/;
disasm v1 archived; ubasic 2024 kept (= 2020 + 6-line fixes), 2023 int-index experiment in archive/conflict-losers.
SOURCES ARE NEVER EDITED (purge reverts edits!) - old relative includes satisfied by tools/layout_links.py symlinks
(firmware/opcodes.h, software/disassembler/yaccsignaldefine.h, .../ucode-Generator2). Verified: asm, emulator, ubasic,
ucode-generator2 compile with clang; ucode-generator2 REPRODUCES test.hex byte-identical. disasm2 FIXED 2026-09-20 (tools/patched_files.txt lists edited migrated sources; audit/purge/run honour it)
-include yaccsignaldata2.h (its include is commented out as committed).
**SCHEMATIC PDFs (2026-09-20):** `tools/sch_to_pdf.py` = every Eagle .sch under hardware/ -> my converter -> kicad-cli pdf ->
`<rev>/pdf/<name>-schematic.pdf` + hardware/SCHEMATICS.md (56/56 OK). Fusion has no scriptable export; Eagle 9.6.2 `-C PRINT`
hangs on its login dialog. Converter fixes that day: `_LibGroup` (Eagle 9 managed libs appear twice under one name - search
all copies), sheet comment no longer hard-coded to Memory V1.3. Page 1 of each PDF = KiCad sheet index.
**YACC1-D STRAWMAN CREATED 2026-09-19** at `~/Documents/YACCS/YACC1-D/`: README.md (tree + conventions +
open decisions), MIGRATION.md (source->destination map, authoritative copy per item), and the empty
skeleton with a placeholder README per dir. NO files migrated, no git. Key facts behind it: 2,753 of
7,566 files under YACCS are iCloud-EVICTED (must "Download Now" before migrating; git inside iCloud
Drive is risky -> recommend ~/Developer); "Software-vs" = July-2021 git state (burned build),
"Software pre vs" = Sept-2021, "Software" = working copy with 2023-26 edits; the 4 old backups
YACC1-BACKUP/A/A1/B = gen-1 YACC1 (2015-18: Logisim, python asm, gen-1 boards, tinyBasic);
Required Applications (593 MB, evicted) = Parallels, JDK8/NetBeans 8.2, JDK 22; yacc1.pptx = 142 MB.
DECIDED 2026-09-19: real tree goes to `~/Developer/YACC1-D` (beside P8X), NO LFS ever. iCloud
download COMPLETE 2026-09-19 (7,566 files, 0 evicted; YACC1-2026 deleted). Full-hash result: backups
hold 1,041 "interesting" files absent from the current copies (gen-1 material: YACC1A/A1 ~130 each
truly unique, YACC1-BACKUP 25, ORIG 20, YACC1B 13); YACC1-master 28. TREE CREATED 2026-09-19 at `~/Developer/YACC1-D` (62 dirs + README/MIGRATION; busdrv.py,
alias_min.py, inventory.py in tools/; captured EPROM in firmware/rom/). NO git yet, NOTHING migrated
from YACCS yet. Next step when asked: dry-run migration script from MIGRATION.md. YACCS/YACC1-D =
retired strawman.
**DRY RUN + DEDUP 2026-09-19 (tools/migrate_dryrun.py, reports in migration/):** source tree is NEVER modified;
dedup happens in the copy plan: archive-mode files whose md5 already goes elsewhere are dropped and logged in
dedup-dropped.tsv (priority: copy > rule archive > YACC1A1 > YACC1A > YACC1B > YACC1-BACKUP > master > snapshots);
Eagle .sch/.brd pairs are never split; copy-mode never dropped (copy-duplicates.txt lists 99 identical
contents at 2+ copy destinations, mostly Production-vs-Working folders of the same rev); files > 50 MB
-> manifest (no LFS). Result: copy 629 / archive 1,212 (213 MB, was 4,487 / 1.4 GB) / manifest 7 / 0
unclassified / 0 dest conflicts / 28 same-path conflicts (user decisions pending). PRODUCTION = PCB/Production
folder (identical in all 4 current copies) = what was FABRICATED: memory v1.2, ALU V3.2, Index Registers 1.1,
Bus Tester V3.1, IO 1.1, Seq-Logic 2.1, Seq-Memory 2.1, BUS 2.0, jumpers H3.2/V3.0, Mem Switch 1.1, Mem Register
1.0, Protocard 1.0. MEMORY v1.3 IS FABRICATED AND IN THE MACHINE (Ken 2026-09-19; ordered 2025-06, never moved to
Production; the FABRICATED table in migrate_dryrun.py is the truth). Working holds NEWER unfabricated designs ( ALU
V3.3/-16, Registers 1.2, Bus Tester V3.11 board-only change) and IO V1.1: the PRODUCTION folder is the built card (Ken 2026-09-19); the Working copy is post-fab edits, never ordered.
**MIGRATION EXECUTED 2026-09-19** (`tools/migrate_run.py`): ~/Developer/YACC1-D holds 1,994 files / 328 MB: 631 copy +
1,228 archive rows all md5-verified, plus the KiCad pilot (hardware/cards/memory/kicad + tools/kicad), Arduino libs
(embedded/libraries/YACC + Adafruit_MCP23017 1.1.0), LM1881 conv Eagle project; 7 large files manifest-only
(migration/large-files-manifest.tsv); 24 conflict losers under archive/conflict-losers/<copy>/. YACCS untouched.
LAYOUT (Ken 2026-09-20): hardware/cards/<card>/eagle/<rev>/ = ACTIVE version + newer unbuilt designs; eagle/deprecated/<rev>/ = every
lower version; <rev>/fab/ = gerbers/CAM/invoices, <rev>/bom/. ACTIVE table in migrate_dryrun.py: memory 1.3, mem-switch 1.1,
mem-register 1.0, bus-tester 1.1 (= the 2016 TESTER-PROD-V1.1 board, Eagle folder 'Bus Tester orig'; V3.1/V3.11 never built),
video 1.0, alu 3.2, io 1.1, register 1.1, seq-memory 2.1, seq-logic 2.1, backplane 2.0; assumed: protocard 1.0, blank 3.1,
template 3.2, jumpers H3.2/V3.0, address-tmp retired. EEPROM adaptor = ACCESSORY of sequencer-memory (plugs into IC9 for a
bigger EEPROM) -> hardware/cards/sequencer-memory/accessories/eeprom-adaptor/ (Ken 2026-09-20), not a card of its own. Every 2020 board's Fusion CAMOutputs (gerbers/drill/assembly) exist and now sit in <rev>/fab/CAMOutputs/ (index
2026-09-20, 10,550 files; the 09-19 index skipped CAMOutputs - see [[feedback-verify-index-coverage]]). REBUILT FROM SCRATCH 2026-09-20 from index 09-20 (11,400 files incl. nbproject/): tree = 3,044 files / ~400 MB;
migration/yaccs-find-2026-09-20.txt = raw find of YACCS (25,476) fully reconciled; tools/audit_tree.py must pass (every file
explained) after any re-run; firmware/rom/eprom-captured-2026-09-18.* are session captures NOT from YACCS (audit knows).
FABRICATED markers; archive/superseded-revisions = never-built only; truth table = tools/fabricated.py -> gen_fabricated.py ->
hardware/FABRICATED.md (in-machine confirmed by Ken: memory v1.3, io V1.1 (Production copy), video V1.0; the rest 'presumed'
from PCB/Production). Production/'Old & obsolete' boards (2020-08/2021-01 snapshots) = fabricated-then-superseded, recovered.
FAB OUTPUT (routed by the FAB regex in migrate_dryrun.py into <rev>/fab/):
only memory v1.3 (Memory V1_2025-06-27.zip, Fusion CAM 4-layer), blank-card v3.1, backplane v1.1, alu v3.0-2layer,
bus-tester orig, protocard, eeprom-adaptor invoice have any; the rest were ordered as .brd uploads (OSH Park). BOM csv -> cards/<card>/bom/<rev>/.
GIT INITIALISED 2026-09-20: ~/Developer/YACC1-D on branch main, first commit = the whole sorted tree (2,59x files, pack ~104 MB),
.gitattributes `* -text` (byte-exact, no LFS), .gitignore for Eagle autosaves/build products. A fresh clone passes
audit_tree.py and verify_firmware.py. GitHub: https://github.com/ksr/YACC1-D (public, remote origin, pushed 2026-09-20); ksr/YACC1-2020 ARCHIVED read-only. Commit style: conventional commits.
**User's plan (2026-09-19):** originally `~/Documents/YACCS/YACC1-D` ("definitive"), now ~/Developer
+ matching GitHub repo = single source of truth: migrate current boards, software, tools, scripts, test
plans; write docs (theory of operation per card + system); migrate Eagle files then convert all to KiCad
and deprecate Eagle (kept in git). See [[project-yacc1]] for which copy of each thing is newest.
Also wanted in YACC1-D: (a) VIRTUAL MACHINES for software that only runs on old/unsupported OSes -
too big for plain GitHub (100 MB file cap); advised manifest+checksums with images stored outside git,
or LFS only if git-lfs is installed everywhere (the 2020/2024 repos broke on exactly that); (b) ARDUINO
code for the bus tester and the control/sequencer card, vendoring the legacy MCP23017 1.1.0 lib and the
YACC_Common_header.h signal table next to the sketches + arduino-cli compile check; (c) ROM IMAGES for
the memory card (rom = Software-vs build ff7d85a is what is burned) and the SEQUENCER MICROCODE
(uCode-Generator2 sources + hex + downloader), each with a rebuild-and-diff script.
