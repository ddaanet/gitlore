# Simplification Report

**Runbook:** plans/unadoptable-tier-arrival/runbook.md **Design:**
plans/unadoptable-tier-arrival/outline.md **Corrector report:**
plans/unadoptable-tier-arrival/reports/runbook-review.md **Date:** 2026-09-14

## Summary

- Items before: 17 (1.1, 2.1–2.3, 3.1, 4.1, 5.1–5.3, 6.1–6.7, 7.1)
- Items after: 17
- Consolidated: 0 items across 0 patterns

No consolidation candidates. The runbook is unchanged.

## Consolidations Applied

None.

## Patterns Examined and Not Consolidated

- **Items 1.1 and 2.1 share `scripts/lib/index-compose.sh`.** They are in
  different phases, and the functions are not independent: 2.1's caller (2.2)
  depends on 1.1's helper. Each is also a distinct behaviour: attribution versus
  repair.
- **Items 2.2 and 2.3 share `scripts/lib/resolve.sh`.** 2.3 depends on 2.2,
  because its slices take the repair 2.2 builds. They edit different functions
  (`gitlore_adopt_tier_into_root` versus `gitlore_merge_one_store` and the
  `behind` arm), and the dependency chains differ.
- **Items 3.1 and 4.1 share `scripts/resolve.sh`.** They are in different
  phases, and 4.1 depends on 3.1. They edit different functions.
- **Slice level, Item 1.1 slices 1 and 3** (a dirty carrier aborts; a dirty root
  aborts). They exercise different dirtiness reads (tier `status -- MEMORY.md`
  versus root) and different rule sets (any carrier problem versus root rules
  1/4/6). Merging them would join two behaviours in one slice.
- **Slice level, Item 2.1 slices 2 and 6** (an identical duplicate; a differing
  duplicate). Slice 6 carries the pin-lookup behaviour, and its three rows are
  already parametrized within it. Slice 2 is the first red for the duplicate
  rule. They are distinct behaviours.
- **Slice level, Item 2.1 slices 3 and 4** (a weld splits; the weld guard). The
  corrector deliberately separated them so that slice 4's missing-file case
  carries its own red (review Major 3).
- **Slice level, Item 2.2 slice 2 and Item 2.1 slices 3/5.** Slice 2.2/2 already
  batches the weld and interleaved arrivals as one guard slice. No further
  reduction preserves one behaviour per slice.
- **Phase 5 (5.1–5.3) and Phase 6 (6.1–6.7).** Each item targets a different
  prose file. By rule, these phases have one item per prose artifact, so none
  were merged.
- **Item 7.1.** This is a single item.

## Requirements Mapping

No changes. All mappings, `Depends on:` targets, fixtures, message strings,
assertions, guard marks and Interfaces blocks are preserved as the corrector
left them.
