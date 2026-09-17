# Item 2.1 / Slice 1 — GREEN report

Target: `gitlore_push_stores` in `scripts/lib/resolve.sh`. Implements the
post-loop publication pass; no test edited beyond what RED and the test
review left.

## Change

- Removed the behind arm's retry push (the `merge-base --is-ancestor live
  origin/live` block after its `GITLORE_TAKE_IN_PUSH=1 gitlore_merge_stores`
  call); the arm now just `continue`s after the take.
- Added a pass over `gitlore_tier_paths` after the tier loop and before the
  memory-remote check: skips a tier with no checkout or no local `live` (the
  loop's own guards), then pushes `live` to `origin` when it is not an
  ancestor of `origin/live` — including when `origin/live` has no local
  tracking ref at all, guarded the same way `gitlore_merge_one_store` guards
  its own possibly-missing `remote` (rev-parse into a variable, then
  `[ -z ... ] || ! merge-base --is-ancestor`, no stderr suppression). A failed
  push prints the existing "failed, and not because of divergence" wording
  and returns 1.
- Updated the two comments the removal and the new pass made stale: the
  `GITLORE_TAKE_IN_PUSH` rationale at the ahead-of-HEAD arm now notes the
  post-loop pass covers a repair landing on a different tier; the behind arm's
  comment on why the `live` has to go out now points at the same pass instead
  of describing its own removed retry.
- Left the "this push publishes it" message (`:1984`, printed when
  `GITLORE_TAKE_IN_PUSH` is set) untouched: it names the overall push
  invocation, not the immediate retry, so it stays true now that the
  post-loop pass is what actually publishes a mid-loop repair — and the two
  existing tests asserting its exact text (`:338`, `:376`, run below) confirm
  it.

## Test transitions

- `tests/push_behind_vs_diverged.bats`:16 "a repair the take makes to another
  tier mid-loop is published, not left for the next push (behind)": RED → GREEN.
- `tests/push_behind_vs_diverged.bats`:17 "… (ahead-of-HEAD)": RED → GREEN.

## Runs (`scripts/run-bats.sh <file>`, foreground, one at a time)

- `tests/push_behind_vs_diverged.bats`: 17 passed, 0 failed (the existing
  repair-publication cases at :338, :376, :404 pass unchanged).
- `tests/cc_hook_session_start.bats`: 25 passed, 0 failed.
- `tests/merge_commit_hygiene.bats`: 10 passed, 0 failed.
- `tests/plugin_distribution.bats`: 15 passed, 0 failed.
- `tests/merge_memory.bats`: 41 passed, 0 failed.
- `tests/push_memory.bats`: 12 passed, 0 failed.
- `tests/resolve_recovery.bats`: 23 passed, 0 failed.
- `tests/push_rejection_discriminator.bats`: 9 passed, 0 failed.
- `tests/write_settings.bats`: 7 passed, 0 failed.
- `shellcheck -x scripts/lib/resolve.sh tests/push_behind_vs_diverged.bats`: clean.

## Commit

`fix: Item 2.1/1 — a repair made mid-loop is published before memory's push`
