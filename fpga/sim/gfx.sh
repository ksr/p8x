#!/usr/bin/env bash
# The RTL drawing engine matches the emulator, pixel for pixel.
#
#   ./gfx.sh
#
# Runs the SAME graphics payloads on both models and byte-compares the frames
# they produce. The emulator is the golden model, so this is `cmp`, not "does it
# look right": one wrong pixel in eight thousand fails. A Bresenham that lights a
# prettier but different pixel is a bug, and this is what catches it.
#
# WHY THIS AND NOT run.sh's CYCLE DIFF. The graphics device deliberately CANNOT
# be cycle-diffed. The emulator draws instantaneously and never raises BUSY; the
# RTL takes thousands of clocks and does. A program that polls GSTAT therefore
# reads different values on the two models by design, so their CPU traces
# legitimately diverge. What must agree is the FRAMEBUFFER, and nothing about the
# engine's internal timing is visible to software beyond that BUSY bit.
#
# The payloads call GWAIT before every command for the same reason: the device
# draws in real time and a command issued while another is running ABORTS it.
# The wait is free on the emulator (never busy) and essential on the RTL, so one
# payload is correct on both -- which is what makes this comparison meaningful.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
EMU="$ROOT/emulator"

for f in u0.bin u1.bin u2.bin u3.bin; do
  [ -f "$EMU/$f" ] || { echo "gfx.sh: $EMU/$f missing — run 'cd emulator && make'" >&2; exit 2; }
done
command -v iverilog >/dev/null 2>&1 || { echo "gfx.sh: iverilog not found (brew install icarus-verilog)" >&2; exit 2; }

W="$HERE/work"; mkdir -p "$W"; cd "$W"
for f in u0.bin u1.bin u2.bin u3.bin; do ln -sf "$EMU/$f" .; done
python3 "$HERE/mk_ucode_mem.py" "$EMU" ucode.hex >/dev/null

iverilog -g2012 -o tb_gfx.vvp \
  "$ROOT/fpga/rtl/p8x_cpu.v" "$ROOT/fpga/rtl/p8x_soc.v" "$ROOT/fpga/rtl/gfx.v" \
  "$HERE/tb_gfx.v"

fail=0
for name in gfx gfx2; do
  src="$EMU/test/test_${name#gfx}.asm"
  case "$name" in
    gfx)  src="$EMU/test/test_gfx.asm" ;;
    gfx2) src="$EMU/test/test_gfx2.asm" ;;
  esac
  python3 "$ROOT/assembler/p8xasm.py" "$src" -o "$name.bin" >/dev/null

  # golden frame from the emulator
  ( cd "$EMU" && ./p8xemu -l 200000 -g "$W/$name.golden.ppm" "$W/$name.bin" ) >/dev/null 2>&1

  # the same ROM on the RTL
  python3 - "$name" <<'PY'
import sys
n = sys.argv[1]
b = open(n + ".bin", "rb").read()
open("gfxrom.hex", "w").write("".join("%02x\n" % x for x in b))
PY
  vvp tb_gfx.vvp "+ppm=$name.rtl.ppm" > "$name.log" 2>&1 || true

  if [ ! -f "$name.rtl.ppm" ]; then
    echo "GFX-RTL TEST: FAIL — $name produced no frame"; sed -n '1,5p' "$name.log"; fail=1; continue
  fi
  # A BLANK frame is not a pass. Two models that both draw nothing agree
  # perfectly, and that is exactly what happened when a GWAIT that clobbered A
  # turned every command in the payloads into a NOP: this test stayed green while
  # the payloads drew literally nothing, and only the emulator's own pixel
  # assertions caught it. Identical is necessary, not sufficient.
  lit=$(python3 - "$name.golden.ppm" <<'PY'
import sys
d = open(sys.argv[1], "rb").read()
px = d[d.index(b"255\n")+4:]
print(sum(1 for i in range(0, len(px), 3) if px[i:i+3] != b"\x00\x00\x00"))
PY
)
  if [ "$lit" -lt 100 ]; then
    echo "GFX-RTL TEST: FAIL — $name drew only $lit lit pixels; the payload is not"
    echo "  drawing. Two blank frames compare equal, so this is checked separately."
    fail=1
    continue
  fi

  if cmp -s "$name.golden.ppm" "$name.rtl.ppm"; then
    echo "  $name: frames identical ($lit lit pixels)"
  else
    echo "GFX-RTL TEST: FAIL — $name differs from the golden model"
    python3 - "$name" <<'PY'
import sys
n = sys.argv[1]
g = open(n + ".golden.ppm", "rb").read()
r = open(n + ".rtl.ppm", "rb").read()
if len(g) != len(r):
    print("    sizes differ: golden %d, rtl %d" % (len(g), len(r))); sys.exit()
h  = g.index(b"255\n") + 4
gp, rp = g[h:], r[h:]
bad = [i//3 for i in range(0, len(gp), 3) if gp[i:i+3] != rp[i:i+3]]
print("    %d of %d panel pixels differ" % (len(bad), len(gp)//3))
seen = set()
for p in bad:
    fbx, fby = (p % 480)//2, (p//480)//2
    if (fbx, fby) in seen: continue
    seen.add((fbx, fby))
    print("      fb(%3d,%3d) golden=%s rtl=%s"
          % (fbx, fby, gp[p*3:p*3+3].hex(), rp[p*3:p*3+3].hex()))
    if len(seen) >= 8: break
PY
    fail=1
  fi
done

[ "$fail" = 0 ] && echo "GFX-RTL TEST: PASS (RTL engine matches the emulator pixel for pixel)"
exit $fail
