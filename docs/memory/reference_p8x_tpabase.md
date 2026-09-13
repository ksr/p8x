---
name: reference_p8x_tpabase
description: Every place that must change when TPABASE (the TPA base / default program load address) moves — it is NOT truly single-sourced; ~all of it is hardcoded. Checklist from the 2026-09-13 $6A00->$6300 flag-day.
metadata: 
  node_type: memory
  type: reference
  originSessionId: 6ffcfef7-73ca-445b-bcdb-f57735fdc98f
  modified: 2026-09-13T18:27:57.269Z
---

TPABASE is the base of the transient program area = the default load/exec/`.org`
of RUNnable programs. **It is NOT single-sourced despite `gen_memmap.py`'s
intent** — only `compiler/p8cc.py` derives it (`memmap.TPABASE`); everything
else hardcodes the literal. Changing it is a flag-day. On 2026-09-13 it dropped
`$6A00`->`$6300` (freeing 1,792 B of TPA; commit 6d795c0). The full checklist:

**The map (single source for the few that read it):**
- `generators/gen_memmap.py` `TPABASE` value, then re-run it (writes
  memmap.inc/.h/.py). `RBUF` (built-in output-capture buffer) and any
  TPA-base-scratch symbol must track it (RBUF and MKFLATB alias the TPA base).
- `compiler/p8cc.py` follows automatically (`TPA_BASE = memmap.TPABASE`). DO NOT
  hardcode it there.

**Hardcoded emitters/load-bases (must be edited by hand):**
- `os/p8xos.asm`: `DEFADDR` — the default load/exec for a file whose stored
  load/exec is 0 (what the native assembler's FCREATE writes). Use
  `#<TPABASE`/`#>TPABASE` (it once hardcoded `#$6A` — a bare PAGE byte, which a
  `$6A00` grep MISSES; grep `#\$6[0-9A-F]` too). `MKFLATB` (make scratch) = the
  TPA base. `RBUF` comes from the map.
- `apps/p8xcc.asm`: TWO spots — its own `.org` (~line 259) AND the `.org` it
  EMITS for compiled programs (the `MORG` template, `.ascii ".org $XXXX"`, ~line
  3335). Both hardcoded.
- `apps/cc.c`: the `.org` string it emits (`emit("\t.org $XXXX\n...`)).
- `compiler/p8cc.c`: the `.org` it emits (host C twin; NOT auto like p8cc.py).
- `apps/p8xasm.asm`, `apps/p8xedit.asm`: their own `.org`.
- Every `os/commands-asm/*.asm` (~30 files): each has its own `.org` (the /bin
  twin's load base).
- `basic/p8xbasic.asm`: uses the `BASORG` symbol (not hardcoded); `BASORG` is
  passed by `-D` in run.sh and the tests, which must match.

**Build + test scripts (hardcode `--base`/`--load`/`--exec`/`-D BASORG`):**
- `os/run.sh` (~20 sites): every /bin binary's `--base`/`--load`/`--exec`, and
  `-D BASORG`.
- `emulator/test/*.sh` (~109 files): `--base`/`--load`/`--exec`. Also the SIZE
  LIMIT assertions that are (symbol_table_addr - TPABASE): os_asm_test (SYMTAB
  $8000), asm_c_test ($A800), cc_c_test ($B800) — lowering TPABASE RAISES these.
- Uniform shell replace is safe: every `$6A00`/`0x6A00` in these files was a TPA
  base (no data-address uses; verified). But grep the bare page byte `#$6A`
  separately.

**Rebuild + docs:**
- `rm os/run-disk.img` then `P8X_BUILD_ONLY=1 ./os/run.sh` — run.sh reuses an
  existing disk, so a stale run-disk.img keeps the OLD OS. `basic_cwd_test`
  COPIES run-disk.img, so a $6300 BASIC on an old $6A00-scratch OS collides =
  false failure. [[reference_p8x_runsh_disk_reuse]]
- Docs: `reference_p8x_memory_map`, `reference_p8x_cwdpath` (CWDPATH is in the
  relocated band), the p8xos.asm header comment, the six live README build
  examples. Dated design docs / GLOSSARY / BACKLOG-DONE are historical, exempt.

**What does NOT change:** programs built at the OLD base still run (they load
in-TPA); the emulator/p8xfs have no default base; `p8cc.py`.

Related: [[reference_p8x_memory_map]] (layout after the drop: OS scratch
$5900-$5FFF, SBUF $6100 the remaining floor — the monitor rewrite can reclaim it
for ~768 B more), [[project_p8x_isa_everywhere]].
