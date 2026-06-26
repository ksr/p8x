#!/usr/bin/env python3
"""clib.py — trivial source includer for P8X /BIN command sources.

p8cc has no #include and there is no linker, so reusable helpers are shared by
*concatenation*: a command source opts in with a line

    //#use NAME

which this tool replaces, in place, with the contents of `lib_NAME.c` found in
the SAME directory as the command source (e.g. os/commands/lib_stdin.c). A
source with no `//#use` line passes through unchanged, so the build step can run
clib.py over every command uniformly.

The spliced helper text is emitted ABOVE the rest of the command, so its
functions are defined before any caller — which keeps the combined source inside
the native p8cc.c subset (no forward declarations). The combined output is then
fed to either compiler: `p8cc.py combined.c` (file arg) or `p8cc_host <
combined.c` (stdin).

This is a host-era convenience. When the C toolchain self-hosts on the P8X
(backlog Milestone B), the compiler is expected to become a multipass driver of
separate /BIN binaries staged through temp files; this preprocessor is the
natural first pass, so a native C rewrite of clib.py (reading via BIOS
FOPEN/FGETB) becomes the on-target CPP.BIN. Keeping it tiny keeps that port tiny.

Usage:
    clib.py SRC.c [-o OUT.c]      # default: write combined source to stdout
"""
import argparse
import os
import re
import sys

# Match a `//#use NAME` directive; anything after NAME (e.g. a trailing comment)
# is ignored, so `//#use stdin   /* ... */` still expands.
USE_RE = re.compile(r'^\s*//#use\s+([A-Za-z_][A-Za-z0-9_]*)\b')


def expand(src_path):
    src_dir = os.path.dirname(os.path.abspath(src_path))
    out = []
    with open(src_path, 'r') as f:
        for lineno, line in enumerate(f, 1):
            m = USE_RE.match(line)
            if not m:
                out.append(line)
                continue
            name = m.group(1)
            lib_path = os.path.join(src_dir, 'lib_%s.c' % name)
            if not os.path.exists(lib_path):
                sys.exit("clib.py: %s:%d: no such library 'lib_%s.c' in %s"
                         % (src_path, lineno, name, src_dir))
            with open(lib_path, 'r') as lf:
                out.append('/* --- clib.py: spliced lib_%s.c --- */\n' % name)
                out.append(lf.read())
                out.append('/* --- clib.py: end lib_%s.c --- */\n' % name)
    return ''.join(out)


def main():
    ap = argparse.ArgumentParser(description="Splice //#use libraries into a command source.")
    ap.add_argument('src', help="command source (.c)")
    ap.add_argument('-o', '--out', help="output file (default: stdout)")
    args = ap.parse_args()
    combined = expand(args.src)
    if args.out:
        with open(args.out, 'w') as f:
            f.write(combined)
    else:
        sys.stdout.write(combined)


if __name__ == '__main__':
    main()
