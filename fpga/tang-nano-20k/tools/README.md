# Installing a disk on the board without root

Writing a raw image to a microSD from the host needs root (`dd` to `/dev/rdiskN`),
which is not always available. It is not needed: the board's own `CFWRITE` works,
so P8X can install its own disk over the serial console.

| file | what |
|------|------|
| `term.py` | serial terminal that fixes P8X's bare-LF output (see below) |
| `osload.asm` | writes N (<256) sectors to LBA 1.. and patches OSCNT — installs just the OS onto an already-formatted card |
| `imgload.asm` | writes an arbitrary run of sectors from LBA 0 — clones a whole P8XFS image |

Both are RAM-resident blobs assembled at `$3000`:

```bash
python3 assembler/p8xasm.py fpga/tang-nano-20k/tools/imgload.asm -o /tmp/imgload.bin --base 0x3000
```

Then, over the console: poke the bytes in with the monitor's `E 3000` command
(stream hex digit pairs — two digits set a byte and auto-advance), `G 3000`, and
send the payload.

## Two pacing rules, both learned the hard way

- **Poking through `E` must be echo-paced.** The ACIA shim holds exactly one
  received byte, and the monitor blocks for ~87 us echoing each character, so a
  full-rate burst loses bytes. Send a character, wait for its echo.
- **Streaming sector data does not need pacing, but the acks do.** The loader's
  receive loop is ~4 us per byte against 87 us on the wire, so a whole 512-byte
  sector can go at full speed. `CFWRITE` then takes milliseconds, during which
  anything sent is lost — so the host must wait for the `.` ack before starting
  the next sector. The loader emits `.` per sector and `K` at the end.

## Protocols

`osload`: 1 byte N, then N*512 bytes → LBA 1..N, then OSCNT is patched into the
boot block. Use on a card already formatted by the monitor's `F`.

`imgload`: 2 bytes N little-endian, then N*512 bytes → LBA 0.. . Nothing is
patched; the image carries its own boot block. 12377 sectors (the 6 MB
`os/run-disk.img`) takes about 10 minutes at 115200.

## term.py — a small serial terminal

```sh
./term.py                       # auto-picks the console port, 115200
./term.py /dev/cu.usbserial-XXX 115200
```

`Ctrl-]` quits. Dependency-free (termios only — no pyserial, no install).

**A stock terminal now works too.** This tool was written when P8X emitted a bare
LF for a newline, which staircased on anything that did not translate. `CONOUT`
does that expansion itself since 2026-08-13 (see
[`docs/p8x-monitor.md`](../../../docs/p8x-monitor.md)), so `screen` renders the
OS correctly and `term.py` is now a convenience rather than a fix:

- it finds the console port for you (the bridge exposes two, and the other one is
  JTAG),
- `Ctrl-]` beats `Ctrl-A k`,
- its LF → CRLF mapping is harmless and idempotent — it leaves an existing CR LF
  alone — so it still behaves correctly against the older firmware, or against
  anything run with `TTYRAW` set.

## imgsend.py — driving imgload from the host

```sh
./imgsend.py ../../../os/run-disk.img          # port auto-detected
```

Assembles the loader, pokes it in, runs it, streams the image, and waits for the
per-sector acks. **Destructive** — it overwrites the card from LBA 0.

Two things it does that the by-hand recipe above does not, both learned by
getting them wrong:

- **It runs the monitor's `I` first.** Without `CFINIT`, every `CFWRITE` fails.
  `imgload` used to ack unconditionally, so all 3254 sectors were reported
  written, the run finished with `K`, and the card was untouched — success and
  total failure were indistinguishable. `imgload` now answers `E` and stops on a
  write error, and `imgsend` treats that as fatal.
- **It verifies the poked loader** with `D 3000` before running it. A loader with
  one wrong byte does not fail cleanly; it runs off into RAM, and the first
  symptom is the board echoing your image back at you.

### It is not reliable to the end of a large image

On a 3254-sector image it has stalled twice at sectors 2777 and 2790 — close
enough together to be systematic rather than random loss. The stream runs at
~9.2 KB/s against the 11.5 KB/s the line can carry, so there is very little
headroom, and a single dropped byte leaves the board waiting mid-sector with no
way to resync (the protocol has no framing or checksum).

**For a full image, write the card from the host instead** — pull the microSD,
put it in a reader, and `dd` the image to it. `imgsend` is dependable for the
small transfers it was meant for, and it is still the only option with no card
reader and no root, but it needs framing and a per-sector retry before it can be
trusted with megabytes.
