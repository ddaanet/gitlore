## Current task

Propagating claude-plugin-dev `v0.4.0` to its consumer plugins. It is a
breaking release: `release` now depends on a consumer-defined `prerelease`
recipe rather than on `precommit`, and a consumer that vendors it without
defining one gets `error: Recipe release has unknown dependency prerelease`
— a whole-justfile compile error, so *every* recipe fails, `just precommit`
included, not only `release`.

## Open decisions

- Whether to push `v0.4.0` into all three consumers now or let each take it
  at its next release. `gitlore` already defines `prerelease: precommit
  evals` (it arrived at the same recipe name independently) so it gains the
  gate the moment it pulls; `handoff` and `gitmoji` each need a new
  `prerelease: precommit` line added in the same commit as the subtree pull,
  or their justfiles break on arrival.
