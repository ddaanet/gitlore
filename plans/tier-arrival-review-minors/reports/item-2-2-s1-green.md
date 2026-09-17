# Item 2.2 / slice 1 — GREEN

## Test transition

`tests/push_behind_vs_diverged.bats`, "a post-loop publication push refused as
a non-fast-forward is worded as a moved remote, not as a non-divergence
failure": red on the positive wording assertion (`The remote moved during the
push`) against unchanged code; green after wiring the new helper into the
post-loop pass. No test edited.

## Change

Added `gitlore_report_tier_push_failure <tier> <git_stderr>` in
`scripts/lib/resolve.sh`, placed after `gitlore_push_stores`. It classifies
`git_stderr` by the same `(fetch first)`/`(non-fast-forward)` discriminator the
callers already used, and prints one of the two existing wordings to stderr
via `gitlore_say_for_agent_or_user`.

Four callers rewired to call it instead of duplicating the `gitlore_say_for_agent_or_user`
pair:
- the behind arm's retry push (after `GITLORE_TAKE_IN_PUSH=1 gitlore_merge_stores`,
  checking `merge-base --is-ancestor live origin/live`);
- the inner `*)` arm under `gitlore_classify_refusal` (the non-fast-forward-while-live-contains-remote
  case) — its call always lands on the helper's divergence branch, reproducing
  the same wording;
- the outer `*)` arm of the tier push `case` (non-divergence-shaped stderr) —
  its call always lands on the helper's non-divergence branch;
- the post-loop pass added in Item 2.1 — previously unconditional
  "not because of divergence", now classified. This is the caller whose fix
  turns the new test green.

The `behind` and `diverged` classify arms are untouched; they still branch on
their own before ever reaching a push-failure wording.

## Bats counts per file

All run foreground, one file at a time, via `scripts/run-bats.sh <file>`:

- `tests/push_behind_vs_diverged.bats`: 19 passed, 0 failed.
- `tests/merge_commit_hygiene.bats`: 10 passed, 0 failed.
- `tests/plugin_distribution.bats`: 15 passed, 0 failed.
- `tests/push_rejection_discriminator.bats`: 9 passed, 0 failed.
- `tests/cc_hook_session_start.bats`: 25 passed, 0 failed.
- `tests/tier_divergence.bats`: 20 passed, 0 failed.
- `tests/write_settings.bats`: 7 passed, 0 failed.
- `tests/push_memory.bats`: 12 passed, 0 failed.
- `tests/merge_memory.bats`: 41 passed, 0 failed.
- `tests/resolve_compose.bats`: 23 passed, 0 failed.
- `tests/resolve_recovery.bats`: 23 passed, 0 failed.

## shellcheck

`shellcheck -x scripts/lib/resolve.sh tests/push_behind_vs_diverged.bats`:
clean.
