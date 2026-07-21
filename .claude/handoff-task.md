## Current task

First teach the parent `pre-commit` hook to leave the memory gitlink alone while
a rebase or cherry-pick is replaying — it now stages the gitlink on every
commit, so an `--amend` mid-surgery re-pins the replayed commit to memory's
current SHA instead of the one it recorded — then resume D17 slice 3 at tier
commit/push lockstep, followed by 3-ii composition and 3-iii `/add-tier`.

## Open decisions

- **How far the replay guard reaches.** Skipping the gitlink staging is the
  settled part. Undecided: whether the whole sync is skipped too, since dirty
  memory during a replay trips the FR11 approval gate and would abort the
  rebase rather than the commit; and whether a skip announces itself or stays
  silent, given the hook has no way to tell a deliberate replay from a stuck
  one.
- **What content each sentinel hashes.** `just precommit` and `just prerelease`
  are to skip when their recorded content hash still matches, so `release`
  right after a green `precommit` re-runs only the uncovered part. Undecided:
  whether the hash covers the whole tracked tree or a per-gate input set (a
  narrower set skips more often but silently misses an untracked input), and
  where the sentinel is recorded so it survives a rebuild but never travels
  between checkouts. A fork drafted an implementation of both gate scripts this
  session; it was removed rather than reviewed, and is to be rewritten.
- **One approval summary per memory episode, or per tier.** Deferred to the
  lockstep slice, which is the first code that commits into more than one store
  in a single episode.
- **Whether the memory submodule needs its own recursing `pre-commit`/`pre-push`.**
  Same slice — a tier is a submodule inside a submodule, so the parent's hooks
  do not reach it.
- **Presence-authority: is the file set or the index authoritative over a
  pointer line's presence?** Coverage, prune, and dedup all wait behind this;
  it needs log evidence of how presence actually drifts, and the standing
  instruction is to decide it on that evidence rather than let inaction pick.
