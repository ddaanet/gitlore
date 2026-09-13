# 2026-09-13 — A half-landed memory commit retries to completion (D50)

The pin guard D50 added to `gitlore_sync_memory_to_live` could not tell a tier
moved behind gitlore's back from one gitlore had just committed in. The commit
path commits inside each dirty tier first, and only memory's later `add -A`
stages the moved gitlink. A transient `index.lock` on memory between the two
left the tier ahead of its pin. The retry `memory-commit-batch.sh` promises then
aborted with "no automatic remedy", on every memory commit for the rest of the
session. Before the guard, the same retry adopted the move and completed. The
deliverable review of `index-edit-propagation` reproduced it (finding C1).

`gitlore_sync_tiers_to_live` now writes a landing record into the tier's gitdir
just before each tier commit, naming the commit the tier sits on. It removes the
record when the commit fails, and once `add -A` has staged every gitlink.
`gitlore_stage_landed_tiers` runs ahead of the pin guard and stages the gitlink
of any tier whose HEAD's parent is the recorded commit and still the pin.
Staging it overwrites nothing, because the commit path composed that carrier
from the root index just before committing it.

Two alternatives were weighed. Matching the tier commit's message against the
approved summary needs no state. But a session that edits memory while the retry
is still blocked approves a new summary, and the landed commit no longer
matches. Staging each gitlink right after its tier commit narrows the window and
does not close it: that staging writes memory's index too, so the same lock
stops it.

A failure after the freshness gate now keeps the approval, unless it prepared a
merge. What the run writes — a composed carrier, a recovered merge's up
projection — projects lines the summary approved, yet reads newer than the
commit-msg file. The `pre-commit` retry reuses that file as it stands, so it
would have demanded a new summary. A merge preparation checks unapproved content
out into the worktree, so it still leaves the approval stale.

The ahead-of-pin refusal's remedy no longer says to stage the gitlink by hand.
Staging alone is the overwrite the refusal exists to stop. The remedy now names
the carrier to bring into the root index first, then the quoted staging command.
The two adoption remedies in `resolve.sh` quote their paths as well.
