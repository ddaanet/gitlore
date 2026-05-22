## Current task

Plan 03 shipped (commits `fc287c3`..`13966da`); write Plan 04 next per [[feedback-plan-late]].

## Open decisions

- **Plan 04 scope.** Three credible focuses, pick one:
  (a) **Marketplace install for gitlore** — makes the `memory-merger` sub-agent actually discoverable (Plan 03 §5.2 follow-up). Without this, the whole agent layer no-ops despite being correctly wired.
  (b) **`WorktreeCreate` / `WorktreeRemove` hooks** — original Plan 04 scope from the design doc; gives per-parent-worktree `worktree` branches in memory.
  (c) **Clone-from-remote smoke test + docs polish** — original Plan 05; defer until (a) or (b) lands.
  Recommendation: (a). Plan 03's agent layer is dormant until install is reachable, and the design doc treats install as a first-class concern.
- **Plan 02 leftover.** `ddaanet/gitmoji-gitlore-memory` GitHub repo still exists; current token lacks `delete_repo`. Clean up with `gh auth refresh -h github.com -s delete_repo && gh repo delete ddaanet/gitmoji-gitlore-memory --yes`. Orthogonal to Plan 04.
- **Memory submodule housekeeping in this repo.** `memory/` shows `modified: MEMORY.md` and untracked `feedback_spec_vs_code.md` from a prior session — not Plan 03 work. Investigate or leave; doesn't block Plan 04.
