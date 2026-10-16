# 2026-09-21 — Resolve publishes memory's `live` only after every tier gate

`scripts/resolve.sh` pushed memory's `live` as soon as it saw a remote without
that branch. The push sat with the Plan 02 simple repairs at the top of the
script — ahead of the stale-merge guard, ahead of the tier loop, ahead of
memory's own gate — because it read as a repair of an unpublished store rather
than as a publication. It is a publication. A tier gate refusing after it left
the memory remote holding a gitlink the tier's remote could not resolve, which
is the exact failure D17 orders the gates to prevent, and a consumer cloning in
that window gets a memory commit it cannot complete.

`check_store_gates` already ends by pushing `live` to `origin`, and the script
already calls it for every mounted tier before the memory root, so nothing had
to be added: the early push is deleted and publication falls to the last gate
that runs. `tests/resolve.bats` pins it with a tier diverged from its remote —
the memory remote must still be missing `live` when the run stops.

The rule is now stated in `docs/references/merge-and-resolve.md`, where the
resolve skill's ordering is described. It had been enforced by two call sites
and argued by neither.

Two test-side changes ride along. `tests/justfile_gates.bats` runs its forced
discovery once in `setup_file` and shares the status and output through
`$BATS_FILE_TMPDIR`, rather than paying a real `just` invocation per case.
`approve()` and `mount_tier_at_live()` live once in
`tests/helpers/tier-fixtures.bash`; the copies in three helpers and in
`tests/tier_lockstep.bats` are gone. And `plans/2026-09-21-macos-check/run.sh`
is the one-shot diagnostic that measures what bash 3.2 does to a bats assertion,
runs the repair suites with assertions under a modern bash and exec'd scripts
under 3.2, and calls `run-bats-cached.sh` with every optional array empty —
`GITLORE_TEST_BASH_DIR` in `tests/helpers/setup.bash` is the opt-in that puts a
chosen `bash` first on PATH for what a test execs.
