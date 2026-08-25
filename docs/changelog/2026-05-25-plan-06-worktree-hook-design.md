# 2026-05-25

Plan 06 design: verified worktree-hook I/O against CC 2.1.150. `WorktreeCreate`
is an override hook (fires pre-creation, must emit only the worktree path on
stdout, no branch in stdin) — **not used**; memory-worktree setup happens at
`SessionStart` in the new worktree instead (covers `claude --worktree`, manual
`git worktree add`, and the Desktop button uniformly). `WorktreeRemove`
(advisory, `worktree_path`-only) removes the memory submodule worktree; branch
retention confirmed a no-op (CC keeps the parent branch on removal). Corrected
the prior wrong assumption that command hooks receive
`worktree_path`/`worktree_branch` on stdin.
