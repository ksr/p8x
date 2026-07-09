# os/man — manual pages

One plain-text manual page per command, the source for the on-target `/man`
directory. `run.sh` creates `/man` on the disk image and installs each file here
as `/man/<name>`, and the [`man`](../commands/man.c) command prints them:

```
man dir       ->  streams /man/dir
```

Pages cover both the `/bin` userland programs (`cat`, `grep`, `cp`, `vi`, …) and
the OS built-in commands (`cd`, `del`, `pack`, `mount`, …); `man` doesn't care
which — it just resolves `/man/<name>`.

## Format

Files are named after the command in **lower case** (matching how commands are
typed), with no extension, so `man cp` finds `/man/cp`. Keep them plain ASCII and
wrapped to ~72 columns for the serial console. The house layout is a subset of a
Unix man page:

```
NAME
    cp - copy files and directory trees

SYNOPSIS
    cp [-r] src dst

DESCRIPTION
    <a paragraph or two>

OPTIONS            (only if the command takes any)
    -r    ...

EXAMPLES
    cp a b          <what it does>

SEE ALSO
    mv, cat, del
```

## Adding a page

When you add a `/bin` command or an OS built-in, add `os/man/<name>` here in the
same layout. It is picked up automatically by `run.sh` (which globs `os/man/*`)
and by `os_man_test.sh`. Keep the content in step with the command's real
behaviour — the command source and `os/commands/README.md` are the source of
truth.
