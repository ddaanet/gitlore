## Current task

D17 slice-1 (one-way index→frontmatter sync) is merged and green, so next is upgrading the claude shim to pass `--plugin-dir .` when appropriate — which is the prerequisite for dogfooding the sync against this repo's real `memory/MEMORY.md`, since the loaded plugin is the marketplace cache and lags the repo at the same version string — then release.

## Open decisions

- What predicate makes `--plugin-dir .` "appropriate" in the shim: only when cwd is the plugin's own repo (detect via `plugin.json` + a marketplace entry?), only under an opt-in env var/config key, or always-when-a-local-plugin-is-detected? Affects whether dogfooding is automatic here or an explicit gesture, and risks shadowing the installed plugin in unrelated repos.
- Whether the one-time semantic **reconcile** (healing pre-existing stale-index drift the one-way sync cannot fix) must land before the release, or ships after — D17 sequences it as sync → reconcile → structural recompose, and it must run after the sync is actually deployed or it re-drifts.
- Whether to fix the five orphaned bats files (21 passing tests unreferenced by the Makefile, including the D12/FR11 memory-gate suite) as part of release prep or as separate work — the gate currently has no regression cover.
