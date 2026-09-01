# The Card Edge — the FPGA as a pure P8X graphics card

The decision (2026-08-28, with the user): the FPGA CPU proved the P8X
design could live in silicon, and that proof is banked (tag
`stage10-complete` rebuilds the all-in-one machine forever). The FPGA's
FUTURE is the add-on GRAPHICS CARD for the machine that will live in
hardware. This arc cuts the design at the bus:

    ideas, in order of appearance:
    1) the Mac EMULATOR is the CPU, driving the real card over a
       serial bus bridge            <- THIS ARC
    2) a second FPGA runs the P8X CPU, same card, inter-board link
    3) the real TTL machine, same card, 5V bus on a DIN 41612 slot

All three drive the SAME card through the SAME contract. Ideas 1 and 2
are rehearsals of 3 — each retires risk on the interface before the
TTL bus exists. This document is the contract.

## 1. The card edge (the contract)

The card IS its register window — the same one software already knows:

    $FF20-$FF2F   the 2D device     (registers, GCMD, GMODE, GID0/GID1)
    $FF50-$FF57   the GL port       (GLDATA/GLSTAT/GLRB/GLERR/GLID)

Semantics are EXACTLY today's (gen_memmap stays the authority; the
graphics theory doc stays true). No graphics software changes: BASIC,
lib_gfx, the GL clients and every test speak this window unchanged.

New, bridge-era additions to the window (unused addresses):

    BRIDGEV $FF55  read: protocol version, $01     (version byte FIRST:
    BRIDGID $FF56  read: 'B'                        three masters will
                                                    speak this edge; we
                                                    can only add this
                                                    cheaply NOW)

A master that reads GID0='P', GID1='G', GLID='G' sees a graphics card;
BRIDGID='B' additionally identifies a bridge front-end (absent on the
all-in-one build and, later, on the TTL bus card).

## 2. What leaves the chip, what stays

    LEAVES (the computer):            STAYS (the card):
      p8x_cpu (+ its BSRAM ROMs)        p8x_geom + scratchpad + tables
      cf_sd, sd_spi (storage)           gfx + gfx_mem + gfx_span
      the console role of the UART      mdu_core (the geom datapath's)
                                        sdram stack + scanout + panel
                                        the UART, reborn as the bridge

Budget consequence (measured, stage-10f era): the CPU is ~1,184 LUT
sites and CF/SD ~1,310 more — roughly 2,500 freed against a 19,048
build. That is MORE than stages 10e + 10g + 10h were denied for.
Resurrecting 10e is `git revert` of its revert, THEN the room exists.

## 3. Build targets: addition, never subtraction

build.sh grows a fourth target beside the untouched three:

    lcd    the all-in-one computer -- UNCHANGED, still built, still
           placed, still passing its six frames: the regression
           baseline and the fallback personality
    card   p8x_gcard_top.v: bridge front-end + the card modules only

The engine RTL is SHARED between lcd and card in identity — the same
files, no forks. Only the top level differs. The board flips
personality by re-flash; both bitstreams are kept.

## 4. The bridge protocol (serial, v1)

Transport: the board's USB-serial UART, owned entirely by the bridge
in card personality (there is no console — there is no CPU). Baud:
negotiated by configuration, start at 115200, characterize the BL616's
ceiling early (a RISK item: pixel-heavy pushes want every baud we can
get; GL command streams do not care).

Host-driven, binary, byte-oriented. The 6-bit register index addresses
the window: idx = I/O address minus $FF20, so idx $00-$0F is the 2D
device ($FF20-$FF2F) and idx $30-$37 the GL port ($FF50-$FF57) -- one
subtraction, mechanical in both directions.

    $00            PING: card replies 'P' '8' 'X' 'G' then BRIDGEV
    $80|idx  val   WRITE val to register idx          (no reply)
    $40|idx        READ register idx -> card replies one byte
    $01      n  b0..b(n-1)
                   BURST: n (1-64) bytes to GLDATA; card replies $06
                   (ACK) after the LAST byte is ACCEPTED by the FIFO
                   -- the ack is flow control: at most one burst in
                   flight, so the card's FIFO and the UART receiver
                   can never be overrun
    $02            STATUS: card replies GLSTAT (a read alias that
                   spares the mux for the hottest poll)

Everything else reserved; the card ignores unknown commands (and a
future v2 can extend behind BRIDGEV). The host idles the line between
commands; there is no card-initiated traffic except replies.

Reset story: opening the port MUST NOT reset the card (lesson learned:
the current board does not reset on open either — probe, never
assume). PING is the state probe. A protocol-level RESET is
deliberately absent from v1: the GL RESETF verb already covers
graphics state, and a wedged bridge FSM is reflash territory.

## 5. The emulator as CPU

`p8xemu -B <serial-device>`: every CPU access to $FF20-$FF5F forwards
over the bridge; everything else (CPU, RAM, storage, console) stays
emulated locally. Flag-gated: default behavior is byte-identical to
today, so every existing test runs unchanged.

The payoff beyond the demo: pointing the EXISTING frame suites at -B
runs the golden model against REAL SILICON — the co-sim's final form.
POINT/GLERR/GLSTAT reads become serial round-trips; the FIFO contract
already tolerates arbitrary latency, and GCHECK's polls translate to
STATUS commands.

Known slow path: IMAGE-class per-pixel pushes (~200KB of pokes for a
256x256 P8I) are minutes at 115200 — hence the baud characterization
up front, and no pretense that idea 1 is a gaming bus. The language
model (stage 10's whole thesis) is what makes a serial bus sufficient:
scenes are tens of bytes.

## 6. RTL: p8x_gcard_top.v

A small top: clocks/PLL as today, the SDRAM/scanout/panel stack as
today, geom+gfx as today, and in place of the CPU a bridge FSM:

    UART rx -> command decoder -> {reg write strobe, reg read mux,
                                   GLDATA push with FIFO backpressure}
            <- reply mux (PING string, read data, ACK, STATUS)

The bridge FSM is deliberately dumb — no buffering beyond one command,
state machine ~a dozen states. Estimated well under 300 LUTs against
~2,500 freed.

## 7. Proof ladder (the usual discipline)

  1. This document.
  2. Protocol reference implementation host-side (tools/glbridge.py:
     open/ping/read/write/burst) + a pure-python unit test against a
     mock endpoint.
  3. p8x_gcard_top.v + `card` target; tb_gcard.v drives the bridge
     with UART BYTES and replays the existing six-frame scenes through
     it — the same .ppm compares, transport swapped. (The benches
     already isolate scene-from-transport; this is the dividend.)
  4. Placement (trivially: the card is ~6,500 sites in a 20,736 chip).
  5. Board first light: flash `card`, PING over the wire, GLID via
     $40-read, one gl scene streamed by glbridge.py — the panel draws
     with NO CPU ON THE CHIP.
  6. p8xemu -B: the frame suites against silicon; then the fun
     (BASIC on the Mac emulator, panel on the desk).
  7. THEN: 10e resurrection in the roomy build; 10g/10h become
     schedulable again.

## 8. Status (2026-08-28): FIRST LIGHT — the ladder is climbed

Every rung proven, same day: glbridge.py mock-proven; the `card`
target PLACES at 16,808 LUT4 / 81% with BSRAM 5/46 (41 blocks + ~2.2k
LUT freed -- the 10e/10g/10h room); tb_gcard renders the 10a frame
byte-identical THROUGH protocol bytes; p8xemu -B drives a MockCard
from a full BASIC session. Then the board: PING answered P8XG v1 with
the full identity (P/G/G/1/B), a register-driven PLOT read back $F800
exactly, the PG-640A house streamed from the Mac, recorded to a list
and drawn -- a graphics card with NO CPU ON THE CHIP -- and p8xemu -B
ran the LINFUN rubber-band program against real silicon: -2017 / 31 /
-1, the emulator's golden values from the card's actual framebuffer.
The card bitstream ran from SRAM for first light; flashing it (or
keeping lcd in flash) is the user's personality choice.

## 8b. Risks, named

- UART integrity at speed: imgsend's history (transport acks are not
  content checks) — the protocol's per-burst ack helps, a periodic
  CRC op can join v2 if reality demands it.
- The lcd target must never break: it builds in CI-discipline (the
  test ladder) until the day the user retires it on purpose.
- One serial port, two personalities: scripts must PING to learn who
  is listening (a monitor banner means lcd personality; PING replies
  mean card) — never assume.
- Idle means TWO polls: GLSTAT bit6 clears while the 2D engine may
  still be draining its final span to SDRAM (tb_gcard found the frame
  19 pixels short). Hosts poll GLSTAT.busy then GSTAT.busy. (BASIC's
  GCHECK once did the same dance before probing GID0; it is GLID-only
  since the single-interface migration — GLID answers regardless of
  walker state.)
