## Current task

The two gate defects the 400-line split run surfaced are fixed: `scripts/lint-shell.sh` lints untracked, non-ignored shell files, and `tests/justfile_gates.bats` records its stubbed sentinels in a scratch directory through `GITLORE_GATE_DIR`. Next is making `just precommit` faster: a per-file shellcheck cache in `lint` first, then per-suite bats timings to choose between `setup_file` fixtures and per-suite gates. The gate mechanism is recorded in `docs/references/testing.md`, which is where the cache design goes too.
