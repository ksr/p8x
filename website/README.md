# website/ — the P8X project website

The project website is built from this repository's own documents with [MkDocs](https://www.mkdocs.org/) and the
[Material](https://squidfunk.github.io/mkdocs-material/) theme. The documents stay where they are; the site is
a readable view of them, with navigation and search.

| File | What |
|---|---|
| `home.md` | the visitor home page (the site's index) |
| `stage.py` | copies the documents the site uses into `stage/`, keeping their repository paths so the links between them work, and generates the extra pages |
| `hooks.py` | MkDocs hook: a link to a repository file that is not part of the site becomes a link to that file on GitHub (branch `main`) |
| `mkdocs.yml` | the site: navigation, theme, Markdown extensions |
| `mkdocs-publish.yml` | `mkdocs.yml` + the Google Analytics tag (G-X7P96DTCNE); only the published build carries it |
| `requirements.txt` | the Python packages, pinned |
| `build.sh` | stage + build (installs the packages into `venv/` on the first run, which needs the network) |

    website/build.sh            build into website/site/
    website/build.sh serve      ... and serve it at http://127.0.0.1:8766 (Ctrl-C stops it)
    website/build.sh publish    the build to publish (with Google Analytics)

`venv/`, `stage/` and `site/` are rebuilt each time and not committed. Previews leave the analytics tag out, so
looking at the site locally is not counted as a visit.

**Not published yet.** The plan: a GitHub Action builds `build.sh publish` on every push and deploys it to GitHub
Pages, at `https://p8x.cottageworker.com` (a CNAME record at the domain's DNS host, Gandi).
