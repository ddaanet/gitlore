# 2026-09-21 — A first publish stops printing git's missing-ref line, and the `lint` gate sees the scripts under `plans/`

Four strands, each a gap between what a script actually reads and what something
else assumed it read.

`check_store_gates` fetched `origin live` before every push, including on a
store whose remote has never held the branch, so a first publish printed git's
`couldn't find remote ref live` at a user for whom nothing was wrong. It takes a
first-publish argument now and skips the fetch when it is set. Only a caller
already holding the remote's ref list passes it — the memory root, from the
`ls-remote` its reachability probe pays for anyway. A tier still fetches and
still prints the line on its own first publish: finding out beforehand would
cost every resolve run a round trip per tier, and the function's comment says
so.

The `lint` gate hash gains `plans/*.sh`, `*.bash` and `*.bats`. `lint-shell.sh`
walks the whole tree while `precommit_inputs` leaves `plans/` out, so an edit to
`plans/macos-check/run.sh` moved no hash and reported a cached pass over a file
the run would have linted. By extension only: a plan's prose must not cost a
lint run, so an extensionless script there is linted without moving the hash.
Writing the test for that found `guard_line` in `tests/justfile_gates.bats`
evaluating an empty name under just 1.46, whose dump nests an interpolation one
level deeper — `guard_input_files` then listed the whole tree and the input
assertions held vacuously. It reads both shapes now and fails when a name does
not evaluate, which is the failure the vacuous pass had been hiding.

Three files came under the 400-line cap by pure extraction, continuing the
2026-09-20 pass: `check_common.py` holds what the two checkers duplicated,
`check_docs_decisions.py` the decisions-index checks, and session-start's nested
tier stage is `gitlore_sync_nested_tiers` in `scripts/lib/session-tiers.sh`,
with `push_rejection_discriminator.bats` pinning the ancestry check at its new
home. `__pycache__/` is ignored, since bytecode written under `scripts/` would
move every gate hash on every run.

`scripts/test-macos.sh` is the standing macOS run: the unit suites with bats
under a modern bash and exec'd scripts under `/bin/bash` 3.2, on a PATH narrowed
to the system directories plus the tools the platform lacks — a Homebrew PATH
says nothing about the platform. It exits with bats' status and records no
sentinel, because `test-unit`'s hash does not know which bash ran the scripts.
No CI job runs it; it is run by hand on a Mac.
