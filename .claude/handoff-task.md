## Current task

Execute the written plan `docs/plans/2026-06-12-09-standalone-memory-commit.md` — four TDD tasks adding the standalone `commit-memory.sh` memory-commit entry point (D16); the design is fully spec'd in design.md, no code started.

## Open decisions

- Plan Task 3 Step 5: confirm whether `tests/install_run.bats` drives a full install through `write-settings.sh` (extend that test) or whether a focused `write-settings.sh` invocation test is needed for the `gitlore.commitCommand` key assertion.
- Carried from prior session: whether to cut a 0.2.8 release — 0.2.7 ships the macOS-broken launcher shim that commit 3b416bb already fixes.
- Carried: the shell-gotchas plugin (installed as `shell-scripting@ddaanet`, repo at `/Users/david/code/shell-gotchas`) is built but never trigger-tested in a real session.
