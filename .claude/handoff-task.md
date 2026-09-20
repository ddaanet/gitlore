## Current task

Making `just precommit` faster. `lint` now keeps a per-file shellcheck cache under the whole-tree sentinel, so a one-file edit costs ~4s instead of ~65s. Next is a `--timing` pass over the full bats run, to choose between building fixtures once per file in `setup_file` and per-suite gate sentinels. The gate mechanism is recorded in `docs/references/testing.md`.
