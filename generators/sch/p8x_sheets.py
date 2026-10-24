#!/usr/bin/env python3
"""Group a P8X card's parts into schematic sheets.

sheets_for(card) -> (sheets, wired)
  sheets = [(title, [[ref, ...row...], ...rows...]), ...]   one tuple per sheet
  wired  = {sheet index (1-based), ...}                      ELK-wired sheets

Default grouping: the active ICs on ELK-wired sheets (chunked so one sheet is not
overcrowded), the backplane/edge connectors on their own sheet, and the passives
(decoupling, resistors, LEDs, R-networks) on a label sheet. A card may override
by adding its name to SHEETS below.
"""
import re

PASSIVE = {"CAP", "CAP1", "CAPP", "RES", "LED", "SIP9", "RNISO8", "RNISO8D", "LEDARR8",
           "XTAL32", "COIN", "SW2", "DIP8SW"}
CONN = {"DIN96C", "DIN96", "DSUB9F", "IDE40", "HDR3", "HDR4", "HDR10", "JMP2X3", "JMP2X3SWAP", "MINIDIN6", "TB4"}

def _nat(ref):
    m = re.match(r"([A-Za-z]+)(\d+)", ref)
    return (m.group(1), int(m.group(2))) if m else (ref, 0)

def _chunk(lst, n):
    return [lst[i:i + n] for i in range(0, len(lst), n)]

def classify(card):
    active, conn, passive = [], [], []
    for ref, (dev, f, v) in card.parts.items():
        (passive if dev in PASSIVE else conn if dev in CONN else active).append(ref)
    return (sorted(active, key=_nat), sorted(conn, key=_nat), sorted(passive, key=_nat))

ICS_PER_WIRED_SHEET = 9       # keep an ELK-wired sheet readable
ICS_PER_ROW = 5               # rows on a label sheet

def auto_sheets(card):
    active, conn, passive = classify(card)
    sheets, wired = [], set()
    # active ICs: ELK-wired sheets, chunked
    chunks = _chunk(active, ICS_PER_WIRED_SHEET) or [[]]
    for i, chunk in enumerate(chunks, 1):
        if not chunk:
            continue
        title = "Logic %d of %d" % (i, len(chunks)) if len(chunks) > 1 else "Logic"
        sheets.append((title, [chunk]))        # one row: ELK lays it out in 2D
        wired.add(len(sheets))
    # connectors: their own label sheet (the DIN is large)
    if conn:
        sheets.append(("Backplane / edge connectors", [[r] for r in conn]))
    # passives: a label sheet, chunked into rows
    if passive:
        sheets.append(("Decoupling, resistors, LEDs", _chunk(passive, 12)))
    return sheets, wired

def backplane_sheets(card):
    """The backplane is the 8 slot connectors wired in parallel to the bus, plus
    the pull-up array, power entry and decoupling -- all label style (the slots
    connect by shared bus-signal labels, as a backplane schematic is drawn)."""
    slots = sorted([r for r, (d, f, v) in card.parts.items() if d == "DIN96"], key=_nat)
    rest = sorted([r for r in card.parts if r not in slots], key=_nat)
    sheets = []
    for grp in _chunk(slots, 2):               # 2 slot connectors per sheet
        sheets.append(("DIN 41612 bus slots %s" % ", ".join(grp), [grp]))
    sheets.append(("Bus pull-ups, power entry, decoupling", _chunk(rest, 8)))
    return sheets, set()                        # no ELK wiring

def functional_sheets(blocks):
    """A card drawn by function, as a hand-drawn schematic is: each block is one
    ELK-wired sheet holding its ICs AND the resistors, LEDs, crystals and local
    connectors they drive, so the nets between them are drawn as wires. Whatever
    no block claims (the bus connector, decoupling) goes on a final label sheet.
    blocks = [(title, [ref, ...]), ...]"""
    def build(card):
        claimed = [r for t, refs in blocks for r in refs]
        missing = [r for r in claimed if r not in card.parts]
        if missing:
            raise SystemExit("%s sheet groups name unknown parts: %s" % (card.name, missing))
        sheets, wired = [], set()
        for title, refs in blocks:
            sheets.append((title, [refs]))
            wired.add(len(sheets))
        rest = sorted([r for r in card.parts if r not in claimed], key=_nat)
        if rest:
            sheets.append(("Bus connector, decoupling", _chunk(rest, 12)))
        return sheets, wired
    return build

# io-card by function (2026-10-24); the blocks follow hardware/io-card/README.md.
IO_CARD = functional_sheets([
    ("Address decode and port strobes",
     ["U1", "U2", "U3", "U4", "U5", "U6", "U15", "U18", "R4", "LED4"]),
    ("Switch input and LED output ports",
     ["SW1", "RNP", "U9", "U10", "RL1", "LA1"]),
    ("Serial: two 6850 ACIAs, baud clock, RS-232",
     ["X2", "U7", "U14", "U17", "U8", "C2", "C3", "C4", "C5", "JP1", "JP2", "DB9A", "DB9B"]),
    ("Bus monitor LEDs",
     ["U11", "U12", "U13", "RM1", "RM2", "RM3", "LM1", "LM2", "LM3"]),
    ("Real-time clock (DNP)",
     ["U16", "X3", "BT1", "J3"]),
])

# per-board explicit overrides: name -> function(card) -> (sheets, wired)
SHEETS = {"backplane": backplane_sheets, "io-card": IO_CARD}

def sheets_for(card):
    if card.name in SHEETS:
        return SHEETS[card.name](card)
    return auto_sheets(card)
