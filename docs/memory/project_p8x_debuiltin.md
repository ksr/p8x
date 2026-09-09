---
name: project_p8x_debuiltin
description: "De-built-in'ing shell commands to /bin to free OS budget; del+help done, mkdir/rmdir/pack/save/fsck remain"
metadata: 
  node_type: memory
  type: project
  originSessionId: 6ffcfef7-73ca-445b-bcdb-f57735fdc98f
  modified: 2026-09-09T08:10:47.781Z
---

Moving self-contained shell built-in commands OUT of the resident OS image into
`/bin` programs, to free OS code budget. Driven by the WM work: the OS hit the
`$6000` ceiling (see [[project_p8x_resident_wm]]) and de-built-in'ing is the
cleanest reclaim. Prior art: DIR, PWD, CAT, TREE were already moved.

**DONE 2026-09-09:**
- **del** → os/commands/del.c (freed ~78 B). FDELETE BIOS call; abspath the arg
  (CWD-relative — FRESOLVE starts at root, see [[reference_p8x_relpath_gotcha]]);
  `while(*a==32)a++` between args like touch.c (multi-arg). c_del_test.
- **help** → os/commands/help.c (freed ~1.4 KB — the big one; user's idea). Was
  ~1.4 KB of static MHELP text + a one-line print, all resident for no reason.
  Just puts() the reference. c_help_test. **OS went 1 B free -> ~1.5 KB free.**

**Pattern per move:** write os/commands/<name>.c (//#use apath+abi as needed);
remove from p8xos.asm — the DISPATCH block (LDP1 #KW_x/CMPCMD/JNZ DO_x), the DO_x
impl, any message string, the KW_x keyword, AND the KWTAB entry (tab-complete);
add <name> to run.sh's compile loop + the C-only /bin loop (line ~247, ~259) —
C-first, asm twin follows per "asm is the /bin default"; update man/<name> +
os/commands/README (table row + the "no longer built-ins" note) + os/README +
man/README; add a c_<name>_test; run os_complete (KWTAB changed) + test-c + gfx.

**REMAINING candidates (self-contained FS ops, no shell state):** mkdir (nearly
free — SYS_MKDIR $2021 already exists, /bin/mkdir is a ~5-line wrapper), rmdir,
pack, save, fsck. format is movable but low-level/risky. **MUST STAY builtin:**
cd (shell CWD), run/load (loader), sh/make (script engine), path (PATH state),
exit/mon, mount/umount (mount state), bootload (low-level boot writing).
GOTCHA: `?`/`H` in the ROM MONITOR is separate from OS `help` — leave those docs.
