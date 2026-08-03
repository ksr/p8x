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
- Scratch block **$6000–$69FF** (firmware/BIOS scratch $6000-$60xx, **SBUF $6100**,
  OS shell scratch $6300, IBUF/PATHBUF/RUNPATH/APBUF $6500-$69FF) — moved -$1000 from
  rev D's $7000-$79FF. **TPA (programs) = $6A00** (was $7A00); stack down from $FEFF.
- **TPA is ~37.9K ($6A00–$FE00)**, +4K vs rev D. OS reserve $2000–$5FFF (16K = disk
  LBA 1..32 cap). Program `--base`/`--load`/`--exec`, cc/asm `.org`, RBUF, DEFADDR
  all = $6A00. (commit 37dd09f)

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
