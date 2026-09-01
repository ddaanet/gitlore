## Open decisions

- `/gitlore:merge` ignores local `live` (`brief-push-behind-tier-merge-blind-spot.md`, "What remains" item 1): `gitlore_merge_one_store` reasons from HEAD alone, so a store whose HEAD contains `origin/live` while `live` sits behind — the state 0.5.0's failed preparations left on every affected repo — reads as "already holds everything". Decide report (call `gitlore_check_head_live_agree` before the ancestry test, as push does) vs repair (`push . HEAD:live`, ff-checked, in `gitlore_merge_one_store`); either way add the HEAD-detached-at-remote, `live`-behind case to `tests/merge_memory.bats`. Sibling briefs in the repo root touch the same area: `brief-push-gate-contradicts-tier-pin.md`, `brief-tier-live-ref-stranded.md`.

- The memory index against Claude Code's ~24,985-byte loader cutoff, per `plans/2026-08-27-memory-index-budget-decision.md`. The index sits over both the 25,600-byte gitlore budget and the loader cap; three sweeps agree curation cannot close the gap. Recommended: reorder composition so tier blocks come last, so this repo's own lines and the newest facts stop being the truncated tail, then take `ddaanet` sub-scoping as its own subproject. The third option is to accept the overage and push the cap back upstream. Reordering touches D29's layout rule, D36's layout rewrite and `gitlore_order_merge`'s hoist in `index-composition.md` — three places.

- Whether constrained generation (skill text read before drafting) or unconstrained-then-review produces better memory facts — D47 leaves it open for `just evals`. D48 adds three review-side placements to compare against, and a comparison still has to control for the flows differing in more than directive placement.

- Why the post-merge D17 sync has anything to propagate at all. In the normal workflow the upstream repo's own index pass already shortened the fact file's frontmatter description before publishing, so the file arriving through a tier merge carries the shortened description and the downstream sync should be a no-op; that it silently cut three routing clauses out of this repo's ddaanet files means something upstream of the trim is wrong. Diagnose before considering remedies.

## Remaining

- Continue the ddaanet review pass from entry 5 of `plans/ddaanet-memory-review.md` (next-largest index lines).
- When the pass reaches the hook memories: combine `hook-output-channels` + `hook-cannot-inject-tool-calls` (ruled 2026-09-01), landing 2c finding (2) — `updatedInput` alone defers to the full pipeline, `permissionDecision` settles it — in the merged fact. `hook-input-schema` stays separate (stdin side, different moment).
- `docs/design.md` is at exactly the 400-line cap again after the D49 additions; the next hub addition needs a split decision.
