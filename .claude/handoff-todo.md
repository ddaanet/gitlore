## Open decisions

- The memory index against Claude Code's ~24,985-byte loader cutoff, per `plans/2026-08-27-memory-index-budget-decision.md`. The index sits over both the 25,600-byte gitlore budget and the loader cap; three sweeps agree curation cannot close the gap. Recommended: reorder composition so tier blocks come last, then take `ddaanet` sub-scoping as its own subproject; the third option is accepting the overage. Reordering touches D29's layout rule, D36's layout rewrite and `gitlore_order_merge`'s hoist in `index-composition.md` — three places.

## Remaining

- Rerun the recall log analysis with native recall included: count `attachment.type == "relevant_memories"` entries as a fourth class (harness), keep the spontaneous/manual/active split for model Reads, fold Bash `cat`/`sed` reads of memory files into the same per-file counts, and report the 7 most- and least-read facts plus the class totals over time.
- Continue the ddaanet review pass from the queue in `plans/ddaanet-memory-review.md` (entry 5, `hook-output-channels`).
- `docs/design.md` sits at exactly the 400-line cap; the next hub addition needs a split decision.
