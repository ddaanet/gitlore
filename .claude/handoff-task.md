## Current task

Working through the Critical and Major findings of the `plans/index-edit-propagation` deliverable review (`plans/index-edit-propagation/reports/deliverable-review.md`). C1 (with M4) and both halves of M5 have landed. Next is the relay redesign (C2, M1, M2, M3, M6 as one design pass), per the first open decision: design recorded in `docs/references/index-authoring-sync.md` and `docs/decisions.md` before any code, starting with the `PostToolBatch` subagent `session_id` probe.

The M5 continuation fix exits 0 when a tier merge lands unadopted, and rests the tier on its index pin with the merge in `live`; the claim that the next `/gitlore:resolve` run refuses that state and names `/gitlore:merge` is argued from `gitlore_check_head_live_agree`, not covered by a test of this exact fixture.
