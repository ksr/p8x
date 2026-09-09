---
name: project_p8x_debuiltin
description: "De-built-in'ing shell commands to /bin to free OS budget; del+help DONE (~1.5KB); mkdir reverted (bootstrap); no clean candidates remain"
metadata: 
  node_type: memory
  type: project
  originSessionId: 6ffcfef7-73ca-445b-bcdb-f57735fdc98f
  modified: 2026-09-09T12:28:40.180Z
---

Moving self-contained shell built-in commands OUT of the resident OS image into
`/bin` programs, to free OS code budget. Driven by the WM work: the OS hit the
`$6000` ceiling (see [[project_p8x_resident_wm]]) and de-built-in'ing is the
cleanest reclaim. Prior art: DIR, PWD, CAT, TREE were already moved.

**DONE 2026-09-09 (all three have C + verified asm twin -> /bin default):**
- **del** → del.c + del.asm (freed ~78 B). FDELETE BIOS call; abspath the arg
  (CWD-relative — FRESOLVE starts at root, see [[reference_p8x_relpath_gotcha]]);
  `while(*a==32)a++` between args like touch (multi-arg). c_del_test.
- **help** → help.c + help.asm (freed ~1.4 KB — the big one; user's idea). Was
  ~1.4 KB of static MHELP text + a one-line print, all resident for no reason.
  C puts() the reference; asm = a string-ptr table + print loop. c_help_test.
- **mkdir** → ATTEMPTED then REVERTED. It's a filesystem BOOTSTRAP primitive
  (you need it to create /bin on a freshly-formatted card, and `format` WIPES
  /bin so a format-then-mkdir sanity check can't use a /bin binary), and it is
  woven through ~10 tests' setup (os_bigdir/dualvol/basic/sh/format/bigpack +
  the format-verify pattern). Moving it broke all those for a ~76 B gain — not
  worth it. Stays a shell built-in like cd. LESSON: a command that BOOTSTRAPS
  the FS or is used to set up /bin cannot itself live in /bin.
- **ASM TWINS:** del/mkdir cloned touch.asm's arg-loop+inlined-abspath skeleton
  (swap the per-name action); help.asm = htab word-table + print loop. Verified
  byte-identical via os/commands-asm/verify.sh (added DEL/MKDIR/HELP cmd_script
  cases). Moved from run.sh's C-only /bin loop to the asm-twin loop (asm->/bin,
  C->/binc). commands-asm/README scoreboard: del 5.2x, mkdir 4.8x, help 1.5x; now
  "All 21 ported". **OS went 1 B free -> ~1.7 KB free (ends ~$59B4).**

**Pattern per move:** write os/commands/<name>.c (//#use apath+abi as needed);
remove from p8xos.asm — the DISPATCH block (LDP1 #KW_x/CMPCMD/JNZ DO_x), the DO_x
impl, any message string, the KW_x keyword, AND the KWTAB entry (tab-complete);
add <name> to run.sh's compile loop + the C-only /bin loop (line ~247, ~259) —
C-first, asm twin follows per "asm is the /bin default"; update man/<name> +
os/commands/README (table row + the "no longer built-ins" note) + os/README +
man/README; add a c_<name>_test; run os_complete (KWTAB changed) + test-c + gfx.

**NO clean candidates remain** (assessed 2026-09-09): rmdir/pack/fsck reach deep
FS internals (FINDENT/DIREMPTY/PK2MOVE/raw CFREAD dir-walking) with NO syscall
surface — moving them would ADD OS code, not save it; save/dep/dump operate on
memory a /bin program at $6A00 would overwrite (dump already stays native for
this); mkdir is bootstrap (above). **MUST STAY builtin:** cd (shell CWD),
run/load (loader), sh/make (script engine), path (PATH state), exit/mon,
mount/umount (mount state), bootload (low-level), mkdir (bootstrap),
rmdir/pack/fsck/format (deep FS), save/dep (memory).
GOTCHAS: (1) `?`/`H` in the ROM MONITOR is separate from OS `help` — leave those
docs. (2) de-built-in'ing a command breaks EVERY test that ran it as a shell
command (they need the /bin binary on their disk) — grep test .sh for it first;
`del` needed fixes in fdelete_hilba/os_bigfile/os_bigpack, `help` in os_append.
