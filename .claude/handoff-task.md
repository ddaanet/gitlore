## Current task

Execute Plan 07 (`docs/plans/2026-05-25-07-gitlink-aware-wrappers.md`) subagent-driven on `main` — 10 TDD tasks implementing D11 gitlink-aware wrappers + absorbed Plan 06 deliverables; nothing dispatched yet.

## Open decisions

- `hooks/hooks.json` Task 9 registers `WorktreeRemove` with `matcher: "*"` mirroring `SessionStart`; unverified whether `WorktreeRemove` honors a matcher field — confirm against CC, drop the matcher if it rejects one.
- Task 10 assumes `tests/plugin_distribution.bats` tolerates the new `WorktreeRemove` hook key; if it asserts an exact event set, update that assertion.
