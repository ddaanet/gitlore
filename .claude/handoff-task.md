## Current task

Shell-gotcha audit fixes are complete and verified (full git-hook `unset $(git rev-parse --local-env-vars)`, `unset CDPATH` at every `cd … && pwd` capture site, `LC_ALL=C` on the NUL read loop, new GIT_COMMON_DIR regression test) — committing now; no code work remains in flight.

## Open decisions

- Whether to cut a 0.2.8 release — 0.2.7 shipped the macOS-broken launcher shim that is now fixed, and `.gitlore/bin/claude` was regenerated again this session (added `unset CDPATH`).
- Whether the D16 standalone-memory-commit plan (`docs/plans/2026-06-12-09-standalone-memory-commit.md`) is fully landed — `scripts/commit-memory.sh` + `tests/commit_memory.bats` now exist and pass; confirm against the plan's remaining tasks before considering it closed.
- The shell-scripting plugin (`shell-scripting@ddaanet`) has still never been trigger-tested in a real session beyond this scan.
