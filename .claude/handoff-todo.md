## Open decisions

- The memory index against Claude Code's ~24,985-byte loader cutoff, per `plans/2026-08-27-memory-index-budget-decision.md`. The index sits over both the 25,600-byte gitlore budget and the loader cap; three sweeps agree curation cannot close the gap. Recommended: reorder composition so tier blocks come last, then take `ddaanet` sub-scoping as its own subproject; the third option is accepting the overage. Reordering touches D29's layout rule, D36's layout rewrite and `gitlore_order_merge`'s hoist in `index-composition.md` — three places.

## Remaining

- Continue the ddaanet review pass from entry 5 of `plans/ddaanet-memory-review.md` (next-largest index lines).
- `docs/design.md` sits at exactly the 400-line cap; the next hub addition needs a split decision.
