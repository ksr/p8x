---
name: reference_p8x_memory_map
description: "P8X memory map — 6K ROM $0000-$17FF (reclaim 2026-09-14), OS at $2000, TPABASE $5900, syscall ABI $20xx"
metadata: 
  node_type: memory
  type: reference
  originSessionId: df90e3f3-8668-416d-bc7b-83f2952ba723
---

P8X **rev E** memory map (2026-07-13, commit 6cadf38):

- **ROM $0000–$17FF (6K)** — monitor + BIOS (~5.2K used). BIOS jump table at $0100.
  Shrunk from 8K to 6K on 2026-09-14 (ROMSIZE/RAMBASE $2000→$1800) to reclaim
  **$1800–$1FFF as a RAM island**; the emulator reads only ROMSIZE bytes of the
  (still 8K) assembled image, so the monitor (ends ~$143F) is untouched.
- **RAM $1800–$FEFF** — 2× 62256. **OS loads at $2000** (OSORG unchanged); the
  $1800–$1FFF island below it holds relocated scratch (see below).
- **I/O $FF00–$FFFF**.
- **TPA base dropped $6A00 → $6300 → $6100 → $5900** over 2026-09-13/14, freeing
  4,352 B total. The first three moves relocated the OS scratch band and `SBUF`
  down toward the OS code. The last move (2026-09-14, +2,048 B) followed the ROM
  shrink: the top half of the scratch band — `IBUF`, `PATHBUF`, `APBUF`, `SBUF`,
  and the **firmware/BIOS scratch** — moved into the new $1800–$1FFF island,
  which let TPABASE drop to $5900.
- **Final low layout:** RAM island **$1800–$1FFF** (IBUF $1800, PATHBUF $1A00,
  APBUF $1B00, **SBUF $1D00–$1EFF**, **BIOS scratch $1F00–$1FFF**), OS code
  $2000–~$5585, OS scratch (stay band) **$5700–$58FF** (LINEBUF, CWDPATH $5800,
  the FS/shell/PACK/FSCK/make vars), **TPA = $5900**; stack down from $FEFF.
  **The BIOS scratch moved** ($6000–$60FF → $1F00–$1FFF): FNAME/LBA/DIRLBA/FLEN
  and the graphics flags (GFXPRES/GTSUSP/GCONEN) + ROSTATE/ROSDRV are hardcoded
  in ~28 command/app/fixture sources, all shifted −$4100 in lockstep. `SBUF`
  (not in the //#define ABI) only touched raw-CFWRITE fixtures.
- **TPA is ~39.8 KB ($5900–$F7FF** = 40,704 B; a program's image + its P3 stack
  which grows down from $F7FF, below the system buffers at $F800+**)**. Program `--base`/`--load`/`--exec`, cc/asm
  `.org` (p8cc.py via memmap.TPABASE; p8xcc.asm/cc.c/asm commands hardcoded, all
  shifted), RBUF, MKFLATB, DEFADDR (`#<TPABASE`/`#>TPABASE`), and the monitor's
  dir-buffer default (`#>SBUF`) all track the base. Programs at an old base still
  run (in-TPA). See [[reference_p8x_tpabase]] for the full change checklist.

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
