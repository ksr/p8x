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

PASSIVE = {"CAP", "CAP1", "CAPP", "RES", "LED", "SIP9", "RNISO8", "RNISO8D", "RNISO8DSTR", "LEDARR8",
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
    ELK-wired sheet holding its ICs AND the glue, resistors, LEDs, crystals and
    local connectors they drive, so the nets between them are drawn as wires.
    blocks = [(title, [ref, ...]), ...] names the main parts of each block; any
    part left unnamed that shares a local net (not power, not a bus signal) with a
    block joins the block it shares the most with, repeated until stable, so a
    gate, an LED and its resistor follow the logic they belong to. Whatever is
    still unclaimed (the bus connector, decoupling, the power LED) goes on a final
    label sheet."""
    def build(card):
        from p8x_card import SIGNALS
        named = [r for t, refs in blocks for r in refs]
        missing = [r for r in named if r not in card.parts]
        dup = sorted({r for r in named if named.count(r) > 1})
        if missing or dup:
            raise SystemExit("%s sheet groups: unknown parts %s, listed twice %s" % (card.name, missing, dup))
        local = {}
        for n, pins in card.nets.items():
            if n in ("VCC", "GND") or n in SIGNALS:
                continue
            for r, p in pins:
                local.setdefault(r, set()).add(n)
        groups = [list(refs) for t, refs in blocks]
        home = {r: i for i, refs in enumerate(groups) for r in refs}
        changed = True
        while changed:
            changed = False
            for r in sorted(card.parts, key=_nat):
                if r in home or not local.get(r):
                    continue
                score = [sum(len(local[r] & local.get(m, set())) for m in g) for g in groups]
                if max(score):
                    i = score.index(max(score))
                    groups[i].append(r); home[r] = i; changed = True
        sheets, wired = [], set()
        for (title, refs), g in zip(blocks, groups):
            sheets.append((title, [g]))
            wired.add(len(sheets))
        rest = sorted([r for r in card.parts if r not in home], key=_nat)
        if rest:
            sheets.append(("Bus connector, decoupling", _chunk(rest, 12)))
        return sheets, wired
    return build

# Cards drawn by function (io-card 2026-10-24, the rest the same day). Each list
# names a block's main parts; glue gates, LEDs and resistors attach themselves.
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

CONTROL_CARD = functional_sheets([
    ("Clock, reset and run/step", ["X1", "U1", "JP1", "U2", "U3"]),
    ("Instruction register, step counter, condition mux", ["U7", "U8", "U18", "U9", "U19"]),
    ("Microcode ROMs and pipeline register",
     ["U10", "U11", "U12", "U13", "U14", "U15", "U16", "U17"]),
    ("Interrupt controller (DNP)", ["U20", "U21"]),
])

REGBANK_CARD = functional_sheets([
    # one pointer per sheet: its four 74169s and two select buffers (the shared
    # pointer bus PB0-7 joins the sheets by label)
    ("Pointer P0 (PC)", ["U1", "U2", "U3", "U4", "U17", "U18"]),
    ("Pointer P1", ["U5", "U6", "U7", "U8", "U19", "U20"]),
    ("Pointer P2", ["U9", "U10", "U11", "U12", "U21", "U22"]),
    ("Pointer P3 (SP)", ["U13", "U14", "U15", "U16", "U23", "U24"]),
    ("Scratch counter PT", ["U41", "U42", "U43", "U44", "U49", "U50"]),
    ("Scratch counter PT2", ["U45", "U46", "U47", "U48", "U51", "U52"]),
    ("Address drivers and readback", ["U25", "U26", "U27", "U28", "U29"]),
    ("Load, select and count decode", ["U30", "U31", "U32", "U33", "U39", "U34", "U35",
                                       "U36", "U37", "U38", "U40", "U53"]),
])

ALU_CARD = functional_sheets([
    ("Operand registers A, B, T, T2", ["U1", "U2", "U3", "U4", "U5", "U6", "U7", "U8"]),
    ("ALU, carry lookahead, B-operand mux", ["U32", "U33", "U9", "U10", "U11"]),
    ("Shifter and result driver", ["U30", "U12", "U13", "U14", "U15", "U28", "U16"]),
    ("Flags C, Z, N, V", ["U18", "U27", "U22", "U29", "U26", "U17", "U34", "U35", "U23"]),
    ("Bus decode", ["U20", "U21"]),
])

MEMORY_CARD = functional_sheets([
    ("Decode, chip selects, activity LEDs", ["U4", "U5", "U6", "U7", "U8", "U9", "U11", "JWP"]),
    ("ROM, RAM and data buffer", ["U3", "U1", "U2", "U10"]),
])

CF_CARD = functional_sheets([
    ("Decode and IDE strobes", ["U2", "U3", "U4", "U5", "U6", "U7", "U11", "U8"]),
    ("CF socket 0: data path", ["U1", "U9", "J2", "RN1"]),
    ("CF socket 1: data path", ["U10", "J5", "RN3"]),
])

PS2_CARD = functional_sheets([
    ("Bus decode", ["U1", "U4", "U2", "U3", "U5", "U6"]),
    ("PS/2 microcontroller, mailbox latches, line buffers",
     ["U13", "U7", "U8", "U9", "U10", "U11", "U12", "JICSP", "RRST", "RRB", "RN1", "PS2A", "PS2B"]),
])

BUSTEST_CARD = functional_sheets([
    ("Pico, SPI buffer, status LEDs", ["A1", "U6", "D1", "R5", "R6", "R7", "R8", "RN2"]),
    ("Bus port expanders", ["U1", "U2", "U3", "U4"]),
    ("Probe inputs", ["U5", "U7", "RN1", "RN3", "J2"]),
])

# per-board explicit overrides: name -> function(card) -> (sheets, wired)
SHEETS = {"backplane": backplane_sheets, "io-card": IO_CARD, "control-card": CONTROL_CARD,
          "regbank-card": REGBANK_CARD, "alu-card": ALU_CARD, "memory-card": MEMORY_CARD,
          "cf-card": CF_CARD, "ps2-card": PS2_CARD, "bustest-card": BUSTEST_CARD}

def sheets_for(card):
    if card.name in SHEETS:
        return SHEETS[card.name](card)
    return auto_sheets(card)
