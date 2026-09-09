## Current task

Orchestrating `plans/index-edit-propagation/runbook.md` with the edify
orchestrate skill. Phase 3 is complete: Item 3.1 shipped in five slices (1, 2,
2.5, 3, 4, 5 — 2.5 and 5 added mid-phase from review findings), so a subagent's
memory-index report now reaches the parent through a per-agent marker in the
memory gitdir, with SessionStart as the backstop and every failure path costing
the relay rather than the hook's own report.

Next is Item 1.2 — the D-1 pin abort, `gitlore_compose_check_pins` at the
`gitlore_sync_memory_to_live` call site, aborting on refusal — then Phase 4's
four items: 4.0 narrows `docs/references/index-authoring-sync.md`, whose
per-batch baseline invariant Item 2.1 falsified; 4.1 the decision node, which
must also give the subagent-confinement measurement a shipped home and
back-fill its `D<n>` into the `gitlore_relay_*` comments, since shipped source
may cite neither `plans/` nor `memory/`; 4.2 the decisions index; 4.3 the
changelog's two surfaces.

The dispatch shape that worked, and should continue: each slice runs RED
(sonnet test-driver) → test review (opus corrector) → GREEN (sonnet
test-driver) → code review (opus corrector), and the orchestrator alone runs
the gate and makes every commit. Every subagent prompt says so and gives the
reason. The reviews earn their cost by mutating the SUT and measuring which
wrong implementations still ship green — that round, never the pass/fail count,
found every real defect this phase, including two cases that could not have
passed at GREEN and an assertion the runbook itself named as the discriminator
which discriminated nothing.

Running alongside, still: the ddaanet memory curation — the index budget
against the loader cutoff, the design-moment tier merges, the oversized-fact
splits, and the review pass.