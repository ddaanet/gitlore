## Current task

gitlore is preflight-passed and ready to release (main clean, 141 tests green, `make check-version` in sync at 0.1.1, readme refreshed in unpushed commit `418011e`) — the next release first adopts the `claude-plugin-dev` toolkit (vendored via `git subtree --prefix=plugin-dev`) to get a real `just release` recipe + git tags, then ships.

## Open decisions

- Integrate `claude-plugin-dev` before releasing: `git subtree add --prefix=plugin-dev git@github.com:ddaanet/claude-plugin-dev.git <vX.Y.Z tag> --squash`, add a gitlore `justfile` with a `precommit` recipe wrapping `make test` + `make check-version` (the toolkit's `release` recipe depends on `precommit`), then run `plugin-dev/install.sh` to wire the `import 'plugin-dev/release.just'` line + the `version-guard.sh` PreToolUse hook into `.claude/settings.json`. Pick which toolkit tag to pin.
- Bump level for the release: `0.2.0` (minor — recommended, ~26 commits of D11/Plan-07 rework + FR7 fix since `0.1.1`) vs `0.1.2` (patch). Run via `just release minor` once integrated.
- The toolkit's `release` recipe bumps `plugin.json` + tags but is unaware of the separate marketplace repo — so the `marketplace.json` bump (kept in sync via `scripts/check-version.sh`) + `/plugin marketplace update` cache-bust still need to happen alongside. Decide whether to extend the recipe/precommit or keep that step manual.
- Uncommitted: `memory/project_overview.md` has the release-ready/toolkit note in the working tree (memory submodule), not yet committed.
