## Current task

Acting on `inbox/brief-index-edit-propagation-findings.md`. The `/runbook` pipeline over `plans/index-edit-propagation/outline.md` is complete through `/proof` — `runbook.md` holds 6 items across 4 phases, all proof items dispositioned — and the precommit sentinel split it was waiting on has landed: `lint`, `test-unit` and `test-integration` each guard their own sentinel through the `sentinel-guard` prolog helper, and `just precommit` runs green end to end. Next is `/orchestrate` over the runbook in this fresh session; from an agent the full gate runs with `run_in_background: true`.

Running alongside, still: the ddaanet memory curation — the index budget against the loader cutoff (103%), the design-moment tier merges, the oversized-fact splits, and the review pass.
