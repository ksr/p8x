---
name: feedback-verify-index-coverage
description: Before saying a file "is not in any copy", prove the index covers the disk (count files on disk vs indexed per folder); the YACCS inventory silently skipped every CAMOutputs dir for a day
metadata:
  type: feedback
---

On 2026-09-20 I told Ken the Index Registers 1.1 gerbers were "in none of the 13 copies nor anywhere on this Mac".
They were in `PCB/Production/Index Registers 1.1/CAMOutputs/` all along: my `inventory.py` had `CAMOutputs` in
SKIP_DIRS (2,984 files invisible), so every "none in tree" claim and the whole first fab layout were built on a
hole in the index. Ken caught it by asking "did you look into PCB/Production in the original tree?".

**Why:** an index is only as good as its skip list; negative claims ("not anywhere") are the ones that mislead.
**How to apply:** before any "X does not exist" statement, run `find <dir> -type f | wc -l` against the indexed
count for the same dir; whenever a skip list exists, print it in the report. Keep both index files
(`yaccs-index-2026-09-19.json` = the broken one, `-20` = complete). See [[project-yacc1-kicad]].
