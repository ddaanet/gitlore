# Simplification Report

**Runbook:** plans/tier-arrival-review-minors/runbook.md **Date:**
2026-09-15T15:35:19Z

## Summary

- Items before: 18
- Items after: 15
- Consolidated: 3 items across 2 patterns, plus one duplicated passage in Item
  1.1 removed.
- Line count: 472 before, 472 after. Consolidation does not shorten this
  runbook. Nesting the merged items costs about as many lines as the removed
  item headers save. The overage is test and mutant specification that carries
  weight. Cutting it would mean stripping assertions, which the brief forbids.

## Consolidations Applied

### 1. The two readers of Item 4.1's pre-landing lines

- **Type:** identical-pattern (the same rule taught to two prose readers of one
  harness output)
- **Items merged:** 6.1 (`agents/memory-merger.md`), 6.2
  (`skills/resolve/SKILL.md`)
- **Result:** Item 6.1, with one sub-bullet block per file.
- **Rationale:**
  - Both items key on the same two lines, the ones containing
    `the merge was not committed`.
  - Both have the same dependency (Item 4.1) and share requirement M15.
  - The outline's Phase 4 treats them as one split ("`SKILL.md` makes the same
    split"), so one editor keeping both readers consistent is the point.
  - Each file's edits stay whole inside the item, so prose atomicity holds.
  - Every original bullet is kept word for word. Only the indentation changes.

### 2. Single-clause docs fixes with no dependencies

- **Type:** same-module (`docs/references/` nodes, one inline phase)
- **Items merged:** 7.1 (`git-hooks.md`, M16), 7.4 (`index-authoring-sync.md`,
  M19), 7.5 (`commit-gate.md`, M21)
- **Result:** Item 7.1, "single-clause fixes in three nodes", with one
  sub-bullet per file tagged with its requirement.
- **Rationale:**
  - Each item is one sentence or one clause replaced in a different file.
  - None of them declares a dependency, so the three share an empty dependency
    chain.
  - Each file's edits stay in one item.
  - The replacement strings, the `rg` pattern and the "already correct and stay"
    note for `tiered-memory.md` are kept word for word.
- **Renumbering:**
  - 7.2 and 7.3 are unchanged.
  - The sweep 7.6 becomes 7.4, with "Depends on: Items 7.1–7.3, 6.1".
  - The changelog 7.7 becomes 7.5, with "Depends on: Item 7.4".

### 3. Item 1.1: walk-back argument positions stated twice (redundancy, not a merge)

- The **Walk-back wording** change bullets repeated the argument positions and
  the `what arrived` default, which **Interfaces** also states.
- They now point to **Interfaces** for position and default, and keep the rest:
  - which helper gains which argument;
  - pass-through and the empty-remedy rule;
  - the message template;
  - both call sites' arguments.

## Patterns Not Consolidated

- **1.1 + 1.2** (same file, same function `gitlore_adopt_repair_arrival`):
  - 1.2 depends on 1.1, and M7 (scratch location) is a separate behaviour.
  - 1.1 already has 15 assertions across four slices. Merging would make a god
    item without saving a dispatch, because TDD dispatches go per slice.
- **2.1 + 2.2** (same function `gitlore_push_stores`):
  - 2.1 carries the reproduction stop rule. Folding 2.2 into it would tie the
    wording work to a gate that may stop the phase.
  - Different behaviours (M5 and M4), and 2.2 depends on 2.1.
- **5.3 rule 4 + 5.4 rule 4** (same mutant, "`gitlore_compose_check_index` skips
  rule 4"):
  - Different entry points, test files and fixtures.
  - 5.4 depends on 4.1 and 5.3 does not.
  - Merging would also change which dispatch owns the mutant proofs.
- **5.1–5.4 generally:** each is one test file (5.3 is two) with its own
  mutants. There are no identical-pattern items with only the data varying.
- **7.2 + 7.3** (both align nodes with Phase 1/2 mechanisms): their dependency
  chains differ (7.2 needs 1.2; 7.3 does not).
- **7.3's grep bullet vs the 7.4 sweep:**
  - These overlap in part: scratch location, publication and walk-back wording.
  - Moving 7.3's grep into the sweep would split the `tier-stores.md` edits
    across items, so it is left in place.
- **Transient-arm assertion sets in 1.1/2, 1.1/4 and 1.2/2** (refusal header,
  `Run /gitlore:merge again.`, `HEAD` back on the pin):
  - Parametrizing them would merge slices across two items, which the brief
    forbids.
  - Factoring them into a shared definition saves about 2 lines net and makes
    every slice dispatch depend on a preamble.
- **Per-item `Model: sonnet` lines in Phase 5:** they are kept. Per `edify`
  `dispatch-composition.md`, the per-item `Model:` line is what `/orchestrate`
  reads, so a phase-level statement would not be honoured.

## Requirements Mapping

The mapping table is updated: Phase 6 → `6.1`, Phase 7 → `7.1–7.5`. Each of
M1–M21 still maps to an item:

| Requirement | Item |
|---|---|
| M1, M2, M3 | 1.1 (also 7.4 sweep) |
| M4 | 2.2 (also 7.4) |
| M5 | 2.1 (also 7.4) |
| M6, M8 | 3.1 |
| M7 | 1.2 (also 7.4) |
| M9, M10 | 5.1 |
| M11 | 5.2 |
| M12 | 5.3 |
| M13 | 5.3, 5.4 |
| M14 | 6.1 |
| M15 | 4.1, 6.1 (also 7.4) |
| M16, M19, M21 | 7.1 |
| M17 | 7.2 |
| M18 | 7.3 |
| M20 | 7.5 |

## Validation

- **Phases:** all seven are intact. Numbering is sequential within each phase:
  1.1–1.2, 2.1–2.2, 3.1, 4.1, 5.1–5.4, 6.1, 7.1–7.5.
- **Dependencies:**
  - No forward dependency was introduced.
  - The sweep still runs after every docs and prose edit.
  - The changelog still runs after the sweep.
- **Left untouched:** TDD slices, red/green semantics, the Phase 2 stop rule and
  the Phase 5 mutant proofs.
- **Line width:** the lines over 80 columns are all older unbreakable code spans
  or the table. `just format-docs` has not been run.
