# website/ — the P8X project website

The project website is built from this repository's own documents with [MkDocs](https://www.mkdocs.org/) and the
[Material](https://squidfunk.github.io/mkdocs-material/) theme. The documents stay where they are; the site is
a readable view of them, with navigation and search.

| File | What |
|---|---|
| `home.md` | the visitor home page (the site's index) |
| `p8x-collage.jpg` | the home page's lead picture: the assembled-machine renders and the memory card (until there are photos of built boards) |
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

**Publishing.** `.github/workflows/website.yml` runs on every push to `main` (or by hand: Actions -> website -> Run
workflow): it builds `website/build.sh publish` on GitHub's machine, so every push proves the site builds. It deploys
to GitHub Pages only when the repository variable `PAGES_DEPLOY` is `true` (Settings -> Secrets and variables ->
Actions -> Variables) and Pages is on (Settings -> Pages -> Source: GitHub Actions); until then nothing is published.
The address will be `https://p8x.cottageworker.com` (a CNAME record at the domain's DNS host, Gandi, and the custom domain in
Settings -> Pages); `site_url` in `mkdocs-publish.yml` already names it.
