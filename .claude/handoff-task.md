## Current task

Orchestrating `plans/index-edit-propagation/runbook.md` with the edify
orchestrate skill. Phases 1-3 and Item 1.2 are behind; Phase 4 is the whole
remainder — 4.0 narrows `docs/references/index-authoring-sync.md`, whose
per-batch baseline invariant Item 2.1 falsified; 4.1 the decision node, which
must also give the subagent-confinement measurement a shipped home and back-fill
its `D<n>` into the `gitlore_relay_*` comments, since shipped source may cite
neither `plans/` nor `memory/`; 4.2 the decisions index; 4.3 the changelog's two
surfaces.

Item 1.2 left two residuals recorded in the runbook rather than fixed, and 4.1's
decision node is where they have to be argued or dismissed: an interrupted
`/gitlore:merge` continuation can be handed to the new pin guard by
`gitlore_recover_stale_no_merge_head` under a `checkout --detach` remedy that
would undo the repair, and the guard covers active tiers while the commit's
`add -A` covers mounted ones, so a dormant tier off its pin is still adopted
silently.

The dispatch shape that worked, and should continue: each slice runs RED (sonnet
test-driver) → test review (opus corrector) → GREEN (sonnet test-driver) → code
review (opus corrector), and the orchestrator alone runs the gate and makes
every commit. Every subagent prompt says so and gives the reason. A born-green
slice — one whose behaviour an earlier slice already landed — collapses to RED
plus test review: there is nothing for GREEN to write or a code review to read,
and the test review runs the mutation round in their place. The reviews earn
their cost by mutating the SUT and measuring which wrong implementations still
ship green; that round, never the pass/fail count, found every real defect in
Phase 3 and Item 1.2.

Running alongside, still: the ddaanet memory curation — the index budget against
the loader cutoff, the design-moment tier merges, the oversized-fact splits, and
the review pass.
