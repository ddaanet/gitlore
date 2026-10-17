## Open decisions

- Six inbox briefs under `inbox/` (https-submodule-urls, launcher-memory-path-containment, launcher-shim-second-sighting, memory-gate-owner-inventory-and-existence, orphan-report-fix-recipe, write-https-urls): triage which to take.
- `just resume-release` is not in `sandbox.excludedCommands` (unlike `just release *`), so it reached github.com only with `dangerouslyDisableSandbox`. Decide whether to add a `just resume-release` exclusion.

## Remaining

- `MEMORY.md` is at 97% of its 25600-byte budget (loader truncates past 24.4KB): run `/gitlore:index-audit`.
- `memory/ddaanet/simplicity-no-unneeded-code.md` links `[[removing-cleanly]]`, which matches no memory file; likely meant the `craft:removing-cleanly` skill.
- `tests/install_remote.bats` sets `GITLORE_HOME` for only one test; call `isolate_home` (`tests/helpers/setup.bash`) in its `setup`.
- Delete each `gitlore/archive/2026-10-15` branch (tier and memory store) on or after 2026-11-15.
- Simplification (my human partner's plan): agent commits memory directly via heredoc + script, no hook commits, no memory pre-commit approval gate, no SessionStart ff — explicit `gitlore:merge` only. G3 (identity scrub) is moot under it; record that in the simplification's D-entry.
