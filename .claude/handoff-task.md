## Current task

D17 slice 3a (the coverage/prune/dedup recompose) was reverted this session as premature; the next step is slice 3 — materialize the first nested tier (`memory/lore`) inside the memory submodule and build the **placement-only** SessionStart composition (splice each mounted tier's `memory/<tier>/MEMORY.md` carrier block into the root index, global-first with project bare-path lines last, plus carrier mirroring), with routing guidance added to the SessionStart `additionalContext`.

## Open decisions

- The presence-authority question — whether the file set or the index is authoritative over a line's *presence* (the index is canonical for line *text*; presence is a separate axis) — is **deliberately deferred, do not decide it before slice 3 forces it**. Settling it needs a log analysis of how presence actually drifts; the hunch leans file-set-authoritative, which would revive coverage/prune on their merits. Deferring is the decision, per [[feedback_plan_late]] (decide as late as possible, but not later) — don't build anything that presupposes an answer.
- Slice 3 needs its own fresh plan (plan-as-late-as-possible) before coding. Scope from D17's deferred items: nested-tier submodule materialization reusing init/FR11/push-lockstep, tier-block placement + carrier mirroring, routing guidance, and a composition that relocates tier blocks without deleting a tier line whose body lives in an unchecked-out nested submodule.
