## Current task

Plan 05 (Memory Redirect Launcher / D10) is fully drafted and reviewed at `docs/plans/2026-05-24-05-memory-redirect-launcher.md`; the next action is to execute it task-by-task (TDD, 9 steps: canonical shim → Placement A direnv → wire-in + dead-write removal → SessionStart guard → Placement B global shim + command → Makefile → docs → self-dogfood).

## Open decisions

- Execution mode for Plan 05: subagent-driven (fresh subagent per task, review between tasks — recommended) vs inline in this session. Was asked twice and deferred both times; pick one to start.
- Plan 05 Step 9 dogfood must run under `--plugin-dir` (not the marketplace cache) per the stale-cache lesson; a `/plugin install` + `/reload-plugins` happened this session, so confirm which gitlore source is loaded before trusting the dogfood.
