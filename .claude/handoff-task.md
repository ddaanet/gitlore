## Current task

Nothing in progress — the FR7 clone-restore bug is fixed, tested (136/136), and committed on local `main` (root + memory submodule), unpushed.

## Open decisions

- Push the unpushed commits to `origin/main` (root ~19 ahead, memory submodule 1+ ahead — push memory first so the gitlink resolves), or pick up a deferred item next. Deferred, all nice-to-have: version-sync CI (`plugin.json`↔`marketplace.json`), Plan-02 leftover `ddaanet/gitmoji-gitlore-memory` cleanup, locked-worktree `WorktreeRemove` test.
