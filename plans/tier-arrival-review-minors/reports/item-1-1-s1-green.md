# Item 1.1 / slice 1 — GREEN

**Test:** `an arrival the repair cannot fix beside a root duplicate reports both
and the two-fix remedy` (`tests/merge_memory.bats`).

## Implementation

`scripts/lib/resolve.sh`:
- `gitlore_adopt_tier_into_root`'s call into `gitlore_adopt_repair_arrival`
  gains `"$composed"` as a seventh argument.
- `gitlore_adopt_repair_arrival` takes `composed` as `$7`. In the unrepairable
  arm, after the `live:MEMORY.md:` loop, it filters `$composed` for lines not
  prefixed `"$tierpath/MEMORY.md: "` into `other_lines`. When non-empty, it
  prints the `gitlore: the root index could not take <label>'s lines:` header
  (same wording as `gitlore_adopt_report_refusal_and_walk_back`) followed by
  each line prefixed `gitlore:   `, and sets the remedy to the two-fix
  sentence. Otherwise the remedy is unchanged.

## Runs

- `scripts/run-bats.sh tests/merge_memory.bats --filter "beside a root
  duplicate reports both and the two-fix remedy"` — 1 passed, 0 failed.
- `scripts/run-bats.sh tests/merge_memory.bats` (whole file) — 36 passed, 0
  failed.
- Grep for other bats files exercising `could not be repaired` /
  `live:MEMORY.md:` output: only `tests/merge_memory.bats` matches.
- `shellcheck scripts/lib/resolve.sh tests/merge_memory.bats` — clean.

## Commit

One commit, subject `feat: Item 1.1/1 — unrepairable arm reports the root
index's problems`, carrying the test, the implementation and this report
trio. (A commit's own hash cannot be written into its own tree without
changing it; `git log -1 --format=%H -- scripts/lib/resolve.sh` on this
report's commit gives it.)

Tree clean afterward (verified with `git status --short`).
