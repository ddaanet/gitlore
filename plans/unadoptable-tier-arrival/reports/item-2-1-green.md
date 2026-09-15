# Item 2.1 — GREEN report

Commit: `b0e19de` —
`feat: Item 2.1/1-8 — gitlore_repair_index splits welds, moves stray lines and drops duplicates`

## Implementation

`scripts/lib/index-compose.sh`:

- Refactored `gitlore_welded_path` to factor its tail-scan into a new shared
  helper `gitlore_weld_tail`, which prints the *substring* starting at the
  welded second bullet (rather than just its path). `gitlore_welded_path` now
  calls it and reduces the result to a path with `gitlore_bullet_path`. This is
  what lets `gitlore_repair_index` split a line at exactly the shape
  `gitlore_welded_path` reports (E1), from one source of truth, instead of
  re-scanning the line differently.
- Added the required sentence to `gitlore_compose_check_index`'s comment: a rule
  added there gains a matching repair rule in `gitlore_repair_index` in the same
  change.
- Replaced the inert `gitlore_repair_index` stub with the real implementation:
  three in-memory passes over a bash array of lines (welds, then interleaved
  non-bullet lines, then duplicates, per K3's order), each pass appending its
  own report lines to a single accumulator. Weld existence is checked with
  `[ -f "$tierdir/$path" ]`; the pointer-block boundary for the second and third
  passes is recomputed each time via `gitlore_index_region` fed through process
  substitution over the in-progress array, so the repair and the check agree on
  where the bullet region and trailer start. Duplicate resolution groups bullets
  by path and picks the survivor per K3's rule (first line the pin lacks when
  the group mixes known/lacked; otherwise the first line), using `grep -qxF`
  against a newline-delimited "seen"/pin-lines string for exact whole-line
  matching (no associative arrays, no regex built from a path). `report`
  non-empty is the sole "was anything edited" signal — every edit type prints a
  line, so an empty report is a correctness guarantee that nothing changed,
  letting the untouched-file case (slice 1) skip ever touching disk. Only when
  `report` is non-empty does the function `mktemp` a scratch file beside
  `<file>` (never under `$TMPDIR`), write the final content there — respecting
  `<file>`'s original final-newline state — `mv` it over `<file>`, and only
  after that succeeds print the report.

## Tests made green, in order

1. "repairing a clean index changes nothing"
2. "an identical duplicate is dropped"
3. "a welded line is split before the second bullet"
4. "a three-bullet weld splits twice"
5. "a weld naming no file in the tier is left unchanged"
6. "a link the check does not report as a weld is left unchanged"
7. "an interleaved non-bullet line moves to the start of the trailer"
8. "a differing duplicate keeps the line the pin lacks"
9. "a differing duplicate: of several lines the pin lacks, the first survives"
10. "a differing duplicate: new to both keeps the first"
11. "a differing duplicate: known to both keeps the first"
12. "a differing duplicate: a pin with no carrier keeps the first"
13. "welds are split before duplicates are resolved"
14. "a rewrite that cannot be written leaves the file unchanged"

Each was run individually with
`scripts/run-bats.sh tests/index_compose.bats --filter <name>` against the final
implementation (written whole, not grown incrementally line-by-line, given the
interlocking nature of the three passes) and passed on the first run with no
further edits needed.

## Final suite line

`scripts/run-bats.sh tests/index_compose.bats` (no filter):
`bats: 80 passed, 0 failed`

## Lint

`shellcheck scripts/lib/index-compose.sh tests/index_compose.bats` — clean, no
output.

No precommit warnings to report (per dispatch constraints, `just precommit` was
not run — the orchestrator owns that gate at phase boundaries).
