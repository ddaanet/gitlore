## Current task

Orchestrating `plans/index-edit-propagation/runbook.md` with the edify
orchestrate skill: 4 phases, 6 items, the first three of them tdd. Phase 1 is
complete — Item 1.1 ran as four slices and its boundary checkpoint
(`plans/index-edit-propagation/reports/phase-1-corrector.md`) came back with six
items needing a decision. The run is holding there: D-1 through D-6 get
addressed by a subagent first, then Phase 2 Item 2.1 (per-agent index baselines)
opens with a RED dispatch.

Two slices departed from the standard cycle by decision, and the TDD audit at
the end of the run has to read them as decisions rather than process defects.
Slice 2 ran without a RED phase: Item 1.1's own text places the compose inside
the `dirty = 1` branch, so slice 1's implementation pre-satisfied the guard
slice 2 exists to pin and a RED would have been vacuous — mutation evidence
stands in, in `item-1-1-s2-green.md`. Slice 4 pinned a fix that had already
landed untested in `62258fa`, so its RED backed the two `touch "$msgfile"`
statements out to have something to red against and GREEN restored them; the
slice commit carries only tests, and the discrimination evidence is the
four-mutation table in `item-1-1-s4-code-review.md`.

The model rules binding the rest of the run: a test-driver dispatch runs sonnet
in both RED and GREEN, and any dispatch whose deliverable is prose runs opus.
Both outrank a runbook item's own `Model:` line, so the `Model: opus` on Items
2.1 and 3.1 does not apply to their test-driver dispatches, and Item 4.3's
`Model: sonnet` becomes opus because a changelog entry is prose.

Running alongside, still: the ddaanet memory curation — the index budget against
the loader cutoff, the design-moment tier merges, the oversized-fact splits, and
the review pass.
