## Current task

Execute Plan 06 (`docs/plans/2026-05-25-06-worktree-lifecycle.md`) — 4 TDD tasks: SessionStart linked-worktree memory-worktree creation, advisory `WorktreeRemove` hook + `hooks.json` registration, Makefile test registration, dogfood; git commands are pre-verified against git 2.47.3.

## Open decisions

- Execution mode for Plan 06: subagent-driven (fresh subagent per task, review between) vs inline (`executing-plans`, batch with checkpoints). User was asked but pivoted to handoff/commit; pick this up first on resume.
