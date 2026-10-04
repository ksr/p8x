# Setting up a machine to work on P8X

P8X is a macOS project. The whole machine — every KiCad board, the emulator,
microcode, OS, compiler, firmware, docs, and the committed ROM/Gerber artifacts
— lives in this one repository, so setup is: install the toolchain, clone, and
verify.

The toolchain splits into four tiers. **Only Tier 1 is required** — it is enough
to write and build the emulator, microcode, assembler, OS, compiler and firmware,
and to run the tests. The higher tiers are needed only for the work that uses
them, so a machine meant purely for software development can stop after Tier 1.

| Tier | Area | Needed for |
|------|------|------------|
| 1 | Core software | emulator, microcode, assembler, OS, compiler, `make test` |
| 2 | Hardware / CAD | regenerating the KiCad boards (placement → Freerouting → Gerbers → DRC) |
| 3 | Documentation | the reference PDFs (programmer's guide, bus definition, memory map) |
| 4 | Website & FPGA | the MkDocs site and the Icarus/Tang-Nano simulation + board flow |

## Check what is already present

After cloning, run the checker. It reports every tier and names the fix for
anything missing; its exit code is non-zero only when a **Tier 1** tool is absent.

```sh
python3 tools/setup_check.py
```

Re-run it after installing something to confirm the gap is closed. `--tier N`
limits it to one tier; `-q` prints only the summary line.

## Clone

The remote is HTTPS, so cloning needs no special setup:

```sh
git clone https://github.com/ksr/p8x.git ~/Developer/p8x
```

Pushing over HTTPS needs a credential. The simplest is the GitHub CLI, which
stores a token in the macOS keychain — install it (Tier-0 tools, below), then run
`gh auth login` and choose HTTPS.

## Verify Tier 1

```sh
cd ~/Developer/p8x/emulator && make && make test
```

A healthy machine prints `P8X lives! same ucode as the EPROMs` and then HALTs.
Once that passes, the machine is ready for all core development.

---

## Tier 0 — base system

On a Mac with administrator access, the base tools come from Apple's Command Line
Tools and Homebrew.

Command Line Tools provide `cc`/clang, `make` and `git`:

```sh
xcode-select --install
```

Homebrew is the package manager for everything else:

```sh
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

The GitHub CLI handles push authentication:

```sh
brew install gh
```

### A managed Mac without administrator access

On an IT-managed Mac the standard Homebrew install fails (it cannot write to
`/opt/homebrew` and cannot use `sudo`). Two facts make this a non-problem for
software development:

1. **Core development needs no administrator rights.** If the checker shows
   Tier 1 already green — managed dev Macs usually ship with the Command Line
   Tools — clone and build straight away; nothing else is required.
2. **Homebrew installs into a home directory without `sudo`.** Unpack it under
   `~/homebrew` and add it to the shell:

   ```sh
   mkdir -p ~/homebrew && curl -L https://github.com/Homebrew/brew/tarball/master | tar xz --strip-components 1 -C ~/homebrew
   ```

   ```sh
   echo 'eval "$($HOME/homebrew/bin/brew shellenv)"' >> ~/.zprofile && eval "$($HOME/homebrew/bin/brew shellenv)"
   ```

   A home-directory Homebrew cannot use Apple's prebuilt bottles, so some
   formulae compile from source (slower), but it installs CLI tools —  `gh`,
   `temurin`, `icarus-verilog` — without administrator rights.

Casks that install into `/Applications` (KiCad, Google Chrome) still need a
writable `/Applications`; where that is locked down, those Tier 2–3 tools need
IT to install them, or a copy kept in a home directory with the generator paths
pointed at it. A machine doing only Tier 1 software work needs none of them.

## Tier 1 — core software

Provided entirely by Tier 0 (clang + `make` + `git` + `python3`). No third-party
Python packages are required to build the emulator or run the tests.

## Tier 2 — hardware / KiCad board regeneration

The board generators call KiCad's **bundled** Python (for `pcbnew`) and
`kicad-cli` at fixed paths under `/Applications/KiCad/KiCad.app`, and route with
Java-based Freerouting.

```sh
brew install --cask kicad
```

```sh
brew install temurin
```

Freerouting is a single jar. The build scripts look for it at
`~/freerouting/freerouting.jar` (override with the `FRJAR` environment variable).
Download the Freerouting 1.9.0 release jar and place it there:

```sh
mkdir -p ~/freerouting
```

With those present, a board regenerates and passes its readiness check end to
end — for example:

```sh
sh generators/build.sh memory-card
```

## Tier 3 — documentation PDFs

The reportlab PDFs (programmer's guide, bus definition, ISA card) import
`reportlab` into the **host** Python:

```sh
python3 -m pip install reportlab
```

The memory-map PDF renders through headless Google Chrome (override the binary
with the `CHROME` environment variable):

```sh
brew install --cask google-chrome
```

Regenerate, for example:

```sh
python3 microcode/gen_progguide.py
```

```sh
python3 generators/gen_memmap_pdf.py
```

## Tier 4 — website and FPGA

The website build creates its own Python virtual environment from
`website/requirements.txt`, so it needs no manual package install — only a
working `python3` with `venv`:

```sh
sh website/build.sh serve
```

The FPGA co-simulation needs Icarus Verilog; the Tang Nano 20K board build and
flashing additionally need oss-cad-suite (which provides `openFPGALoader`):

```sh
brew install icarus-verilog
```

---

## Working from two machines

With more than one machine on the same branch, pull before starting and push when
finishing on each, or the two clones diverge. Commit directly per the project
workflow; branch only when a feature needs it, and never merge a branch to `main`
without explicit confirmation.

Claude Code's cross-session memory is **not** part of the repository — it lives
under `~/.claude/` on each machine — so a fresh Claude Code on another Mac starts
without those notes. The repository's own documentation (CLAUDE.md, the READMEs,
BACKLOG.md) travels with the clone and carries the load-bearing facts.
