# Stage 4 step 5 — the integration, written down before it is attempted

Every component exists and is independently proven. What remains is one
coordinated edit across four files with **no green state in between**, which is
why it is written out rather than started at the end of a session.

| component | cost | proven by |
|---|---|---|
| `sdram.v` word-write mode | — | on hardware, `WD=0000` |
| `sdram_arb.v` | 7 LUT4 | `tb_sdram_arb.v` |
| `gfx_mem.v` | 152 LUT4 | `tb_gfx_mem.v` |
| `gfx_span.v` | 96 LUT4 | `tb_gfx_span.v`, exhaustive |
| `sdram_model.v` (sim) | — | drop-in at `sdram.v`'s interface |

## The edit, file by file

### `fpga/rtl/gfx.v`

1. **Ports.** Drop `sc_en`, `sc_addr`, `sc_data` — the scanout no longer reads
   through this module. **Keep `sc_pen`/`sc_rgb`**: the palette still lives here
   and the scanout still looks up through it. Add the arbiter port
   (`e_req`, `e_we`, `e_word`, `e_addr`, `e_din`, `e_ack`, `e_ready`, `e_dout`).
2. **Delete** `reg [7:0] fb[0:FBBYTES-1]`, `fb_a`, `fb_we`, `fb_q`, `sc_en_d`,
   the `e_addr`/`e_we`/`e_wdata`/`e_rdata` regs, and the always block that
   drives them. That is the 42 references counted at the outset.
3. **Delete the pixel unit's four-phase FSM** and instantiate `gfx_mem` in its
   place. The algorithms' interface is unchanged — `px_go`, `px_busy`, `px_x`,
   `px_y`, `px_pen`, `px_read` — which is the entire point of building it that
   way. Two knock-ons: `px_pen` widens from `[1:0]` to `[7:0]`, and `px_go`
   needs a `px_go <= 0;` default at the top of the main always block, because
   the FSM being deleted is what used to clear it.
4. **Geometry becomes mode-dependent.** `GW`/`GH`/`GSTRIDE` and `px_on`,
   `px_row`, `px_byte`, `px_sh` all move into `gfx_mem`, which already has them.
5. **Add the mode register** and command `$0C` SETMODE (mode in `GPARM`),
   refusing anything but 0/1 via the ERR bit — matching the emulator, which is
   the golden model here.
6. **`S_CLS`** currently walks `clsi` over `FBBYTES` writing `cls_val` directly.
   Re-express as one `gfx_span` per row, which also makes it use the word path.
7. **Fills** — `S_FILL`, `S_CIRCF`, and the ellipse fill — currently plot pixel
   by pixel. Point them at `gfx_span` for their runs. This is where the 4x comes
   from; correctness does not depend on it, so it can land second.

### `fpga/rtl/p8x_soc.v`
Instantiate `sdram_model` + `sdram_arb`, wire `gfx`'s new port to the arbiter's
engine side, and give the arbiter a refresh timer. The scanout side of the SoC
has no panel, so `s_req` ties low — but **exercise it anyway**, as the current
SoC already does with `sc_lfsr`: contention that is never simulated is
contention that is never tested.

### `fpga/tang-nano-20k/rtl/p8x_top.v`
Same, with the real `sdram.v`, plus `sdram_video` replacing `video_rgb` and
taking the arbiter's scanout port.

### `fpga/sim/tb_gfx.v`
It dumps the PPM by reading `dut.gfx.fb[]` directly. That array is gone, so it
must read `sdram_model`'s `mem[]` instead, and honour the mode when deciding
geometry and depth. **This is the acceptance test, so it has to be right**: the
whole branch is judged by `gfx.sh` showing RTL and emulator identical.

## Order, and where it can go wrong

Do 1–5 first and prove mode 0 still matches the emulator pixel-for-pixel via
`gfx.sh` — that is a pure substitution and should change no pixels at all. Only
then do 6–7 (spans) and re-run, then add mode-1 payloads.

The first full build is also the first time the whole thing is placed together.
Budget: ~255 LUT4 of new logic plus the controller's ~600, against 7,448 free —
but block RAM goes the other way, 4 framebuffer blocks returned against 1 for
the line buffer. On a design that failed to place from a logically-null change,
expect to find out the hard way, and check `p8x_cpu.fs`'s mtime before
believing any result.
