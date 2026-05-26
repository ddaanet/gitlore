## Current task

The `claude-plugin-dev` toolkit is fully integrated and committed; the only remaining step is to ship 0.2.0 by running `env MARKETPLACE_DIR=$PWD/../claude-plugins just release minor --yes && git -C memory push` (the user must run it via `!` — subtree/cross-repo/settings ops are auto-mode-denied), then `/plugin marketplace update` to bust the local cache.

## Open decisions

- None outstanding: bump = minor (0.2.0), toolkit pinned at v0.2.0, marketplace bump is handled by the recipe. If the release errors mid-way, the likely culprit is the marketplace cross-repo push needing `!`/`--add-dir` authorization — the gitlore tag + gh release may already be live, so before re-running check `git tag` (a stray `v0.2.0` tag or a plugin.json already at 0.2.0 means resume from the marketplace step, not a fresh `just release`).
