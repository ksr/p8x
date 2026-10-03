# Author: Claude (Anthropic) for Ken Rother, 2026
"""MkDocs hook: a relative link to a repository file that is not part of the site (a source, a schematic, a PDF)
becomes a link to that file on GitHub; an image that is not part of the site is shown from GitHub's raw files.
A link to a directory goes to that directory's README page when the site has one, otherwise to the directory on
GitHub."""
import os, posixpath, re
from urllib.parse import unquote

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))   # the repository this folder is in
# the branch the GitHub links point at (graphics-card was merged into main 2026-10-02)
BRANCH = "main"
GH = "https://github.com/ksr/p8x"
RAW = "https://raw.githubusercontent.com/ksr/p8x/%s/" % BRANCH
LINK = re.compile(r'(!?)\[((?:[^\[\]]|\[[^\]]*\])*)\]\((<[^>]+>|[^)\s]+)((?:\s+"[^"]*")?)\)')
stats = {"github": 0, "readme": 0}


def alias(resolved):
    """The site page that stands in for a repository file staged under another name, or None: the repository README
    is the "Working on the code" page, and each manual page os/man/NAME is the generated page commands/NAME.md."""
    if resolved in ("", "README.md"): return "repository.md"
    if resolved.startswith("os/man/") and "/" not in resolved[7:] and resolved[7:] not in ("", "README.md"):
        return "commands/%s.md" % resolved[7:]
    return None


def on_page_markdown(markdown, page, config, files):
    site = {f.src_uri for f in files}
    here = posixpath.dirname(page.file.src_uri)

    def fix(m):
        bang, text, target, title = m.groups()
        t = target[1:-1] if target.startswith("<") else target
        if re.match(r"^[a-z][a-z0-9+.-]*:", t, re.I) or t.startswith("#") or t.startswith("/"): return m.group(0)
        path, _, frag = t.partition("#")
        if not path: return m.group(0)
        resolved = posixpath.normpath(posixpath.join(here, unquote(path)))
        if resolved in site or resolved.startswith(".."): return m.group(0)
        if resolved == ".": resolved = ""
        stand_in = alias(resolved)
        if stand_in and stand_in in site and not bang:
            stats["readme"] += 1
            return "[%s](<%s>%s)" % (text, posixpath.relpath(stand_in, here or ".") + ("#" + frag if frag else ""), title)
        if not os.path.exists(os.path.join(REPO, resolved)): return m.group(0)       # leave MkDocs to report it
        isdir = os.path.isdir(os.path.join(REPO, resolved))
        readme = posixpath.join(resolved, "README.md") if resolved else "README.md"
        if isdir and not bang and readme in site:
            stats["readme"] += 1
            rel = posixpath.relpath(readme, here or ".")
            return "[%s](<%s>%s)" % (text, rel + ("#" + frag if frag else ""), title)
        stats["github"] += 1
        if bang: url = RAW + resolved
        else:
            url = "%s/%s/%s/%s" % (GH, "tree" if isdir else "blob", BRANCH, resolved) + ("#" + frag if frag else "")
        return "%s[%s](<%s>%s)" % (bang, text, url, title)

    return LINK.sub(fix, markdown)


def on_post_build(config):
    print("hooks: %d links to files outside the site now point at GitHub (%s); %d links to directories or renamed "
          "files go to their site page" % (stats["github"], BRANCH, stats["readme"]))
