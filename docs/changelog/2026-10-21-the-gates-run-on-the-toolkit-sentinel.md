# 2026-10-21 — The gates run on the toolkit's sentinel

**The sentinel functions are the toolkit's.** The release toolkit, from 0.11.0,
ships the gate sentinel gitlore had carried in its own `bash_prolog`
(`check-sentinel`, `sentinel-guard`, `record-sentinel`, `gate-inputs-hash`) and
the quiet bats runner it had in `scripts/run-bats.sh`. gitlore imports
`plugin-dev/gates.just` and runs `plugin-dev/run-bats.sh`, and keeps what the
toolkit does not ship: `run-suites` and its per-suite cache. The gate files
moved from `gitlore/gates` to `plugin-dev/gates` under the gitdir, and
`GITLORE_GATE_DIR` and `GITLORE_GATE_FORCE` became `PLUGIN_DEV_GATE_DIR` and
`PLUGIN_DEV_GATE_FORCE`. Two behaviours changed with the functions: an input
edited mid-run now leaves no pass recorded and keeps the checks' own verdict,
where the recipe used to fail; and a declared pathspec that matches no file is
refused at the guard, so the `lint` hash names `plans/*.sh` alone while no plan
carries a `.bash` or `.bats` file. `docs/references/testing.md` says so.

**Design stops shipping.** Toolkit 0.12.0 builds the `dist` branch from the
paths `dist.include` lists, and its reference check refuses a shipped Markdown
file that links to one the list leaves out. `docs/` is design, read by whoever
works on gitlore and by no skill, so it is not listed. The README keeps the
runtime requirements and reaches the design by one URL; the recipe list, the
gate prose and the dev-only dependencies it carried were already in
`docs/references/testing.md` and `CLAUDE.md`. `precommit` now depends on the
toolkit's `check-refs`, which runs uncached on every call.
