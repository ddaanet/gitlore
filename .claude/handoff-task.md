## Current task

Execute Plan 03 via `superpowers:subagent-driven-development` on `docs/plans/2026-05-21-03-semantic-merge-resolve.md` — 7 tasks, outside-in TDD per task, dogfood gate at Task 7.

## Open decisions

- **Execution mode.** User deferred between subagent-driven (recommended; isolates per-task context) vs inline (faster, single session). Pick before starting; revisit if Task 1's scaffolding ends up larger than expected.
- **Task 1 step 10 loop test.** The plan calls out that simulating a concurrent live-advance during synthesis is hard to set up cleanly in bats. Refine the fixture during execution or accept the loop test as a hand-validated checkpoint.
- **Leftover GitHub repo from Plan 02 dogfood.** `ddaanet/gitmoji-gitlore-memory` still exists; token lacks `delete_repo` scope. To clean up: `gh auth refresh -h github.com -s delete_repo && gh repo delete ddaanet/gitmoji-gitlore-memory --yes`. Orthogonal to Plan 03 but unfinished.
- **CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS at dogfood (Task 7).** Required for real `Task` + `SendMessage` dispatch. Plan 03 Tasks 1-4 don't need it (stub-synth bypasses the agent layer), but Task 7 does. Confirm set in the shell before invoking dogfood.
