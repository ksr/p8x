# emulator/

`p8xemu.c` — a cycle-accurate P8X emulator. It does not hard-code instruction
behavior; it loads the microcode images `u0–u3.bin` and steps the same control
word the real hardware does, so it is a faithful model of the machine, not an
approximation.

## Build & run

```sh
make            # builds p8xemu and regenerates the microcode (u0-u3.bin)
./p8xemu [-t] [-l N] [-c disk.img] [-s NN] [-L] rom.bin
```

- `rom.bin` — the EEPROM image (origin `$0000`), e.g. the monitor or combined
  ROM BASIC. The emulator expects `u0–u3.bin` in the current directory.
- `-c disk.img` — attach a CompactFlash image; models the 8-bit True IDE task
  file at `$FF10–$FF17`.
- `-s NN` — value the I/O card switches present at `$FF00` (hex or decimal, e.g.
  `-s 0xA5`); defaults to 0. So `PEEK(65280)` / monitor reads see it.
- `-L` — trace LED writes: each change to `$FF02` prints to stderr as
  `[LED $FF02] $NN  *.*..*.*` (`*` = lit). The final LED byte is always shown in
  the halt status line.
- `-t` — instruction trace. `-l N` — halt after N cycles.
- The 6850 ACIA is wired to stdin/stdout, so the monitor/OS/BASIC are interactive.

On halt it prints `PC/A/B/...` register state (`A=00` is the convention for "test
passed" in the self-checking suites).

## Tests

```sh
make test        # everything below
make test-isa    # per-instruction self-check (halts A=00 on success)
make test-cf     # monitor format/boot against the CF model
make test-os     # P8X/OS boot + shell on flat and v2 volumes
make test-basic  # ROM BASIC (X) and disk BASIC (B)
make test-io     # switch input (-s) -> $FF00 and LED writes ($FF02, -L)
```

Test scripts and fixtures live in [`test/`](test/); their build artifacts
(`*.bin`, `*.img`, `*.hex`, …) are gitignored.

## Other targets

`make rom` builds the persistent burnable image set into [`../rom/`](../rom/).
