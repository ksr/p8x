# Claude Code memory

These files are Claude Code's persistent memory for the P8X project: accumulated
facts about the machine, the toolchain, and the working conventions that aren't
derivable from the code or git history. `MEMORY.md` is the index — one line per
memory — and is the only file loaded into context automatically. The rest are
pulled in on demand.

They live in the repo so they're versioned and backed up rather than sitting in
a single untracked home directory.

## How Claude finds them

Claude Code derives its memory directory from the flattened path of the
directory it was launched in:

    ~/Developer/p8x        ->  ~/.claude/projects/-Users-ksr77-Developer-p8x/memory/
    ~/Documents/claude test ->  ~/.claude/projects/-Users-ksr77-Documents-claude-test/memory/

Those paths are symlinks to this directory, so either launch point sees the same
memories and writes land here, in the repo. (The repo moved from
`~/Documents/Projects/p8x` on 2026-09-14 to escape a Documents sync client that
was spawning conflict copies; the legacy `-Users-ksr77-Documents-Projects-p8x`
key is still linked here too, so old session transcripts keep resolving.)

To re-create the links (after a reinstall, or on another machine):

    cd ~/.claude/projects
    ln -s ~/Developer/p8x/docs/memory ./-Users-ksr77-Developer-p8x/memory
    ln -s ~/Developer/p8x/docs/memory ./-Users-ksr77-Documents-claude-test/memory
    ln -s ~/Developer/p8x/docs/memory ./-Users-ksr77-Documents-Projects-p8x/memory   # legacy launch point

Those directory names begin with `-`, so prefix paths with `./` or `ls` and
friends will read them as command-line flags.

## Editing

Claude maintains these itself. Editing them by hand is fine — they're just
markdown with a frontmatter block. If you add or delete a file, update the
matching line in `MEMORY.md`, which is what gets read first.
