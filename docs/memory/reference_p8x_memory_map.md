---
name: reference_p8x_memory_map
description: "P8X rev E memory map — 8K ROM, OS at $2000, syscall ABI at $20xx"
metadata: 
  node_type: memory
  type: reference
  originSessionId: df90e3f3-8668-416d-bc7b-83f2952ba723
---

P8X **rev E** memory map (2026-07-13, commit 6cadf38):

- **ROM $0000–$1FFF (8K)** — monitor + BIOS (~4.7K used). BIOS jump table at $0100.
  Assembler emits an 8K ROM image (cap $2000).
- **RAM $2000–$FEFF (56K)** — 2× 62256. **OS loads at $2000** (was $4000 in rev D).
- **I/O $FF00–$FFFF**.
- **TPA base dropped $6A00 → $6300 → $6100 (2026-09-13)** in two steps, freeing
  2,304 B for the self-host fit. Step 1: the OS's own scratch band (LINEBUF, the
  FS/shell/PACK/FSCK variables, IBUF, PATHBUF, APBUF, ~1.75 KB) relocated from
  $6300–$69FF down into free RAM just past the OS code (which ends ~$55E6),
  dropping TPABASE to $6300. Step 2: `SBUF` (the monitor's sector buffer, was
  $6100) moved down below the BIOS scratch to $5E00–$5FFF, dropping TPABASE to
  $6100.
- **Final low layout:** OS code $2000–$55E6, OS scratch **$5700–$5DFF**,
  **SBUF $5E00–$5FFF**, firmware/BIOS scratch **$6000–$60FF**, **TPA = $6100**;
  stack down from $FEFF. **The BIOS scratch $6000–$60FF did NOT move** — FNAME,
  LBA, LBA1, DIRLBA, FLEN etc. are the stable ABI that commands `//#define`
  (lib_abi). `SBUF` is monitor-owned but NOT in that //#define ABI (commands use
  the FWOPEN/FPUTB stream, never raw SBUF), so moving it only touched raw-CFWRITE
  test fixtures (cf2, hilba) — but it IS a documented address, and a real
  monitor rewrite would redesign this region.
- **TPA is ~40.1K ($6100–$FE00)**. Program `--base`/`--load`/`--exec`, cc/asm
  `.org` (p8cc.py via memmap.TPABASE; p8xcc.asm/cc.c/asm commands hardcoded, all
  shifted), RBUF, MKFLATB, DEFADDR (`#<TPABASE`/`#>TPABASE`, was `#$6A`), and the
  monitor's dir-buffer default (`#>SBUF`, was `#$61`) all track the base.
  Programs at an old base still run (in-TPA). See [[reference_p8x_tpabase]] for
  the full change checklist.

**Syscall ABI moved with the OS: $40xx → $20xx.** The OS jump table is at the
front of the OS image, so it now starts at $2000: SYS_GETCWD $2003, SYS_CWDLBA
$2006, SYS_PUTC $2009, SYS_GETC $200C, SYS_PUTS $200F, SYS_OPENCWD $2012,
SYS_SETDRIVE $2015, SYS_GETDRIVE $2018, SYS_DIRENTRY $201B, SYS_OPENDIR $201E,
SYS_MKDIR $2021. C programs call `bios(0x20xx,...)`; asm uses `SYS_* = $20xx`.
Both compilers (host compiler/p8cc.py + p8lib.c, on-target apps/p8xcc.asm) emit
$20xx. BIOS jump table ($0100+) is unchanged (in ROM).

Why: freed $2000–$3FFF (old upper ROM window) for RAM. dir.c now compiles+assembles
on-target (36K DIR.BIN) but a 36K binary is still marginal to RUN in the 37.9K TPA
(fixed runtime buffers $FA00/$FC00 + stack are tight) — see [[reference_p8x_cc_caps]].
Related: [[project_p8x]].
