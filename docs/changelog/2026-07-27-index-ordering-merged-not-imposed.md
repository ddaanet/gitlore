# 2026-07-27 — Index ordering became merged rather than imposed, in both the divergence merge and the root↔carrier compose

Both had the same placeholder rule — every surviving path in ours' order, then
theirs-only appended — chosen because no insertion-point arithmetic existed and
neither caller seemed to need one: for the root index composition reorders the
tier blocks straight afterwards, and for a carrier the incoming facts could sit
at the end. Both halves of that were too generous. Composition normalizes only
*tier-prefixed* lines; a project-local bullet passes through verbatim, so for
those the merge's order was final and uncorrected. And "the incoming facts sit
at the end" quietly discards an authored choice: where a bullet sits in an index
is a decision (grouping, what gets read first), and appending destroys it on
every merge and every mirror-down of a reordered root. The fix is one primitive,
`gitlore_order_merge` — `git merge-file -p --union` over the three
**path sequences**, first-occurrence-wins on the duplicate `--union` can emit —
used by `_gitlore_index_merge_bullets` and `gitlore_compose_tier_bullets` alike.
`--union` is the tiebreak precisely because a shared offset is not a dispute
worth a human's time: two sides inserting different facts at one point disagree
about placement, not content, so it resolves ours-then-theirs silently rather
than emitting markers. Merging *paths* and not bullet text is what keeps the two
axes independent — with text in the sequence, rewording a hook would read as a
positional edit and relocate its entry. Compose takes the root as ours, so root
ordering propagates into the carrier and splice-up reproduces it, while a
carrier-only arrival keeps the offset the other consumer gave it (the
compose-base makes it an insertion, not an append). Five regressions in
`tests/index_merge.bats` and `tests/index_compose.bats`, three of which the old
code already passed and now guard the new one.
