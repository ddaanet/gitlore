## Open decisions

- `brief-orphaned-merge-head-no-state-file.md` (untracked, repo root): whether to write the merge-state file *before* `gitlore_prepare_merge` and upgrade it on success, which would make `orphaned-merge-head` (MERGE_HEAD, no state file) unreachable and fold it into the landed/staged/dead classifier `gitlore_recover_stale_no_merge_head` already runs; and separately whether `gitlore_prepare_merge` should read `pending` from `live` rather than HEAD. The brief's line 94 reasons about `abort-then-retry`, which no longer exists — a prepared merge is always continued.
- `brief-commit-memory-missing-skill.md` and `brief-resolve-noisy-noop-failure.md` (untracked, repo root): not yet read or triaged.

## Remaining

- Make `check_orphans` resolve sibling-relative links (see the task file).
- File the applied briefs under `plans/`: `brief-claude-p-resets-uncommitted-memory.md` is fully applied (symptom 1 was already fixed in 0.4.5; symptoms 2 and 3 landed 2026-08-26/27).
- `memory/MEMORY.md` is at 26.3KB against Claude Code's 24.4KB loader cutoff, so tail entries are silently dropped every session and the index hook flags every write. Fix by retiring and merging entries, never by shortening lines to hit the number.
