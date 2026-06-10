## Current task

Write up D14 (user-facing output consolidated onto `systemMessage` — every SessionStart success path plus the branch-collision and divergence error paths) and D15 (in-process-worktree memory-drift guard) in docs/design.md and implement both with bats tests; D13 (git-lock retry wrapper) is complete and committed.

## Open decisions

- D15 hook matcher: targeted `matcher:"EnterWorktree|ExitWorktree"` vs `matcher:"*"` with a fast-bail. Decide after a 30-second fresh-session check of whether PostToolUse fires on EnterWorktree at all (wire a throwaway PostToolUse `matcher:"EnterWorktree"` that touches a file, enter a worktree, see if it appears). If it fires → targeted; if not → `"*"`. The drift predicate either way: `toplevel(cwd) != CLAUDE_PROJECT_DIR` with same git common-dir, emitted once per worktree as a systemMessage. No shim change required (CLAUDE_PROJECT_DIR stays frozen at launch while cwd moves).
