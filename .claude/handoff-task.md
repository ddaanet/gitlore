## Current task

Execute the written plan `docs/plans/2026-06-12-09-standalone-memory-commit.md` (four TDD tasks adding the standalone `commit-memory.sh` memory-commit entry point, D16) — not started; this session instead added the shellcheck precommit gate (`scripts/lint-shell.sh` + `make lint` wired into the justfile `precommit` recipe), which is complete, clean, and green.

## Open decisions

- Plan Task 3 Step 5: confirm whether `tests/install_run.bats` drives a full install through `write-settings.sh` (extend that test) or whether a focused `write-settings.sh` invocation test is needed for the `gitlore.commitCommand` key assertion.
- Whether to cut a 0.2.8 release — 0.2.7 ships the macOS-broken launcher shim that commit 3b416bb already fixes (and `.gitlore/bin/claude` was just regenerated to match the fixed template).
- The shell-gotchas plugin (`shell-scripting@ddaanet`, repo `/Users/david/code/shell-gotchas`) is built but never trigger-tested in a real session.
