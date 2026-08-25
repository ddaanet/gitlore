# 2026-06-09 — Implemented D12 — submodule-side commit gate closes the FR11 bypass

A direct `git -C <mempath> commit` (agent, human, or script) bypassed the
per-commit review gate, which lived only on the parent `pre-commit`; found
dogfooding on a downstream project. Fix, two parts: (A, load-bearing) a new
`scripts/git-hooks/memory-pre-commit` gate, emitted by
`scripts/emit-memory-gate.sh` into the submodule's common hooks dir
(`--git-path hooks/pre-commit`), that blocks any commit lacking the
`GITLORE_MEMORY_COMMIT=1` env sentinel — now exported by all three blessed paths
(parent `pre-commit:66`, both `resolve.sh` merge commits, install
`init-submodule.sh`). The wrapper degrades on unset/stale `gitlore.hooksDir`
like the parent wrappers (D5); since it fires in the submodule git context,
`emit-memory-gate.sh` mirrors the parent's `gitlore.hooksDir` into the submodule
config. (B) `SessionStart` emits a standing commit-protocol `additionalContext`
every session, correcting the generic-memory mental model before the agent acts.
Updated the "PreToolUse hook" Rejected Alternative to "superseded by D12". New
tests: `git_hook_memory_pre_commit.bats` (3), `emit_memory_gate.bats` (9),
`integration_memory_gate.bats` (2), plus SessionStart gate-wiring +
standing-context cases. 180 green.
