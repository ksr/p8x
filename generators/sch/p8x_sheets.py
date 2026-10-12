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

PASSIVE = {"CAP", "CAP1", "RES", "LED", "SIP9", "RNISO8", "RNISO8D", "LEDARR8",
           "XTAL32", "COIN", "SW2", "DIP8SW"}
CONN = {"DIN96C", "DIN96", "DSUB9F", "IDE40", "HDR3", "HDR4", "HDR10", "JMP2X3", "MINIDIN6"}

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

# per-card explicit overrides: name -> function(card) -> (sheets, wired)
SHEETS = {}

def sheets_for(card):
    if card.name in SHEETS:
        return SHEETS[card.name](card)
    return auto_sheets(card)
