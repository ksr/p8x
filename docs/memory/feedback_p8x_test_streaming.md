---
name: feedback_p8x_test_streaming
description: "Run P8X regression suite with raw streaming output to a logfile, not piped through grep"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: df90e3f3-8668-416d-bc7b-83f2952ba723
---

When running the P8X regression suite (`make test` in `emulator/`), write **raw, unbuffered** output to a logfile so progress streams line-by-line and can be watched live — e.g. `make test > /tmp/reg.log 2>&1` run in the background, then tail/read the log.

**Why:** piping `make test` through `grep` (to count PASS/FAIL) block-buffers the output when stdout isn't a TTY, so nothing appears until the whole run finishes — the user can't see running progress. Writing straight to a file flushes per line (the test scripts echo `NAME TEST: PASS` on completion).

**How to apply:** background the run writing to a logfile; for a status check, read the log and count `TEST: PASS` lines and show the last line. Do the PASS/FAIL tally by grepping the finished log afterward, not in the live pipe. The full suite is ~50 tests; `test-c` (C compiler) is the slowest phase. See [[project_p8x]] and [[feedback_p8x_docs_before_sync]].
