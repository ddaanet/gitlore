## Current task

Orchestrating `plans/index-edit-propagation/runbook.md` with the edify
orchestrate skill. Phase 1 is complete with its six boundary decisions (D-1
through D-6) landed, and Phase 2's Item 2.1 is closed: all four consumers of
`gitlore_index_preimage_file` / `gitlore_compose_stamp_file` now key the
pre-image and compose-stamp paths on the payload's `agent_id`, so a parent
batch can no longer consume a subagent's baseline. Next is Phase 3, Item 3.1 —
relaying a subagent's `systemMessage` and `additionalContext` to the parent, in
four slices — which Item 2.1 made load-bearing rather than cosmetic: a
subagent's memory edit now propagates correctly and reports it to nobody. Then
Item 1.2, then Phase 4.

The dispatch shape that worked, and should continue: each slice runs RED
(sonnet test-driver) → test review (opus corrector) → GREEN (sonnet
test-driver) → code review (opus corrector), and **the orchestrator alone runs
the gate and makes the commits**. Every subagent prompt says so explicitly and
gives the reason. Two review passes in Item 2.1 found assertions that could not
fail, both times by mutating the SUT and measuring which wrong implementations
still shipped green — that mutation round is what the reviews are for, not the
pass/fail count.

A second thread is unresolved: the `precommit` gate has three times produced a
verdict split across two trees. Separately, this box OOM-killed five
consecutive gate runs when other sessions were live.

Running alongside, still: the ddaanet memory curation — the index budget
against the loader cutoff, the design-moment tier merges, the oversized-fact
splits, and the review pass.