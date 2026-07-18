## Current task

D17 slice 3 (free-form multi-tier memory) is fully designed and the first buildable slice **3-i-a** (nested-tier propagation-in + routing) has a written TDD plan at `docs/plans/2026-07-18-11-tiered-memory-3i-propagation.md`; implementation has not started — Task 1 is a nested-submodule characterization spike that gates the rest.

## Open decisions

- **Execution approach for 3-i-a:** subagent-driven (recommended — Task 1's spike findings should gate Task 2) vs inline with checkpoints. Not yet chosen.
- **`ddaanet` remote visibility** when the dogfood stands up the real tier: default private (matches memory's own default) unless overridden.
- Deferred to their own later slices (not 3-i-a): one approval summary per memory episode vs. per tier; whether the memory submodule needs its own recursing `pre-commit`/`pre-push`. The branch-model unification (memory+tiers → detached-at-`live`) is a Plan-03-level refactor slice that lands *before* tier commit/push lockstep.
