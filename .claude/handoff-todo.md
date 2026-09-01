## Open decisions

- Whether this release runs `just evals`. It drives the real claude CLI and costs time and money, so it is an explicit call and deliberately not part of `just release`.
- The memory index against Claude Code's ~24,985-byte loader cutoff, per `plans/2026-08-27-memory-index-budget-decision.md`. The index sits over both the 25,600-byte gitlore budget and the loader cap; three sweeps agree curation cannot close the gap. Recommended: reorder composition so tier blocks come last, then take `ddaanet` sub-scoping as its own subproject; the third option is accepting the overage. Reordering touches D29's layout rule, D36's layout rewrite and `gitlore_order_merge`'s hoist in `index-composition.md` — three places.
- Whether constrained generation (skill text read before drafting) or unconstrained-then-review produces better memory facts — D47 leaves it open for `just evals`. D48 adds three review-side placements to compare against, and a comparison still has to control for the flows differing in more than directive placement.
- Why the post-merge D17 sync has anything to propagate at all: the upstream index pass should already have shortened descriptions before publishing, yet the downstream sync silently cut three routing clauses out of this repo's ddaanet files. Diagnose before considering remedies.

## Remaining

- Continue the ddaanet review pass from entry 5 of `plans/ddaanet-memory-review.md` (next-largest index lines).
- When the pass reaches the hook memories: combine `hook-output-channels` + `hook-cannot-inject-tool-calls` (ruled 2026-09-01), landing 2c finding (2) — `updatedInput` alone defers to the full pipeline, `permissionDecision` settles it — in the merged fact. `hook-input-schema` stays separate (stdin side, different moment).
- Triage `brief-plugin-dev-0.6.1.md`, the remaining open brief in the repo root.
- `docs/design.md` sits at exactly the 400-line cap; the next hub addition needs a split decision.
