# Item 4.1/2 — GREEN

## Test transition

`tests/resolve_compose.bats`, "a message build failure leaves no message file
behind and keeps the merge prepared": red (`not ok 14`, wording assertion) to
green. `scripts/run-bats.sh tests/resolve_compose.bats`: 24 passed, 0 failed.

## Changes in `scripts/resolve.sh`

1. The message-build arm (`gitlore_merge_commit_message … > "$merge_msgfile"
   || { … }`) now removes the message file first, then emits
   `gitlore: the merge message could not be built, so the merge was not
   committed; the merge stays prepared.` to stderr, then `exit 1` — matching
   slice 1's refused-commit arm shape.
2. Folded the two arms' comments into one, placed above both `||` groups
   (before the `gitlore_merge_commit_message` call): it now states that either
   arm keeps `MERGE_HEAD` and the merge state for a rerun, and that removal
   comes first in each group because errexit stays armed on the right-hand
   side of `||`. The refused-commit arm's inline comment (slice 1) is gone —
   folded rather than duplicated, since the reasoning is identical for both
   arms.
3. The `compose_merged_indexes` comment rider (docstring above the function,
   the "Returns 0 otherwise" sentence) now states that a failed staging
   command aborts under errexit with git's own text on stderr and no
   `gitlore:` line, since wrapping the command would suspend errexit around
   it.

## Bats counts

| File | Result |
|---|---|
| `tests/resolve_compose.bats` | 24 passed, 0 failed |
| `tests/git_hook_pre_commit.bats` | 20 passed, 0 failed |
| `tests/resolve_merge_local.bats` | 4 passed, 0 failed |
| `tests/resolve_recovery.bats` | 23 passed, 0 failed |
| `tests/pre_push_hook.bats` | 9 passed, 0 failed |
| `tests/resolve.bats` | 8 passed, 0 failed |
| `tests/resolve_merge_briefing.bats` | 8 passed, 0 failed |
| `tests/resolve_merge_remote.bats` | 3 passed, 0 failed |
| `tests/tier_divergence.bats` | 20 passed, 0 failed |

## shellcheck

`shellcheck -x scripts/resolve.sh tests/resolve_compose.bats`: clean.

## Comment folding

Slice 1's comment was folded to cover both arms rather than duplicated: one
comment now sits above the message-build call and explains the shared errexit
reasoning for both `||` groups below it; the per-arm comment slice 1 added is
removed.
