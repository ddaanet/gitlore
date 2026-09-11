## Current task

Orchestrating `plans/index-edit-propagation/runbook.md` with the edify
orchestrate skill. Phases 1-3, Items 1.2, 4.0 and 1.3 (both slices) are behind.

Phase 4 remainder: Items 4.1 + 4.2 must land in **one** commit — a decision
argued in a node with no conclusion line in the decisions index is what
`scripts/check-docs-links.py` blocks on as `unstubbed-decision`, so the gate
must not run between them — then Item 4.3's two changelog surfaces. Next free
decision id is D50; re-derive rather than trust that, with
`grep -oh 'D[0-9]\+' docs/decisions.md docs/references/*.md | sort -u -t D -k2 -n | tail -1`.

D50 must carry Item 1.3's two invariants. From slice 1, up-before-stage:
staging a moved gitlink without projecting the carrier up first *inverts* the
pin guard — the index then agrees with HEAD, composition proceeds, and the down
projection writes root's older text over the merged-in facts. From slice 2, the
wrapper in `gitlore_sync_memory_to_live` names no remedy of its own: every
branch of `gitlore_compose_check_pins` prints the one its cause takes, and one
abort can carry several tiers with different causes.
