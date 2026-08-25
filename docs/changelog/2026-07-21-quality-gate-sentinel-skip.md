# 2026-07-21 — Quality gates skip when the tree is what it was the last time they passed

`scripts/run-gate.sh NAME CMD...` records, on success, a content hash of the
whole tree under `$(git rev-parse --git-path gitlore/gates)/NAME`, and skips the
command when that hash still matches. `just precommit` (version drift +
shellcheck + bats) and `just evals` (drives the real `claude` CLI, so slow and
paid) each own a sentinel; `just prerelease` depends on both, so run right after
a green `precommit` it re-runs only the evals. The hash covers the **whole**
tree rather than a per-gate input set: a narrower set would skip more often but
a forgotten input yields a stale green, which is the one failure a gate must not
have. It is content-addressed via a throwaway index (`cp` the real index,
`add -A`, `write-tree`) rather than HEAD-addressed, because a release commits
*after* precommit goes green and that commit must not invalidate it; untracked
non-ignored files count, since `make test` discovers suites by glob and an
unstaged new suite changes what runs. Failing to hash records nothing and runs
the gate — the safe direction, and a real one: under a sandbox surfacing phantom
home dotfiles `git add -A` dies outright, and the first draft would have
recorded the half-updated index's hash and skipped the *next* run. `release`
still depends on `precommit` alone (that lives in the vendored
`plugin-dev/release.just`), so a release goes `just prerelease release`, where
release's own precommit is a sentinel skip.
