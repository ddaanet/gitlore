## Brief: add-tier composition never reaches the index budget advisory

2026-09-03

Found while mounting the `ddaanet` tier into a fresh repo (`ddaanet/craft`).

### The finding

`/gitlore:add-tier` composes the root index but cannot warn that the result
overflows. The mount is the one operation that adds tens of KB of index in a
single step, and it is the one that reports no percentage.

Observed: mounting `ddaanet` (91 facts) into a repo whose own index was the
48-byte scaffold produced a 25,846-byte `MEMORY.md` — 101% of
`GITLORE_INDEX_BUDGET_BYTES` (25,600) and past the ~24,985-byte loader cutoff.
The add-tier report named the mount, the tier's routing guidance, the
`shared-claude.md` import line, activation, and `composed memory/MEMORY.md`. No
budget line. The session learned the index was truncating because the agent
measured it by hand.

Confirmed reachable by the other path in the same session: an ordinary
index-touching Bash batch (retiring one fact) emitted
`gitlore: MEMORY.md is at 100% of the 25600-byte always-loaded budget`.

### Cause

The advisory lives in `scripts/cc-hooks/index-sync-post.sh` (~L162–171 for the
gate, ~L213–221 for the emit), which fires on tool batches that touch the index.
add-tier composes through `scripts/add-tier.sh` instead, so the percentage is
never computed on that path. `gitlore_index_budget_pct` in
`scripts/lib/index-sync.sh` is already the shared helper.

### Constraints

- The once-per-episode marker is keyed by session and kind
  (`gitlore_index_budget_nudge_file`). A mount-time advisory and a later
  edit-time one in the same session need a decision about which suppresses which
  — silently reusing the same marker kind makes the mount advisory eat the
  edit-time one for the rest of the session.
- The mount is still correct when it overflows. This is a report, not a gate:
  the fix for an over-budget tier is not local to the consuming repo.
- The threshold that matters here is the loader cutoff, not the advisory budget:
  a mount can land at 97% of 25,600 and still be truncating.

### Additional context

The memory fact `ddaanet/gitlore-tier-index-budget` covered this ground and was
retired in the same session as redundant — its two substantive claims
(truncation takes the tail, the remedy belongs to the tier owner) are already in
the advisory's own wording and follow from knowing what a tier is. The residue
that is *not* redundant is this defect. If the advisory reaches the mount path,
nothing about that retirement needs revisiting.

Suggested shape, not a decision: compute the pct at the end of add-tier's
composition and append one line to its existing report, reusing the helper.
