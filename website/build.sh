#!/bin/sh
# Author: Claude (Anthropic) for Ken Rother, 2026
# build.sh - build the P8X project website (MkDocs + Material) from this repository's documents, and optionally
#            serve it.
#   ./build.sh          stage the docs, build into site/
#   ./build.sh serve    ... then serve it at http://127.0.0.1:8766 (Ctrl-C stops it)
#   ./build.sh publish  build for publishing: mkdocs-publish.yml = mkdocs.yml + the Google Analytics tag (G-X7P96DTCNE);
#                       previews leave the tag out, so looking at the site locally is not counted as a visit
# venv/, stage/ and site/ are rebuilt each time and not committed (website/.gitignore).
set -e
cd "$(dirname "$0")"
[ -x venv/bin/mkdocs ] || python3 -m venv venv
venv/bin/pip install -q -r requirements.txt   # quick when already installed
venv/bin/python stage.py
CONF=mkdocs.yml; [ "$1" = "publish" ] && CONF=mkdocs-publish.yml
venv/bin/mkdocs build -f "$CONF" 2>&1 | grep -E "WARNING|ERROR|hooks:|Documentation built" || true
[ "$1" = "publish" ] && echo "built with $CONF (Google Analytics on)"
[ "$1" = "serve" ] && cd site && exec python3 -m http.server 8766 --bind 127.0.0.1
