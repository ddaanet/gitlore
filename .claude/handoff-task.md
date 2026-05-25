## Current task

Write the superseding implementation plan (D11 gitlink-aware wrappers across all five hook managers + Plan 06's absorbed SessionStart memory-worktree creation and advisory `WorktreeRemove`) via the writing-plans skill, then execute it subagent-driven on `main`.

## Open decisions

- The overcommit wiring uses `command: ['sh','-c','exec "$(git rev-parse --git-common-dir)/gitlore-pre-commit" "$@"','gitlore']` — overcommit's exact file-arg appending into `$@` is unverified; the plan must include a real verification test for this form before trusting it.
- The implementer's aborted Task-1 edits to `scripts/cc-hooks/session-start.sh` (memory-init block) and `tests/cc_hook_session_start.bats` are still uncommitted in the working tree (kept, not reverted, since they match the approved design) — the new plan should fold them in rather than rewrite from scratch.
