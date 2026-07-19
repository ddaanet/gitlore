## Current task

D17 slice 3-i-a (nested-tier propagation-in + routing) is implemented and green across Tasks 1–3 of its plan, awaiting David's eyeball review before Task 4 (the real-`ddaanet` dogfood) and the branch-model unification refactor that follows.

## Open decisions

- **`ddaanet` remote visibility** for the Task 4 dogfood: default private (matching the memory submodule's own default) unless David overrides. The submodule git writes need David's `!` shell — the agent cannot run them.
- **Whether the linked-worktree finding changes the lockstep design:** a D11 linked memory worktree gets its own independent tier clone (separate objects and refs), so two worktrees can diverge and both push to one tier remote. Harmless for propagation-in; needs a decision when tier commit/push lockstep is planned.
- Still deferred to their own slices: one approval summary per memory episode vs. per tier; whether the memory submodule needs its own recursing `pre-commit`/`pre-push`.
