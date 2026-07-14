## Current task

D17 tiered-memory slice 1 (one-way index→frontmatter sync) is designed in `docs/design.md` and fully planned at `docs/superpowers/plans/2026-07-15-index-frontmatter-sync.md` (4 TDD tasks: lib helpers → PreToolUse stash → PostToolUse diff-and-propagate → wire hooks.json + e2e); next is executing the plan task-by-task.

## Open decisions

- Execution mode for the plan: subagent-driven (fresh agent per task, review between tasks — recommended by writing-plans) vs. inline batch execution in one session.
