# 2026-05-26 — Fixed FR7 clone-restore bug

Added a clone-from-remote integration test
(`tests/integration_clone_restore.bats`): build an origin via the real install
flow (gh-mock + local bare → memory remote carries `live`), clone without
`--recurse-submodules`, run only `SessionStart`. It exposed a real defect —
`git submodule update --init` leaves a detached HEAD with only `origin/live`, so
`SessionStart`'s `checkout -b <branch> live` died with
`fatal: 'live' is not a commit`; every fresh clone failed to restore. Fix:
`SessionStart` materializes a local `live` (from `origin/live`, else `HEAD`)
after submodule init, before the branch-model logic. 136 tests green.
