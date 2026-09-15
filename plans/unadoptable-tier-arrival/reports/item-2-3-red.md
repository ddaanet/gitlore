# Item 2.3 RED report

Tests written, uncommitted, no SUT changes (scripts/ verified clean via
`git status --porcelain`). shellcheck clean on both edited files and on
`scripts/lib/resolve.sh`.

## Slice 1 — guard

`tests/push_behind_vs_diverged.bats:339` — "a repair taken inside a push is
published before memory records it"

- Run alone: `bats: 1 passed, 0 failed`. Holds on the current code, as the
  runbook states (item 2.2's repair-before-push ordering already exists).
- Not vacuous. Mutation: in `gitlore_push_stores` (`scripts/lib/resolve.sh`),
  removed the
  `if gitlore_live_ahead_of_head "$tierpath"; then gitlore_merge_stores "$mempath" || return 1; fi`
  guard ahead of `gitlore_check_head_live_agree`, so a tier whose local `live`
  ran ahead is never repaired/adopted before the push loop's HEAD-vs-live gate.
  Red output:
  ```
  not ok 1 a repair taken inside a push is published before memory records it
  # (in test file tests/push_behind_vs_diverged.bats, line 361)
  #   `[ "$status" -eq 0 ]' failed
  ```
  Restored `scripts/lib/resolve.sh` from a saved copy under
  `/tmp/claude-1000/item23-mut/resolve.sh.orig`; `cmp` against the saved
  original confirmed byte-identical, and `git status --porcelain` on the file is
  clean.
- The pre-receive hook installed on `$MEMORY_REMOTE` (helper
  `install_tier_live_snapshot_hook`) is asserted to have run:
  `[ -s "$hookfile" ]` before the file's content is read.

## Slice 2 — red

`tests/push_behind_vs_diverged.bats:369` — "a repair taken by the behind arm is
published before memory records it"

- Run alone and as part of the full file: fails on
  `[ "$(cat "$hookfile")" = "$R" ]` (`tests/push_behind_vs_diverged.bats:388`).
  ```
  not ok 1 a repair taken by the behind arm is published before memory records it
  # (in test file tests/push_behind_vs_diverged.bats, line 388)
  #   `[ "$(cat "$hookfile")" = "$R" ]' failed
  ```
  Cause matches the runbook's premise: the current `behind` arm calls
  `gitlore_merge_stores` (which repairs and adopts R into the tier's local
  `live`) and then `continue`s with no retry push, so R never reaches the tier's
  own remote before memory's push records the gitlink — the hook's snapshot of
  the tier remote's `live` (read during memory's push) still shows the
  unrepaired arrival, not R.
- The hook's file existence is asserted (`[ -s "$hookfile" ]`) before this
  content check.
- Full-file run (`scripts/run-bats.sh tests/push_behind_vs_diverged.bats`): 13
  passed, this one failed — no other test regressed.

## Slice 3 — red

`tests/merge_memory.bats:855` — "a take fetches first and takes a repair another
consumer published"

- Run alone and as part of the full file: fails on `[ "$status" -eq 0 ]`
  (`tests/merge_memory.bats:894`, originally reported at line 893 before a debug
  line used during diagnosis was removed).
  ```
  not ok 1 a take fetches first and takes a repair another consumer published
  # (in test file tests/merge_memory.bats, line 893)
  #   `[ "$status" -eq 0 ]' failed
  ```
  Confirmed the failure is a genuine assertion against real behavior (not a
  setup error) with a temporary debug print (`echo "DEBUG status=... " >&3`,
  removed afterward, `git diff` shows only the final clean test body): the run
  exits 1 with `gitlore: memory merge prepared (flavor=head-vs-remote)`. On the
  pre-job order, `gitlore_adopt_advanced_live` runs before the fetch, so it
  repairs the stale local copy of the arrival (still carrying the duplicate)
  into its own repair commit before the fetch ever sees the upstream fix; that
  repair and the upstream fix are then siblings on the same arrival, so the
  ancestry test finds neither an ancestor of the other and prepares a merge
  instead of taking the upstream fix by fast-forward.
- Full-file run (`scripts/run-bats.sh tests/merge_memory.bats`): 32 passed, this
  one failed — no other test regressed.

## Slice 4 — holds on pre-job code

`tests/merge_memory.bats:906` — "a failed fetch still adopts local live and
reports the fetch failure"

- Run alone: `bats: 1 passed, 0 failed`. Holds on the current code, as the
  runbook states.
- Not vacuous. Mutation: in `gitlore_merge_one_store`
  (`scripts/lib/resolve.sh`), moved the remote-URL check and the fetch (with its
  failure return) to run *before* `gitlore_adopt_advanced_live`, so a failed
  fetch returns before the local adoption/repair ever runs. Red output:
  ```
  not ok 1 a failed fetch still adopts local live and reports the fetch failure
  # (in test file tests/merge_memory.bats, line 922)
  #   `[ "$(git -C memory/ddaanet rev-parse HEAD)" = "$live_sha" ]' failed
  ```
  Restored `scripts/lib/resolve.sh` from the same saved copy; `cmp` confirmed
  byte-identical, `git status --porcelain` on the file is clean.

## Post-mutation sanity

After both mutations were reverted, re-ran all four new tests together (two per
file) and the full files once more; results matched the table above exactly —
slices 1 and 4 green, slices 2 and 3 red, nothing else regressed. `shellcheck`
on both `.bats` files and on `scripts/lib/resolve.sh` is clean.
