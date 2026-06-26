# assembler/

`p8xasm.py` — the P8X two-pass assembler.

It shares its opcode table with the microcode generator: mnemonics and encodings
come straight from `genucode.OPC`, so the assembler and the hardware can never
disagree about what an opcode means. (Edit the instruction set in
[`../microcode/genucode.py`](../microcode/genucode.py), not here.)

## Usage

```sh
python3 p8xasm.py src.asm [-o out.bin] [-l listing.txt] [--base ADDR] [-D NAME=VAL ...]
```

- **No `--base`** → a full 32 KB ROM image (origin `$0000`), ready for the
  memory-card EEPROM. This is how the monitor (program ROM) is built.
- **`--base A`** → a RAM-resident blob: labels resolve to run address `A`, and
  only the `A..high` bytes are emitted. This is how P8X/OS and disk BASIC are
  assembled to load somewhere other than `$0000`.
- **`-D NAME=VAL`** → define an assembly-time symbol (used to parameterize BASIC
  via `BASORG`/`BASRAM`, for example).
- **`-l`** → write a listing file (address + bytes + source per line).

## Notes

- Two passes: pass 1 builds the symbol table, pass 2 emits bytes.
- `;` starts a comment **even inside a quoted string** — avoid `;` in `.ascii`
  strings.

See [GLOSSARY.md](../GLOSSARY.md) for mnemonics and the [programmer's guide](../docs/p8x-programmers-guide.pdf)
for the full instruction set.
