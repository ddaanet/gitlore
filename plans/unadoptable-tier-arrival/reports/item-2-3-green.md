# Item 2.3 GREEN

Commit: `3287a661250d96ed24ded12a5134a8e19db990a9` "✨ Item 2.3/1-4 — a repair
publishes the way its take does"

## What changed

`scripts/lib/resolve.sh`:

- `gitlore_merge_one_store`: reordered so the remote-url check, the fetch, and
  the `origin/live` read all come before `gitlore_adopt_advanced_live`. Each
  return that precedes the new ancestry test (no remote/placeholder URL, a
  failed fetch, a remote with no `live`) now calls the local adoption first,
  then prints and returns as before. After the remote is read, local `live` is
  read with `rev-parse -q --verify` and compared against it with
  `merge-base --is-ancestor`: the adoption runs unless that succeeds (a missing
  local `live` also runs it), in which case the existing remote fast-forward a
  few lines down takes origin's commits instead. `head` is now read after the
  adoption call. The comment above the (now conditional) adoption call is
  rewritten for the new order, present tense, no plan/item/
  decision-number-for-work-not-yet-done citations.
- `gitlore_push_stores`, `behind` arm of the tier push case: after
  `gitlore_merge_stores "$mempath" || return 1`, added a check —
  `gitlore_classify_refusal "$tierpath" live origin/live` (reused; "ahead" only
  fires on strict ancestry since equal refs classify as "behind") — that retries
  `gitlore_git -C "$tierpath" push -q origin live` when the tier's `live` came
  out of the take strictly ahead of `origin/live`. A refusal prints the same
  message as the outer `*)` fallback arm below and returns 1; otherwise falls
  through to `continue` as before.

## Test order

1. `tests/push_behind_vs_diverged.bats` — "a repair taken by the behind arm is
   published before memory records it" (slice 2): red before, green after.
2. `tests/merge_memory.bats` — "a take fetches first and takes a repair another
   consumer published" (slice 3): red before, green after.
3. Confirmed slice 1 ("a repair taken inside a push is published before memory
   records it") and slice 4 ("a failed fetch still adopts local live and reports
   the fetch failure") still pass individually.

## Suite results

All run via `scripts/run-bats.sh <file>` under `GITLORE_GIT_RETRY_SCHEDULE=0`,
one file at a time, foreground:

- `tests/push_behind_vs_diverged.bats` — 14 passed, 0 failed
- `tests/merge_memory.bats` — 33 passed, 0 failed
- `tests/tier_divergence.bats` — 19 passed, 0 failed
- `tests/resolve_compose.bats` — 9 passed, 0 failed
- `tests/commit_memory.bats` — 35 passed, 0 failed
- `tests/push_memory.bats` — 12 passed, 0 failed (grep-found caller of
  `gitlore_merge_one_store`/`gitlore_push_stores`)
- `tests/push_rejection_discriminator.bats` — 9 passed, 0 failed (grep-found
  caller of `gitlore_push_stores`)

`shellcheck` clean on `scripts/lib/resolve.sh`, `tests/merge_memory.bats`, and
`tests/push_behind_vs_diverged.bats`.

`git status --porcelain` after commit shows only the pre-existing unrelated
handoff-file edits and the plan/report scratch files outside this item's scope;
`scripts/lib/resolve.sh` and both `.bats` files are clean (committed).
