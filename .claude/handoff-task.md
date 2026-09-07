## Current task

Orchestrating `plans/index-edit-propagation/runbook.md` with the edify orchestrate skill: 4 phases, 6 items, the first three of them tdd. Phase 1 Item 1.1 slice 1 has finished RED and its test review, so the two new cases in `tests/commit_memory.bats` and `tests/git_hook_pre_commit.bats` sit in the tree failing on their carrier assertion. That red is the designed state between RED and GREEN, not a defect to fix. The next dispatch is that slice's GREEN, then its code review; Item 1.1 has two further slices after it.

A correction landed mid-run and binds the rest of it: a test-driver dispatch runs sonnet in both RED and GREEN, and any dispatch whose deliverable is prose runs opus. Both outrank a runbook item's own `Model:` line, so the `Model: opus` on Items 1.1, 2.1 and 3.1 does not apply to their test-driver dispatches, and Item 4.3's `Model: sonnet` becomes opus because a changelog entry is prose.

Running alongside, still: the ddaanet memory curation — the index budget against the loader cutoff, the design-moment tier merges, the oversized-fact splits, and the review pass.
