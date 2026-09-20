## Current task

The precommit speed-up run is finished: a per-file shellcheck cache under `lint`, per-suite sentinels under `test-unit` and `test-integration`, and a cheaper `make_parent_with_memory` copy path. Batching `rev-parse` in the hooks measured at nothing and a Python rewrite was set aside; the measurements and both arguments are in `plans/precommit-speed/bats-timings-2026-09-20.md`. Nothing is in flight; the todo list is what is left.
