# Item 2.1 / Slice 2 — GREEN

Restored the behind arm's retry push in `gitlore_push_stores`
(`scripts/lib/resolve.sh`): after `GITLORE_TAKE_IN_PUSH=1 gitlore_merge_stores`,
when `live` is not an ancestor of `origin/live`, push `live` to `origin`, and on
failure print the existing "failed, and not because of divergence" message and
return 1 — exactly the block slice 1 removed. Its comment now states, present
tense, that the push goes out both for the D17 lockstep and to be out before a
later tier's failure returns 1 from the loop, and that a repair the same take
made to a *different* tier is left to the post-loop pass.

The post-loop pass's own comment gained one clause: the loop above's own pushes
already moved each tier's `origin/live`, so a tier already out is not pushed
again there. The pass's comment otherwise still names only the cross-tier case —
the behind arm's own-tier repair is now the retry's job again, not the pass's.

In `tests/push_behind_vs_diverged.bats`, `setup_repair_race_on_aa`'s comment no
longer cites `:376`; it names the test "a repair taken by the behind arm is
published before memory records it" instead.

## Test transitions

`tests/push_behind_vs_diverged.bats`, "a behind arm's repair survives a later
tier's failure": red (per `item-2-1-s2-red.md`) → green.

## Bats counts

| File | Result |
|---|---|
| `tests/push_behind_vs_diverged.bats` | 18 passed, 0 failed |
| `tests/merge_commit_hygiene.bats` | 10 passed, 0 failed |
| `tests/plugin_distribution.bats` | 15 passed, 0 failed |
| `tests/push_rejection_discriminator.bats` | 9 passed, 0 failed |
| `tests/write_settings.bats` | 7 passed, 0 failed |
| `tests/cc_hook_session_start.bats` | 25 passed, 0 failed |
| `tests/merge_memory.bats` | 41 passed, 0 failed |
| `tests/resolve_recovery.bats` | 23 passed, 0 failed |
| `tests/push_memory.bats` | 12 passed, 0 failed |

## Shellcheck

`shellcheck -x scripts/lib/resolve.sh tests/push_behind_vs_diverged.bats`:
clean.
