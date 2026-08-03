---
name: feedback_ecad_schematic_truth
description: "In the Eagle/Fusion ECAD workflow, the schematic (.sch) is ALWAYS the source of truth; reconcile the board to it, never the reverse"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: df90e3f3-8668-416d-bc7b-83f2952ba723
  modified: 2026-07-21T19:30:55.612Z
---

## File naming: `-a` marks the LIVE files

The user's convention (applies to any board, not just arduino-scratch):

- **No suffix** (`<board>.sch` / `.brd`) = what Claude generated. The user does NOT
  rename these.
- **`-a` suffix** (`<board>-a.sch` / `-a.brd`) = the user's Fusion working copies,
  created once they start moving files back and forth.

**So: if a `-a` pair exists, THAT is the authoritative hand-edited design — edit
those.** The unsuffixed pair is the older generated baseline; leave it alone.
Always check for a `-a` pair before touching anything.

## Schematic is the source of truth

For P8X hardware and the arduino-scratch test board: when the `.sch` and `.brd`
diverge, the **schematic is always the source of truth**. Reconcile the board to
match the schematic — never edit the schematic to match the board.

**Why:** standard forward-annotation practice — connectivity is designed in the
schematic and the board follows. The user stated this as an absolute ("always").

**How to apply** when reconciling a `.sch`/`.brd` pair (see [[project_arduino_scratch_board]]):
- Part in schematic but not board → **pull it into the board**: add the matching
  `<element>` (park at a default position; the user places it) + `<contactref>`
  entries in the right `<signal>`s, creating new `<signal>`s for new nets.
- Part in board but not schematic → it was **deleted from the schematic** →
  remove it from the board. Do NOT add it back to the schematic.
- Net membership differs → update the board's signals to match the schematic's
  net (pin↔pad via the device `pm` map).
- No need to ask "which direction" — the schematic always wins.

Editing must be in-place on the actual (possibly Fusion-round-tripped, 9.7.0)
files, not regenerated, once the user has hand-placed parts. Verify consistency
after: same part names both sides + identical pin↔pad net membership per net.
