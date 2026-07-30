## Current task

The `/gitlore:merge` then `/gitlore:push` dogfood on this repo is done: the shared `ddaanet` tier merged to `3fba29f`, and that is what its remote holds. Two threads remain open on top of it.

An uncommitted consolidation sits inside the tier worktree — two memory-writing facts folded into one, `feedback_memory_index_lines_functional` and `feedback_memory_not_other_owners_job` deleted, `feedback_memory_writing` and `feedback_index_compaction_triggers` rewritten. It is a content decision on shared memory, so it was left rather than landed.

Separately, `claude-plugin-dev` mounted the same tier and hit two gitlore defects, written up in `brief-hook-exec-and-compose-revert.md` at this repo root: the hook installer appends its managed line after an existing `exec`, silently disabling memory sync; and index composition reverted an incoming tier merge by mirroring stale root wording down over upstream's compacted lines. Both were reproduced and diagnosed there, not fixed here.

## Open decisions

- Four calls made beyond the plan's text, all implemented and tested, none confirmed by David: the down projection is skipped when root holds no line for an active tier and the layout adopts that carrier instead (so emptying a tier's block does not drop the tier — deactivation is the way); a memory-store merge runs a layout-only up pass rather than no pass at all; the non-diverged fast-forward in `/gitlore:merge` adopts without a merge sub-agent; and the no-publish intent rides the state file as `publish: no` rather than a new merge flavor or a marker file.
- `memory/MEMORY.md` is 21.7KB against a 17.1KB soft target and a 24.4KB loader cutoff. Compact it, raise the target, or leave it.
- Whether to carry out the `docs/plans/` to root `plans/` migration.
- Where the six `brief-*.md` files at the repo root belong.