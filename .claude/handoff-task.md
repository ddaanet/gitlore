## Current task

D17 slice 3-i-a (nested-tier propagation-in + routing) and a follow-on shell
hardening pass over `scripts/` both await David's eyeball review, before Task 4
of the 3-i-a plan (the real-`ddaanet` dogfood) and the branch-model unification
refactor that follows it.

## Open decisions

- **`ddaanet` remote visibility** for the Task 4 dogfood: default private
  (matching the memory submodule's own default) unless David overrides. The
  submodule git writes need David's `!` shell — the agent cannot run them.
- **Whether the linked-worktree finding changes the lockstep design:** a D11
  linked memory worktree gets its own independent tier clone (separate objects
  and refs), so two worktrees can diverge and both push to one tier remote.
  Harmless for propagation-in; needs a decision when tier commit/push lockstep
  is planned.
- **How much to trust the push-rejection discriminator:** the pre-push and
  resolve paths now gate the merge-resolution flow on git's parenthesized reason
  (`(fetch first)`/`(non-fast-forward)`), verified against real output for the
  divergence and pre-receive cases. That text is git's UI, not a documented
  contract — if it drifts across versions or transports, a genuine divergence
  gets reported as an unexpected failure rather than entering the resolve flow.
  Accept that failure direction, or pin it with a test against a real
  non-fast-forward push?
- Still deferred to their own slices: one approval summary per memory episode
  vs. per tier; whether the memory submodule needs its own recursing
  `pre-commit`/`pre-push`.
