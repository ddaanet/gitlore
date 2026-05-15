---
name: gitlore-install
description: Install gitlore memory submodule and wire git hooks (local-only)
---

This skill orchestrates the gitlore local install. See `commands/gitlore/install.md`
for the agent-facing flow. Internals: `scripts/install/run.sh`.

Key invariants:
- Memory submodule is registered as `gitlore-memory` regardless of working-tree path.
- Trunk branch is `live`. Worktree branch is named after the parent branch (or detached HEAD).
- Settings under `.claude/settings.json` are tracked; `.claude/settings.local.json` is gitignored.
- Hook wrappers live at `.git/gitlore-pre-{commit,push}` and are regenerated each SessionStart.
