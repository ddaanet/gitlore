# 2026-09-13 — A tier merge the root index cannot adopt records nothing (D50)

When `gitlore_compose_up` refused a tier merge in `continue-after-merge`,
`compose_merged_indexes` reported it and the continuation then staged the moved
tier gitlink and committed it with `gitlore_commit_tier_bookkeeping` anyway. It
was the take path's defect in the continuation: the tier sat on its new pin
while root still held the tier's older block, and the printed remedy — edit
`MEMORY.md` to retrigger composition — ran a down projection over the merged
carrier. The deliverable review of `index-edit-propagation` flagged both halves
(finding M5); the take half landed first.

The merge still lands: the continuation commits it in the tier, clears the merge
state, advances `live` and — for a merge a refused push prepared, never one
`/gitlore:merge` prepared — publishes. It no longer stages the gitlink or makes
the bookkeeping commit, and on the paths that exit 0 it checks the tier out at
the pin the memory store's index holds, keeping the merge in the tier's local
`live`. That is the resting state a failed take leaves, which
`gitlore_adopt_advanced_live` adopts, so the remedy is to fix the store and run
`/gitlore:merge`.

The continuation exits 0, because the merge landed. The `gitlore:memory-merger`
agent and the resolve skill already relay a composition report as an index
problem beside a landed merge, and the next `/gitlore:resolve` run refuses the
tier's `live` ahead of `HEAD` and names the same take, so the unadopted state is
never carried by the exit status alone.

Two paths leave the tier where it is. A yield re-prepares a merge at the tier's
`HEAD`, and checking out would unlink `MERGE_HEAD`; that merge's continuation
retries the adoption. A pin the merge does not contain is not the merge's base,
so the tier stays on the merge and the pin guard names the remedy.
