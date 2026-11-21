#!/usr/bin/env python3
"""qa.py -- the P8X QA entry points behind `make qa-quick`, `make qa` and `make qa-fresh`
(the same three targets as in YACC1-D, elf and P32W; chosen 2026-11-20).

    python3 tools/qa.py quick    # ~3-7 min: before every commit; pcb-check's tests = for the boards
    python3 tools/qa.py full     # ~40 min: the whole suite, before an order or a release
    python3 tools/qa.py fresh    # ~1.5 min: every committed generated file against a fresh build

Three rules hold for all three:
  - nothing tracked changes: the working tree's tracked files are compared before and after
    (git status), and a run that changed one fails, naming it. New untracked files that are
    not ignored are listed too (a test leaving scratch behind);
  - a skip is not a pass: a step that prints a SKIP line (`... TEST: SKIP (no host cc)`) is
    reported as skipped, and the run does not end in OK;
  - every step runs, even after one fails, and the summary gives each step's result and time.

`fresh` never builds in the repository: it copies the tracked files, as they are on disk now,
into a temporary git repository, runs the generators there, and asks that copy's git what
changed. The boards are checked by generators/check_artifacts.py, which makes its own copy.
"""
import os, re, shutil, subprocess, sys, tempfile, time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

COSIMS = [  # CLAUDE.md: re-run all three after any change to fpga/rtl/ or the microcode
    ("co-sim: boot", "fpga/sim", "./run.sh 20000"),
    ("co-sim: all opcodes", "fpga/sim", "./run.sh 60000 isa_test.asm"),
    ("co-sim: driven monitor + console", "fpga/sim", './run.sh 200000 "" console_in.txt'),
]
QUICK = [
    ("emulator: make test-quick", "emulator", "make test-quick"),
] + COSIMS + [
    ("netlist ERC, every card", "generators", "python3 gen_erc.py"),
]
FULL = [
    ("emulator: make test", "emulator", "make test"),
] + COSIMS + [
    ("netlist ERC, every card", "generators", "python3 gen_erc.py"),
]
NOT_IN_FULL = [  # said at the end of every full run, so their absence is never mistaken for a pass
    "make test-full (adds the self-host and full system build to make test)",
    "the FPGA benches run by hand (fpga/tang-nano-20k/sdram/tb_*, fpga/rtl/tb_gtxt.v)",
    "tools/gatesim: it models memory-card rev E, not the rev F board",
]

# (what, folder in the copy, command): each writes its outputs in place, as in the repository
GENERATORS = [
    ("microcode images (genucode.py)", "microcode", "python3 genucode.py"),
    ("burnable ROM set (build_rom.sh)", ".", "sh tools/build_rom.sh"),
    ("memory map: .inc .h .py .vh, lib_mem (gen_memmap.py)", ".", "python3 generators/gen_memmap.py"),
    ("character generator (gen_chargen.py)", "generators", "python3 gen_chargen.py"),
    ("GL keyword tables (gen_glkw.py)", "generators", "python3 gen_glkw.py"),
    ("trig tables (gen_trig.py)", "generators", "python3 gen_trig.py"),
    ("programmer's guide (gen_progguide.py)", "microcode", "python3 gen_progguide.py"),
]
FRESH_NOT_CHECKED = [
    "docs/p8x-memory-map.pdf: printed by headless Chrome, whose version changes the bytes",
    "the board routing and renders: see generators/check_artifacts.py",
]
SKIP = re.compile(r"(^|:\s*)SKIP\b")
PDF_VOLATILE = re.compile(rb"(/(?:CreationDate|ModDate)\s*\()[^)]*(\))|(/ID\s*\[)[^\]]*(\])"
                          rb"|(<xmp:(?:CreateDate|ModifyDate|MetadataDate)>)[^<]*")

def git(*a, cwd=ROOT):
    return subprocess.run(["git"] + list(a), cwd=cwd, capture_output=True, text=True).stdout

def tree_state():
    """(tracked files changed or deleted, with their contents' hashes) and the untracked files
    git does not ignore"""
    changed = {}
    for line in git("status", "--porcelain", "--untracked-files=no").splitlines():
        path = line[3:]
        full = os.path.join(ROOT, path)
        changed[path] = git("hash-object", full).strip() if os.path.isfile(full) else "gone"
    untracked = set(git("ls-files", "--others", "--exclude-standard").splitlines())
    return changed, untracked

def stream(cmd, cwd):
    """run a shell command, echoing its output; return (exit status, the SKIP lines)"""
    p = subprocess.Popen(cmd, shell=True, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                         text=True, errors="replace")
    skips = []
    for line in p.stdout:
        sys.stdout.write("    " + line); sys.stdout.flush()
        if SKIP.search(line):
            skips.append(line.strip())
    return p.wait(), skips

def run(tier):
    steps = QUICK if tier == "quick" else FULL
    before, untracked0 = tree_state()
    results, t0 = [], time.time()
    for what, folder, cmd in steps:
        print("\n== %s  (%s: %s)" % (what, folder, cmd), flush=True)
        t = time.time()
        rc, skips = stream(cmd, os.path.join(ROOT, folder))
        status = "FAIL" if rc else ("SKIP" if skips else "PASS")
        results.append((status, what, time.time() - t, skips))
    after, untracked1 = tree_state()
    touched = sorted(p for p in set(before) | set(after) if before.get(p) != after.get(p))
    leftovers = sorted(untracked1 - untracked0)
    print("\n" + "=" * 72 + "\nqa %s: %d steps in %.0f min" % (tier, len(steps), (time.time() - t0) / 60))
    for status, what, secs, skips in results:
        print("  %-4s  %-44s %6.0f s" % (status, what, secs))
        for s in skips:
            print("          skipped: " + s[:100])
    if touched:
        print("  FAIL  tracked files changed by the run (they must not be):")
        for p in touched: print("          " + p)
    if leftovers:
        print("  WARN  new untracked files left behind (not ignored):")
        for p in leftovers[:20]: print("          " + p)
    if tier == "full":
        print("  not in qa: " + "; ".join(NOT_IN_FULL))
    bad = [r for r in results if r[0] != "PASS"]
    if bad or touched:
        print("qa %s: NOT OK (%d failed, %d skipped%s)" % (tier, sum(r[0] == "FAIL" for r in results),
              sum(r[0] == "SKIP" for r in results), ", tracked files changed" if touched else ""))
        return 1
    print("qa %s: OK" % tier)
    return 0

def pdf_same(a, b):
    with open(a, "rb") as fa, open(b, "rb") as fb:
        sub = lambda m: b"".join(g for g in m.groups() if g)
        return PDF_VOLATILE.sub(sub, fa.read()) == PDF_VOLATILE.sub(sub, fb.read())

def fresh():
    tmp = tempfile.mkdtemp(prefix="p8x-qa-fresh-")
    copy = os.path.join(tmp, "p8x")
    probs, notes = [], []
    try:
        for rel in git("ls-files", "-z").split("\0"):
            src = os.path.join(ROOT, rel)
            if rel and os.path.isfile(src):
                os.makedirs(os.path.dirname(os.path.join(copy, rel)), exist_ok=True)
                shutil.copy2(src, os.path.join(copy, rel))
        git("init", "-q", cwd=copy); git("add", "-A", cwd=copy)
        git("-c", "user.name=qa", "-c", "user.email=qa@localhost", "commit", "-qm", "the tree as it is", cwd=copy)
        for what, folder, cmd in GENERATORS:
            r = subprocess.run(cmd, shell=True, cwd=os.path.join(copy, folder), capture_output=True, text=True)
            print("  %-4s  %s" % ("ran" if r.returncode == 0 else "FAIL", what), flush=True)
            if r.returncode:
                probs.append("%s failed: %s" % (what, (r.stdout + r.stderr).strip().splitlines()[-1:]))
        stale = []
        for line in git("status", "--porcelain", cwd=copy).splitlines():
            path = line[3:].strip('"')
            if line.startswith("??"):
                notes.append("made by a generator, not committed: " + path)
            elif path.endswith(".pdf") and os.path.exists(os.path.join(copy, path)):
                orig = os.path.join(tmp, "orig.pdf")
                with open(orig, "wb") as fh:
                    fh.write(subprocess.run(["git", "show", "HEAD:" + path], cwd=copy, capture_output=True).stdout)
                if not pdf_same(orig, os.path.join(copy, path)):
                    stale.append(path)
            else:
                stale.append(path)
        for p in stale:
            probs.append("stale: %s (its generator makes it differently)" % p)
        # copies of the images that no generator here writes: each must equal the fresh build
        mon = os.path.join(tmp, "monitor.bin")
        subprocess.run(["python3", "assembler/p8xasm.py", "firmware/p8xmon.asm", "-o", mon],
                       cwd=copy, capture_output=True)
        pairs = [("os/u%d.bin" % k, "microcode/u%d.bin" % k) for k in range(4)]
        pairs += [("os/eeprom.bin", mon), ("emulator/eeprom.bin", mon)]
        for mine, want in pairs:
            a = os.path.join(copy, mine); b = want if os.path.isabs(want) else os.path.join(copy, want)
            if open(a, "rb").read() != open(b, "rb").read():
                probs.append("stale: %s is not the fresh %s" % (mine, "monitor (firmware/p8xmon.asm)" if b == mon else want))
        print("  ran   copies: os/u0-3.bin, os/eeprom.bin, emulator/eeprom.bin")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    print("\n== boards: generators/check_artifacts.py", flush=True)
    rc, _ = stream("python3 generators/check_artifacts.py", ROOT)
    if rc:
        probs.append("boards: generators/check_artifacts.py found stale board files (above)")
    print("\n" + "=" * 72)
    for n in notes: print("  NOTE  " + n)
    for n in FRESH_NOT_CHECKED: print("  not checked: " + n)
    for p in probs: print("  NOT OK  " + p)
    print("qa fresh: %s" % ("OK" if not probs else "NOT OK (%d)" % len(probs)))
    return 1 if probs else 0

if __name__ == "__main__":
    what = sys.argv[1] if len(sys.argv) > 1 else ""
    if what in ("quick", "full"): sys.exit(run(what))
    if what == "fresh": sys.exit(fresh())
    sys.exit("usage: tools/qa.py quick|full|fresh")
