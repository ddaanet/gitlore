## Current task

Resume D17 slice 3 at tier commit/push lockstep, then 3-ii composition and
3-iii `/add-tier`.

## Open decisions

- **One approval summary per memory episode, or per tier.** The lockstep slice
  is the first code that commits into more than one store in a single episode,
  so it forces the answer.
- **Whether the memory submodule needs its own recursing `pre-commit`/`pre-push`.**
  A tier is a submodule inside a submodule, so the parent's hooks do not reach
  it. Same slice.
- **Presence-authority: is the file set or the index authoritative over a
  pointer line's presence?** Coverage, prune, and dedup all wait behind this; it
  needs log evidence of how presence actually drifts, and the standing
  instruction is to decide on that evidence rather than let inaction pick.
- **Whether `release` should depend on a plugin-defined `prerelease` upstream.**
  Today `release` depends on `precommit` alone, since that dependency lives in
  the vendored `plugin-dev/release.just`, so releases go `just prerelease
  release`. Making the toolkit depend on a `prerelease` the plugin defines is a
  generic improvement, but it belongs in `ddaanet/claude-plugin-dev`, not in
  this repo's vendored copy.
