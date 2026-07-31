# 2026-05-25 — Implemented D11

All five hook managers (direct, husky, lefthook, overcommit, manual) and `emit-wrappers` now anchor the wrapper at `$(git rev-parse --git-common-dir)/gitlore-<hook>`; direct wiring resolves the hook file via `--git-path hooks/<hook>`. `pre-commit`/`pre-push` early-exit in session-less worktrees (`[ -e "$mempath/.git" ]`). SessionStart lazily creates the memory submodule worktree; new advisory `WorktreeRemove` hook removes it (registered matcher-less — the event has no matcher support). Overcommit's `sh -c` array `$@`-forwarding verified by test.
