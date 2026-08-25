# 2026-06-10 — Documented D13 — lock-contention retry wrapper (`gitlore_git`)

Shipped in `27042ce`: `scripts/lib/util.sh` gains `gitlore_git` (retry mutating
`git` on transient lock contention, 10s exponential backoff,
`GITLORE_GIT_RETRY_SCHEDULE`-overridable) and `gitlore_git_is_lock_error`
(matches `index.lock`/`cannot lock ref`/… but fast-fails D3's
`is already used by worktree at` write-lock). Threaded through SessionStart,
`pre-commit`, `pre-push`, `resolve.sh`, and the install scripts on mutating
calls only. Tests: `lib_util.bats` (+lock-classifier and retry cases).
