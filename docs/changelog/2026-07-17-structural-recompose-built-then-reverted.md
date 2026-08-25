# 2026-07-17 — D17 slice 3a (structural recompose) built, then reverted the same day on review

A `SessionStart`-only `scripts/lib/index-recompose.sh` carried three flat-store
operations — dedup-by-path, prune of orphaned lines, and coverage-seeding of
uncovered files. Eyeball review found all three unjustified: **dedup** guarded
residue from a `merge=union` driver that is not (and will not be) used —
distinct per-index namespaces make cross-index duplication impossible, and
concurrent tier insertions merge through the semantic memory-merger, so no
duplication arises to clean; **prune** and **coverage** were premature, not
wrong — both presuppose that the file set is authoritative over line *presence*,
a question left open (the index is canonical for line *text*; presence is a
separate axis whose direction needs log evidence not yet gathered, and the hunch
leans file-set-authoritative), so baking either into a hook decides by default
what should be decided later on evidence; each also silently hardcodes a
*semantic* call that belongs to the agent (prune can destroy the last
recoverable record of a lost memory; coverage can resurrect a
deliberately-removed line). None advanced nested memory — the tier machinery
(block placement, carrier mirroring) was already deferred to the next slice.
Reverted `index-recompose.sh`, its 11-case bats suite, the `session-start.sh`
wiring + its test case, and the plan doc; folded the reasoning into the
composition/Conflicts paragraphs and two new Rejected Alternatives rows. Slice 3
is now purely tier composition (placement/splice + mirroring), landing with the
first nested tier.
