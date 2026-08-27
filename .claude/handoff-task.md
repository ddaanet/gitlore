## Current task

The docs-checker follow-up: `check_orphans` in `scripts/check-docs-links.py` matches the literal `references/<basename>.md`, so a node linked only by a sibling-relative link (`[x.md](x.md)`, the form nodes use among themselves) reads as an orphan — the three evals nodes clear the warning today only because the 2026-08-25 changelog entry names them by full path.
