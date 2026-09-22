# 2026-09-20 — `lint` keeps a per-file shellcheck cache beneath its sentinel

Every gate hashes its whole input tree, so any edit anywhere in it sent `lint`
through all 203 discovered shell files, ~65 s. The sentinel answers "has
anything changed"; it cannot answer "which file", and that is the question a
one-file edit asks.

`scripts/lint-shell.sh` now records a key per file shellcheck passed, under
`git rev-parse --git-path gitlore/lint-cache`, and lints only the misses. An
unchanged tree costs ~4 s, which is the discovery walk itself; one edited suite
adds under a second. The `lint` sentinel still skips the recipe outright when
nothing moved, so the two layers compose rather than replace each other.

A key covers the shellcheck version, the file, and the closure of every
discovered file whose basename the file mentions. That is an over-approximation
of what `-x` actually reads, and deliberately so: shellcheck follows a `source`
only through a literal path or a `# shellcheck source=` directive, and both
spell the basename, so the closure cannot miss a followed source while it does
include files that merely name one. An edit to a library therefore relints
everything that reaches it. A file sourced from outside the discovered set is in
no key at all. The argument lives in `scripts/lint-cache-keys.py`, beside the
code that computes it.

Failures are never recorded, so a red file relints until it passes. A path the
index lists but the tree has lost is skipped rather than fatal.
`GITLORE_GATE_FORCE=1` lints everything regardless.
