# Simplification report — index-edit propagation

**Runbook:** `plans/index-edit-propagation/runbook.md` **Date:**
2026-09-05T23:06:23Z **Baseline:** the review-fixed runbook at `b718232`

## Summary

- Items before: 6. Items after: 6.
- Slices before: 13 (Phase 1: 4, Phase 2: 4, Phase 3: 5, Phase 4: n/a).
- Slices after: 11 (Phase 1: 3, Phase 2: 4, Phase 3: 4).
- Consolidated: 2 patterns, 2 slices removed. No test case was dropped — all 26
  named cases survive, each in its own bats body.

The item count is unchanged because the phases already did the same-module
batching: Phase 1 is one library edit, Phase 2 is one helper plus its four
consumers in one item, Phase 3 is one helper plus three hooks in one item. There
was no item-level inflation left to remove. The unit that still drives dispatch
cost is the slice — each is a red review plus a green dispatch — so both
consolidations are slice merges.

## Consolidations applied

### 1. Phase 1 slices 3 and 4 → slice 3, "The compose return code decides"

- **Type:** same-module batch (one `case` construct, one suite)
- **Items merged:** Item 1.1 slice 3 (off-pin refusal reported, commit proceeds)
  and slice 4 (write failure aborts the commit)
- **Result:** Item 1.1 slice 3, with an `rc 1` arm and an `rc 2` arm, both cases
  in `tests/commit_memory.bats`
- **Rationale:** the two slices are the two arms of one branch over
  `gitlore_compose`'s status, at one call site in one function. Split across two
  cycles the executor writes `if rc -eq 1` and then refactors it. They are also
  each other's control, which is a correctness gain and not only a cost saving:
  an implementation that aborts on every non-zero rc passes the rc-2 case and
  fails the rc-1 one, and one that never aborts does the reverse. Running them
  in one red makes that mutual constraint visible; running them apart lets each
  arm be authored without the other's constraint in view.
- **Preserved:** both cases stay separate bats bodies with every assertion
  intact — including review finding 3's two-string stderr pair
  (`tier composition refused` for the branch, `is checked out at` for the
  forwarding) and finding 7's corrected `mv`-not-temp-write induction with its
  `id -u` guard. Seven assertions across the merged slice.

### 2. Phase 3 slices 2 and 3 → slice 2, "Both PostToolBatch reports relay on the same wiring"

- **Type:** identical-pattern (the same insertion in two scripts)
- **Items merged:** Item 3.1 slice 2 (compose hook relays) and slice 3 (the same
  relay carries the index-sync report)
- **Result:** Item 3.1 slice 2, four cases — two in
  `tests/cc_hook_index_compose.bats`, two in `tests/index_sync.bats`
- **Rationale:** verified against the tree, not inferred from the titles.
  `scripts/cc-hooks/index-compose.sh` and `scripts/cc-hooks/index-sync-post.sh`
  converge on the same emission shape — a sysmsg/ctx pair, a non-empty guard
  over it, one `jq -n` (`index-compose.sh:55-59`, `index-sync-post.sh:232-240`)
  — so the relay is the same insertion at the same point in both. Authored in
  separate cycles, one mechanism acquires two shapes. Merging also surfaces a
  constraint that binds both hooks and is easy to see only once: the fold has to
  precede the emission guard, or a parent-side run whose only report is a
  relayed one emits nothing. That note is now in the slice.
- **Preserved:** each hook keeps its own keyed/unkeyed pair as two bats bodies.
  The merge is along the *hook* axis only; the keyed-vs-unkeyed axis, which is
  the discriminating one, was not touched. Twelve assertions across four cases —
  over the ≤8 guideline for a single item, accepted here because the assertions
  are distributed across four independent bodies in two suites rather than
  stacked in one.

Phase 3's remaining slices renumbered 4→3 (SessionStart drain) and 5→4 (failed
relay write). The one internal cross-reference introduced ("slice 3 is the
backstop") points at the SessionStart drain under the new numbering. No other
slice cross-reference in the runbook moved: every existing one names slice 1.

## Patterns not consolidated

- **Phase 2 slices 2, 3 and 4 — the keyed-vs-unkeyed cases.** Flagged as a
  likely candidate; declined. Each of these is a positive/negative pair over one
  fixture differing only in the presence of `agent_id`, and each half asserts
  the presence of one path form *and* the absence of the other. Merging them
  collapses exactly the paired-assertion shape review findings 1, 5 and 6 were
  fixes for. Slice 3's second case is explicitly "the positive that keeps the
  negative honest".
- **Phase 2 slices 2 and 4 as one "wire all four consumers" slice.** Declined:
  the work differs per consumer rather than repeating. `index-sync-pre.sh` and
  `index-sync-post.sh` already hold `$payload`; `index-compose.sh` and
  `add-tier-batch.sh` drain it (`cat >/dev/null` at `:23` and `:38`) and must be
  converted to capture, `add-tier-batch.sh` under `set -euo pipefail`. Three
  suites and nine assertions in one cycle for two dissimilar edits.
- **Phase 2 slice 1's four helper cases.** Genuinely identical-pattern — two
  pure path helpers × keyed/unkeyed — and mergeable along the helper axis
  without losing an assertion. Declined because it buys nothing: the slice count
  is unchanged either way, so no dispatch is saved, and folding two functions
  into one bats body under errexit costs the independent failure signal. The
  runbook already states the second helper's cases by reference ("the same two
  assertions against `gitlore-compose-stamp`").
- **Phase 3 slice 3 (SessionStart) into the merged slice 2.** Declined: it is
  not the same insertion. `session-start.sh` accumulates through `add_sysmsg`
  and `protocol_ctx` (`:71`, `:325-338`), not a sysmsg/ctx pair behind a `jq -n`
  guard, and it is drain-only — a SessionStart hook never fires inside a
  subagent, so it has no keyed write side. Its pair is drain-positive vs
  no-marker-negative, with a framing literal held in one test-file variable per
  the review's minor fix.
- **Phase 3 slice 4 (failed relay write).** A distinct failure induction with
  its own `id -u` guard and its own narrowing instruction. Nothing to merge it
  with.
- **Phase 1 slices 1 and 2.** Declined: review finding 1's whole fix was giving
  slice 2 a fixture that *reaches* the `dirty = 1` guard
  (`git -C memory branch -f live HEAD~1`), distinct from slice 1's. Merging them
  re-entangles the two fixtures the review separated.
- **Items 4.1 and 4.2.** They must land in one commit — the docs-links gate is
  red by construction between them — which reads as a merge signal. Declined on
  the different-dependency-chains constraint: Item 4.2's second half is the open
  cap fork, and the runbook states that an instruction to split `docs/design.md`
  instead replaces that half and adds a phase. Merged, that restructuring would
  have to carve the D50 hub conclusion back out of a combined item. The
  one-commit coupling is already stated twice — in Item 4.1 and in the Gate — so
  the hazard is covered without the merge. Item 4.2's open decision was left
  exactly as written, per instruction.
- **Item 4.3.** Already batches its two changelog surfaces into one item.

## Requirements mapping — verified after the edits

Item count and identity are unchanged, so no mapping moved. Checked in the
edited file:

| Requirement | Phase | Items in table | Items present | `Requirements:` line |
|---|---|---|---|---|
| FR-B | 1 | 1.1 | 1.1 (`:46`) | `:48` |
| FR-C | 2 | 2.1 | 2.1 (`:228`) | `:230` |
| FR-D | 3 | 3.1 | 3.1 (`:347`) | `:349` |
| FR-E | 4 | 4.1, 4.2, 4.3 | 4.1 (`:505`), 4.2 (`:537`), 4.3 (`:585`) | `:507`, `:538`, `:587` |

Every item that exists is named in the table, every item in the table exists,
and all six carry a `Requirements:` line. Phase structure is intact (four
phases, no orphans), item numbering is sequential within each phase, slice
numbering is sequential within each item, and no forward dependency was
introduced — Item 3.1 still depends only on Item 2.1, and Phase 4's chain (4.1 →
4.2 → 4.3) is untouched.

## Note for the executor

The review artifact `runbook-review.md` refers to Phase 3 slices by their
pre-consolidation numbers: its minor fix for "Phase 3 slice 4" is now slice 3,
and "Phase 3 slice 5" is now slice 4. Its coverage table's "1.1 (4 slices)" and
"3.1 (5 slices)" now read 3 and 4. The review file was not edited.
