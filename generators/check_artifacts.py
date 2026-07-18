#!/usr/bin/env python3
"""Freshness gate: fail if any committed hardware artifact is out of sync with a
fresh build. Run before sync, or wire into CI / a pre-commit hook:

    python3 generators/check_artifacts.py     # exit 0 = in sync, 1 = stale

Regenerates everything via build_all.py, then asks git whether anything under
hardware/ changed. Because the PDFs render in invariant mode (build_all.py), a
clean tree stays clean -- any diff means a committed file did NOT match its source
(someone edited a netlist and forgot to re-render, or hand-edited an artifact).

This is the mechanical answer to "how do the schematic PDFs stay in sync": they
are checked, not trusted. It catches the missing-re-render case on all 9 boards;
the backplane schematic additionally cannot drop a bus signal (render_bp_traditional
derives its rows from busnet() and asserts completeness).
"""
import subprocess, sys, os

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

def main():
    r = subprocess.run([sys.executable, os.path.join(HERE, "build_all.py")])
    if r.returncode != 0:
        print("check-artifacts: BUILD FAILED"); return r.returncode
    diff = subprocess.run(["git", "status", "--porcelain", "--", "hardware/"],
                          cwd=ROOT, capture_output=True, text=True)
    dirty = [l for l in diff.stdout.splitlines() if l.strip()]
    if dirty:
        print("\ncheck-artifacts: STALE — these committed artifacts do not match a fresh build:")
        for l in dirty: print("  " + l)
        print("\nRun `python3 generators/build_all.py` and commit the result.")
        return 1
    print("check-artifacts: OK — all hardware artifacts match a fresh build")
    return 0

if __name__ == "__main__":
    sys.exit(main())
