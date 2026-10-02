---
name: reference_yacc1_ucode_send
description: How the YACC1 sequencer EEPROM is loaded from the Mac (tools/ucode_send.py), the FTDI port, and the two protocol traps (DTR reset, 64-byte buffer after the prompt)
metadata:
  type: reference
---

Sequencer card (ATmega328, Sequencer4 firmware) on FTDI `/dev/cu.usbserial-AB6WZCQX`, 115200. `tools/ucode_send.py`
(YACC1-D, 2026-09-22) replaces the Processing sender: differential against `firmware/microcode/ucode-generator2/cache`,
`--all`, `--dry-run`, `--boot-check` (captures the run-mode boot, compares the 5 dumped instructions with test.hex).
Procedure: UCODESWITCH=DOWNLOAD, run the tool FIRST (opening the port resets the ATmega via DTR), then press START;
afterwards switch to run, and `--boot-check` (its port open resets the card; READY ~54 s). Traps: after `>>` the card
flashes a LED 100 ms before reading into a 64-byte buffer, so the tool waits 250 ms after each prompt (at 1 ms/char
without it the card hung after record $00). Full load ~6 min at 1 ms/char. Ken prefers `--all` (ignore the cache).
Test: `tests/sequencer/run.py` (mock card on a pty). See [[reference_yacc1_ucemu]], [[project_yacc1]].
