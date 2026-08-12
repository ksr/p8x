# Installing a disk on the board without root

Writing a raw image to a microSD from the host needs root (`dd` to `/dev/rdiskN`),
which is not always available. It is not needed: the board's own `CFWRITE` works,
so P8X can install its own disk over the serial console.

| file | what |
|------|------|
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
