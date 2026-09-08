## Current task

Orchestrating `plans/index-edit-propagation/runbook.md` with the edify orchestrate skill: 4 phases, 6 items, the first three of them tdd. Phase 1 Item 1.1 is complete — slice 3 replaced the `|| true` at the commit-path compose call with a `case` over `gitlore_compose`'s status, and its code review landed two major fixes on top. The run is holding before Phase 1's boundary checkpoint on the two questions in the todo file; the first of them decides whether a slice 4 runs before that checkpoint.

Slice 2 ran without a RED phase, by decision: Item 1.1's own text places the compose inside the `dirty = 1` branch, so slice 1's implementation pre-satisfied the guard slice 2 exists to pin, and a RED there would have been vacuous. Mutation evidence stands in for it, recorded in that slice's GREEN report. The TDD audit at the end of the run needs to read it that way.

The model rules binding the rest of the run: a test-driver dispatch runs sonnet in both RED and GREEN, and any dispatch whose deliverable is prose runs opus. Both outrank a runbook item's own `Model:` line, so the `Model: opus` on Items 1.1, 2.1 and 3.1 does not apply to their test-driver dispatches, and Item 4.3's `Model: sonnet` becomes opus because a changelog entry is prose.

Running alongside, still: the ddaanet memory curation — the index budget against the loader cutoff, the design-moment tier merges, the oversized-fact splits, and the review pass.