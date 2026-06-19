# docs/

System-wide documentation. (Per-card guides live with their board under
[`../hardware/<card>/`](../hardware/); language and tool guides live next to
their source in `../basic/`, `../os/`, etc.)

| Document | Description |
|----------|-------------|
| [p8x-system-design.md](p8x-system-design.md) | System and card-by-card architecture reference; §3.2 has the as-built control-word layout. |
| [p8x-card-standards.md](p8x-card-standards.md) | Design rules every plug-in card must follow (form factor, connector, decoupling, etc.). |
| [p8x-monitor.md](p8x-monitor.md) | ROM monitor command reference and memory map. |
| [p8x-programmers-guide.pdf](p8x-programmers-guide.pdf) | Generated instruction-set reference (built by `../microcode/gen_progguide.py`). |

The PDF is a generated artifact — regenerate it rather than editing:

```sh
python3 ../microcode/gen_progguide.py      # writes the guide PDF here
```

New to the abbreviations and signal names used throughout these docs? See the
root [GLOSSARY.md](../GLOSSARY.md).
