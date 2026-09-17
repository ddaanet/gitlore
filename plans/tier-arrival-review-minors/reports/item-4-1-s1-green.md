# Item 4.1 / Slice 1 — GREEN report

## Change

`scripts/resolve.sh`, the `continue-after-merge` commit arm: the `||` handler
on `gitlore_git -C "$mempath" commit -q -F "$merge_msgfile"` now prints

```
gitlore: the merge commit was refused, so the merge was not committed; the merge stays prepared.
```

to stderr before removing the message file and exiting 1. Git's own refusal
(the hook's `commit refused by hook` text) already reached stderr as part of
the failing `commit` invocation, so the new line naturally follows it —
satisfies the required ordering without extra bookkeeping. Wording matches
the runbook (`plans/tier-arrival-review-minors/runbook.md:322`) and outline
(`:190`) byte-for-byte. Idiom matches the file's existing `echo "gitlore: …" >&2`
style; the script has no say-helper.

## Test transition

`tests/resolve_compose.bats`: "a refused merge commit leaves no message file
behind and keeps the merge for a rerun" — RED (missing gitlore line) to GREEN.

Filtered run: `bats: 1 passed, 0 failed`.

## Bats counts per file

| File | Result |
|---|---|
| tests/resolve_compose.bats | 23 passed, 0 failed |
| tests/commit_memory.bats | 35 passed, 0 failed |
| tests/global_shim.bats | 5 passed, 0 failed |
| tests/git_hook_pre_commit.bats | 20 passed, 0 failed |
| tests/plugin_distribution.bats | 15 passed, 0 failed |
| tests/push_rejection_discriminator.bats | 9 passed, 0 failed |
| tests/resolve_both_flavors.bats | 4 passed, 0 failed |
| tests/merge_memory.bats | 41 passed, 0 failed |
| tests/resolve_merge_briefing.bats | 8 passed, 0 failed |
| tests/pre_push_hook.bats | 9 passed, 0 failed |
| tests/resolve.bats | 8 passed, 0 failed |
| tests/resolve_merge_local.bats | 4 passed, 0 failed |
| tests/resolve_merge_remote.bats | 3 passed, 0 failed |
| tests/tier_divergence.bats | 20 passed, 0 failed |
| tests/resolve_recovery.bats | 23 passed, 0 failed |

All runs used `GITLORE_GIT_RETRY_SCHEDULE=0`, one file at a time, in the
foreground.

## Shellcheck

`shellcheck -x scripts/resolve.sh tests/resolve_compose.bats`: clean.

## Where the line is emitted

`scripts/resolve.sh`, inside the `continue-after-merge` subcommand's commit
step: the `||` block on the `gitlore_git … commit` call, ahead of the existing
`rm -f "$merge_msgfile"; exit 1`.
