# 2026-09-22 — The changelog index splits at the layout boundary

The index in `docs/changelog.md` stood at 395 lines against the 400-line cap,
and the seven entries the v0.8.0 preflight found missing do not fit at any
wording: seven bare link lines land at 402. `check-docs-links.py`'s own
docstring settles the fork — split along a need-time seam rather than raise the
cap — so this is the rule applied, not a new one.

The seam is 2026-07-31, the entry that adopted the `docs/` + `plans/` layout and
created the index. Everything strictly older moves verbatim to
`docs/changelog-archive.md`, a sibling of the index with a header pointing back
at it. Entry bodies stay in `changelog/`, so a link from either index resolves
the same way. The index keeps 46 entries and the archive 59; nothing is dropped.
