---
name: reference_p8x_fs_wrappers
description: "BIOS/OS addresses are named via //#define (both compilers) + equates, not raw hex"
metadata: 
  node_type: memory
  type: reference
  originSessionId: df90e3f3-8668-416d-bc7b-83f2952ba723
---

BIOS/OS entry-point addresses are no longer hand-copied as hex into command source.
As of the 2026-07-14 "clear out hardcoded addresses" work, both C compilers support
**object-like `//#define`** (the `//#` prefix matches the existing `//#use`):

- **C side** (`os/commands/`): a command does `//#use abi` (splices the #define
  header `os/commands/lib_abi.c`, e.g. `#define FOPEN 0x0124`, `#define RDBUF 0xFC00`)
  and writes `bios(FOPEN, RDBUF, 0)`. #define is textual substitution, so bios()'s
  literal-address requirement is met and the compiled binary is **byte-identical to
  the old raw-hex version — ZERO code cost** (this is why we chose #define over
  wrapper functions, which added ~250-540 B/command).
- **ASM side** (`os/commands-asm/`): one `lib_abi.inc` of equates (`FOPEN = $0124`),
  every twin `;#use abi`, `JSR FOPEN`. Equates emit zero bytes → twins byte-identical.

Compiler support added:
- `compiler/p8cc.py` lexer: `#define NAME value` (int, dec/0xhex) + identifier→number substitution.
- `apps/p8xcc.asm` (on-target `cc`): `//#define` parsed in the lexer's `//#` dispatch
  (TRYDEF), macro table = packed names MACNAMES + parallel MACVALS[]; MACLOOKUP runs
  on every identifier in `adv_id`. Reuses `adv_num` to parse the value.

Gotchas (same class either way — centralizing addresses means the shared file must
reach the build disk):
- A command with `//#use` must be built THROUGH `tools/clib.py` (host) — a test that
  feeds it RAW to p8cc breaks (fixed c_dir_test's pwd build).
- On-target build fixtures need `/lib/lib_abi.c` (for `cc`) and `/lib/abi.inc` (for
  `asm`) on the disk (fixed os_mk_test, os_asm_use_test). run.sh installs `/lib` by
  glob, so full-disk builds are automatic.

See [[reference_p8x_hand_asm]], [[feedback_p8x_new_command_dual]].
