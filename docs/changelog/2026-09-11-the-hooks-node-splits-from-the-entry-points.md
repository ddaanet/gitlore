# 2026-09-11 — The hooks node splits from the entry points

`git-hooks-and-entry-points.md` sat at exactly 400 lines, the cap every `docs/`
file is held to, with the commit path's newest argument already inside it. The
seam is the one the node's own title named: the two git hooks that run inside a
parent git operation, and the two callable scripts that do the same work with no
parent operation in flight. A reader reaches one of them for `pre-commit`'s
order or the gitlink invariant, and the other for `gitlore.commitCommand` or the
`push` skill's divergence loop; neither errand is served by the other half, and
the title's conjunction was the only thing binding them.

`git-hooks.md` keeps the two hooks, the gitlink invariant, D46 and D50.
`memory-entry-points.md` takes `commit-memory.sh`, `push-memory.sh`, the
placeholder-url marker, the `push` skill, D16 and D20. Each opens by naming the
other, because the shared bodies — `gitlore_sync_memory_to_live` and
`gitlore_push_stores` — are described on the entry-point side and run from the
hook side.

The rejected alternatives follow their decisions rather than their subject
matter: *triggering a memory commit through a parent commit* fights the hook's
parent-commit requirement, but what it argues against is D16's standalone entry
point, so it travels with D16. `docs/decisions.md` carries two adjacent groups
in place of one, each with its own pointer, conclusions and *Rejected:* line;
every conclusion line keeps its wording, because this is a regrouping.

None of it is a new decision. The 400-line cap already says a node that reaches
it is split along a need-time seam rather than granted an exception, so choosing
the seam applies that rule instead of taking a call.

The room the split frees pays for a move that was owed.
`gitlore_adopt_recovered_merge` was documented inside D50's body, where it read
as an aside to the pin guard; it belongs to merge-state recovery, whose node
classifies every shape a disturbed merge leaves and said nothing about what the
landed case owes the enclosing store. The mechanism — compose the recovered
tier's carrier up into the root index, stage `MEMORY.md` and the tier together,
stage nothing when the projection fails, and fire for a tier alone — is stated
in `merge-state-recovery.md` as part of that flow, citing D50 for why the
ordering is load-bearing. D50 keeps the invariant itself: a path adopting a tier
ahead of its pin composes up before it stages, because staging alone removes the
disagreement the pin check reads and leaves the next down projection free to
write root's older text over facts root has never seen.
