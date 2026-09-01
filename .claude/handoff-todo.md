## Open decisions

- The push-gate/tier-pin contradiction (`brief-push-gate-contradicts-tier-pin.md`): when a tier's HEAD sits at the recorded gitlink with local `live` *ahead*, the push preflight's remedy (`checkout --detach live`) moves the tier off its pin and the composition hook then refuses. Decide which ref is authoritative for a tier's checkout — `live`, or the gitlink the memory store records — and make both gates state the same one; likely route the preflight to `/gitlore:merge` instead of prescribing the checkout. The adjacent `live`-behind direction is already repaired (`gitlore_repair_stranded_live`, changelog `2026-09-01-a-stranded-live-is-advanced.md`); the `live`-ahead arm of `gitlore_check_head_live_agree` was deliberately left untouched for this decision.

- The memory index against Claude Code's ~24,985-byte loader cutoff, per `plans/2026-08-27-memory-index-budget-decision.md`. The index sits over both the 25,600-byte gitlore budget and the loader cap; three sweeps agree curation cannot close the gap. Recommended: reorder composition so tier blocks come last, then take `ddaanet` sub-scoping as its own subproject; third option is accepting the overage. Reordering touches D29's layout rule, D36's layout rewrite and `gitlore_order_merge`'s hoist in `index-composition.md` — three places.

- Whether constrained generation (skill text read before drafting) or unconstrained-then-review produces better memory facts — D47 leaves it open for `just evals`. D48 adds three review-side placements to compare against, and a comparison still has to control for the flows differing in more than directive placement.

- Why the post-merge D17 sync has anything to propagate at all: the upstream index pass should already have shortened descriptions before publishing, yet the downstream sync silently cut three routing clauses out of this repo's ddaanet files. Diagnose before considering remedies.

## Remaining

- Continue the ddaanet review pass from entry 5 of `plans/ddaanet-memory-review.md` (next-largest index lines).
- When the pass reaches the hook memories: combine `hook-output-channels` + `hook-cannot-inject-tool-calls` (ruled 2026-09-01), landing 2c finding (2) — `updatedInput` alone defers to the full pipeline, `permissionDecision` settles it — in the merged fact. `hook-input-schema` stays separate (stdin side, different moment).
- Cut a release: the stranded-`live` repair and everything since v0.5.0 reaches installed repos only at the next `just release` (`just evals` is a separate, explicit decision).
- `docs/design.md` is at exactly the 400-line cap; the next hub addition needs a split decision.
