## Open decisions

- `memory/ddaanet/shared-claude.md` Dispatch bullet "This box will not take parallel heavy work" (~2GB RAM) contradicts the updated `~/.claude/CLAUDE.md` (8GB, 4 vCPU, parallel agents and gates fine). Proposed: delete the bullet; needs my human partner's approval of a memory summary.
- Six inbox briefs under `inbox/` (https-submodule-urls, launcher-memory-path-containment, launcher-shim-second-sighting, memory-gate-owner-inventory-and-existence, orphan-report-fix-recipe, write-https-urls): held until the backlog was done; triage which to take.

## Remaining

- Release review of `dev` against `main`: `/code-review high`, then `/codex:adversarial-review astra --base main` (typed by my human partner).
- `tests/install_remote.bats` sets `GITLORE_HOME` for only one test; call `isolate_home` (`tests/helpers/setup.bash`) in its `setup`.
- Delete each `gitlore/archive/2026-10-15` branch (tier and memory store) on or after 2026-11-15.
- Simplification (my human partner's plan): agent commits memory directly via heredoc + script, no hook commits, no memory pre-commit approval gate, no SessionStart ff — explicit `gitlore:merge` only. G3 (identity scrub) is moot under it; record that in the simplification's D-entry.
