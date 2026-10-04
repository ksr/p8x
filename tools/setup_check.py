#!/usr/bin/env python3
"""setup_check.py -- verify the P8X toolchain on a machine, tier by tier.

Run it after cloning P8X onto a new Mac to see what is installed and what each
work area still needs:

    python3 tools/setup_check.py            # check every tier
    python3 tools/setup_check.py --tier 1   # only the core-dev tier
    python3 tools/setup_check.py -q         # summary line only

The tiers match SETUP.md:

    1  core software    emulator, microcode, assembler, OS, compiler, tests
    2  hardware / CAD   KiCad board regeneration + Freerouting
    3  documentation    the reference PDFs
    4  website & FPGA   MkDocs site and the Icarus/Tang-Nano flow

Tier 1 is required; the rest are optional and only gate the work that uses them.
The exit code is non-zero only when a Tier 1 tool is missing, so the script is
safe to drop into a build gate. Paths honour the same overrides the build
scripts read -- FRJAR for the Freerouting jar, CHROME for the Chrome binary.
"""
import os, sys, shutil, argparse, importlib.util

HOME = os.path.expanduser("~")
KICAD = "/Applications/KiCad/KiCad.app/Contents"
PYK = KICAD + "/Frameworks/Python.framework/Versions/3.9/bin/python3"
CLI = KICAD + "/MacOS/kicad-cli"
FOOTPRINTS = KICAD + "/SharedSupport/footprints"
FRJAR = os.environ.get("FRJAR", os.path.join(HOME, "freerouting", "freerouting.jar"))
CHROME = os.environ.get("CHROME", "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome")

USE_COLOR = sys.stdout.isatty() and os.environ.get("NO_COLOR") is None
def paint(s, code):
    return "\033[%sm%s\033[0m" % (code, s) if USE_COLOR else s

# --- probes -------------------------------------------------------------------
def have_cmd(*names):
    """First of names found on PATH, or None."""
    for n in names:
        p = shutil.which(n)
        if p:
            return p
    return None

def have_path(p):
    return p if os.path.exists(p) else None

def have_module(mod):
    """Is a Python module importable by THIS interpreter? (host python3)"""
    try:
        return importlib.util.find_spec(mod) is not None
    except (ImportError, ValueError):
        return False

# --- the tiers ----------------------------------------------------------------
# each check: (label, found-value-or-None, fix-hint)
def tier1():
    return [
        ("C compiler (cc/clang)", have_cmd("cc", "clang"), "xcode-select --install"),
        ("make",                  have_cmd("make"),        "xcode-select --install"),
        ("git",                   have_cmd("git"),         "xcode-select --install"),
        ("python3 >= 3.6",        sys.executable if sys.version_info >= (3, 6) else None,
                                  "install a current python3 (Xcode CLT ships one)"),
    ]

def tier2():
    return [
        ("KiCad bundled python (pcbnew)", have_path(PYK), "brew install --cask kicad"),
        ("kicad-cli",                     have_path(CLI), "brew install --cask kicad"),
        ("KiCad footprint library",       have_path(FOOTPRINTS), "comes with KiCad"),
        ("java (for Freerouting)",        have_cmd("java"), "brew install temurin"),
        ("Freerouting jar  [$FRJAR]",     have_path(FRJAR),
                                          "download freerouting 1.9.0 jar to %s" % FRJAR),
    ]

def tier3():
    return [
        ("reportlab (host python3)", "importable" if have_module("reportlab") else None,
                                     "%s -m pip install reportlab" % os.path.basename(sys.executable)),
        ("Google Chrome  [$CHROME]", have_path(CHROME), "brew install --cask google-chrome"),
    ]

def tier4():
    venv_ok = have_module("venv") and have_module("ensurepip")
    return [
        ("python venv + ensurepip", "available" if venv_ok else None,
                                    "needed by website/build.sh; ships with python3"),
        ("iverilog (FPGA co-sim)",  have_cmd("iverilog"), "brew install icarus-verilog"),
        ("openFPGALoader (flash)",  have_cmd("openFPGALoader"),
                                    "from oss-cad-suite (optional; board flashing only)"),
    ]

TIERS = [
    (1, "Core software      (emulator, microcode, asm, OS, compiler, tests)", tier1, True),
    (2, "Hardware / CAD     (KiCad board regeneration + Freerouting)",        tier2, False),
    (3, "Documentation      (the reference PDFs)",                            tier3, False),
    (4, "Website & FPGA     (MkDocs site, Icarus/Tang-Nano flow)",            tier4, False),
]

# --- run ----------------------------------------------------------------------
def main():
    ap = argparse.ArgumentParser(description="Check the P8X toolchain, tier by tier.")
    ap.add_argument("--tier", type=int, choices=[1, 2, 3, 4],
                    help="check only this tier (default: all)")
    ap.add_argument("-q", "--quiet", action="store_true", help="summary line only")
    args = ap.parse_args()

    ok_mark   = paint("  ok ", "32")   # green
    miss_req  = paint("MISS!", "31")   # red  -- required and absent
    miss_opt  = paint(" -- ", "33")    # yellow -- optional and absent

    required_missing = 0
    optional_missing = 0

    for num, title, fn, required in TIERS:
        if args.tier and num != args.tier:
            continue
        rows = fn()
        if not args.quiet:
            tag = "required" if required else "optional"
            print("\n%s %s  [%s]" % (paint("Tier %d" % num, "1;36"), title, tag))
        for label, found, hint in rows:
            if found:
                if not args.quiet:
                    detail = found if isinstance(found, str) else ""
                    print("   %s %-32s %s" % (ok_mark, label, paint(detail, "90")))
            else:
                if required:
                    required_missing += 1
                else:
                    optional_missing += 1
                if not args.quiet:
                    mark = miss_req if required else miss_opt
                    print("   %s %-32s %s" % (mark, label, paint("-> " + hint, "90")))

    print()
    if required_missing:
        print(paint("FAIL", "1;31") +
              ": %d core tool(s) missing -- Tier 1 must be complete to build P8X." % required_missing)
        print("      Fix the Tier 1 items above, then re-run this check.")
    else:
        extra = (" (%d optional tool(s) not installed -- only needed for the tiers above)"
                 % optional_missing) if optional_missing else ""
        print(paint("OK", "1;32") + ": core toolchain is ready." + extra)
        print("     Verify with:  cd emulator && make && make test")
    return 1 if required_missing else 0

if __name__ == "__main__":
    sys.exit(main())
