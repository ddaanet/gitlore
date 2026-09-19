# Deliverable Review: tier-arrival-review-minors

**Date:** 2026-09-19
**Methodology:** docs/design.md §6.8 "Deliverable review"

Baseline: `outline.md` (design) with `runbook.md` as the later, authoritative item contracts; M1–M21 from `classification.md`. Range `3502a86..00584a1`, 1129 added / 118 removed lines outside `plans/` and `.claude/`. The tree has moved on since (`00584a1..HEAD`, unrelated work), so every finding is verified against HEAD and cited there. Layer 1 ran as two opus reviewers — `deliverable-review-code-test.md` and `deliverable-review-prose-docs.md` hold the detail; Layer 2 ran in the main session over message strings, exit contracts and cross-document consistency. Nothing found in the range has been fixed since; nothing later broke it.

## Inventory

| Type | File | +/− |
|---|---|---|
| Code | `scripts/lib/resolve.sh` | 113/40 |
| Code | `scripts/lib/index-compose.sh` | 17/2 |
| Code | `scripts/resolve.sh` | 24/9 |
| Test | `tests/push_behind_vs_diverged.bats` | 297/0 |
| Test | `tests/merge_memory.bats` | 255/2 |
| Test | `tests/resolve_compose.bats` | 152/1 |
| Test | `tests/index_compose.bats` | 60/4 |
| Test | `tests/git_hook_pre_commit.bats` | 36/1 |
| Test | `tests/commit_memory.bats` | 18/0 |
| Agentic prose | `agents/memory-merger.md` | 9/4 |
| Agentic prose | `skills/resolve/SKILL.md` | 16/3 |
| Human docs | `docs/references/tier-arrival-repair.md` | 46/28 |
| Human docs | `docs/references/tier-stores.md` | 9/7 |
| Human docs | `docs/references/merge-and-resolve.md` | 8/1 |
| Human docs | `docs/references/git-hooks.md` | 7/7 |
| Human docs | `docs/references/commit-gate.md` | 6/6 |
| Human docs | `docs/references/index-authoring-sync.md` | 1/1 |
| Human docs | `docs/changelog.md` + `docs/changelog/2026-09-18-…md` | 55/2 |

Conformance: all 21 findings are addressed. The one design/shipped divergence — the behind arm keeps its retry push, where the outline dropped it — is explained by the runbook (slice 2.1/2: a later tier's failure would otherwise strand the repair) and pinned by a test. `merge-and-resolve.md` is outside the runbook's file list but falls under Item 7.4's sweep; not excess.

## Critical Findings

None.

## Major Findings

1. **The rejected scratch-sweep alternative is recorded nowhere.** `docs/decisions.md:151-167`, `docs/references/tier-arrival-repair.md` "Rejected alternatives". The outline rejects, by name and with its reason, sweeping stale `gitlore-repair.*` directories on the next repair (it races a concurrent take), and records the choice as confirmed at proof. `grep -n sweep` over both files finds nothing. The project rule is that `docs/decisions.md` holds every rejected alternative by name and the node the argument; a session weighing a stale-scratch sweep finds no trace that it lost. The runbook's Phase 7 never assigned it, so the gap is inherited from the runbook, not introduced against it. Grounding: `scripts/lib/resolve.sh:2018`.

## Minor Findings

**Code**

2. `scripts/lib/resolve.sh:1472` — the behind arm's retry goes through `gitlore_report_tier_push_failure`, a fourth caller beyond Item 2.2's three, changing its wording with no test in the job's range. Covered since: `eabe091` added the guard at `tests/push_behind_vs_diverged.bats:454`, which a mutant restoring the fixed "not because of divergence" text fails.
3. `scripts/lib/resolve.sh:2049-2050` vs `:2130-2131` — the root-index refusal header and its `gitlore:   ` prefixing exist at two sites for one user-visible string.
4. `scripts/lib/resolve.sh:1513-1517` — the pass's `[ -z "$origin_live" ]` arm is unreachable and redundant, and no test runs it. Every tier that reaches the pass with a local `live` has `origin/live`: the loop pushed it (a successful push writes the tracking ref, a failed one returns 1), its behind arm classified against it, or a mid-loop take created `live` by fast-forwarding from it. Were it missing, `merge-base --is-ancestor live origin/live` fails and the tier is pushed all the same — the outline's own wording, and the form the behind arm's retry already uses at `:1470`. The arm buys only a suppressed `fatal:` line on a state that does not occur; removing it and the `origin_live` read leaves one spelling of the check. The two `continue` skips mirror the loop's and stay.

**Tests**

5. `tests/merge_memory.bats:1025` — `run ! grep …` clobbers `$stderr` with eight assertions still to come. Correct today (they read the saved `$all`); a trap for a later `$stderr` assertion.

**Agentic prose**

6. `agents/memory-merger.md:42`, `skills/resolve/SKILL.md:84`, `:107-108` — the post-landing push failure (`push_or_report` rc 2, `scripts/resolve.sh:373-375`, `:394-396`) exits 1 with a recognisable line, `… failed, and not because of divergence — no merge can fix this`, and is the one path that prints `rest_unadopted_tier`'s `stays on the merge commit … Run:` remedy (`scripts/resolve.sh:241-244`). Both readers put it in the unrecognised bucket by design, so a merge that did land is reported as "fate unknown", **Resume commit** is skipped, and the skill's "a printed remedy is still to run" paragraph (`:117-119`) is framed around **Loop**, which this path never reaches. The remedy still reaches the user verbatim, hence Minor; a recognised-line arm in both readers would close it.
7. `agents/memory-merger.md:41`, `skills/resolve/SKILL.md:82`, `docs/references/merge-and-resolve.md:103` — "a `live` push after it" names one of the two post-commit yield sites (`. HEAD:live` and, for `head-vs-remote`, `origin live`). Routing is unaffected.

**Human docs**

8. `docs/references/tier-arrival-repair.md:4-5` — "One of the nodes": the only subsystem node that neither states the count of five nor opts out, and the runbook's numeral-based sweep could not see it (M19 partial).
9. `docs/references/tier-arrival-repair.md:35-36` and the 2026-09-18 changelog entry `:18-19` — "under `$TMPDIR`" omits the `/tmp` fallback of `${TMPDIR:-/tmp}`.
10. `docs/references/tier-arrival-repair.md:91-94` — the retry-refusal arm's default remedy, `Fix the store, then run /gitlore:merge again.` (`scripts/lib/resolve.sh:2146`), is quoted in no node; the only hit in `docs/` is a changelog sentence describing it as removed wording.
11. `docs/references/tier-arrival-repair.md:55-57` vs `:59-67` — the refused `live` advance is described twice at different completeness; read in order the second reads as a correction of the first.
12. `docs/changelog/2026-09-18-…md:28-29` — the terminator rule omits the weld-tail case the code comment states (`scripts/lib/index-compose.sh:355-358`).

**Considered and dropped:** the post-loop pass carries no remote check, but no tier can reach it without one. A local `live` is a prerequisite after install or tier addition, and the only mid-loop creator of one — the take's fast-forward, `scripts/lib/resolve.sh:1794` — pushes from `origin/live`, so it needs the remote the loop's check (`:1407`) would have asked for; a tier with no remote is stopped by the take itself (`:1729-1733`).

**Cross-cutting (Layer 2), no finding:** every string the two prose readers and the docs key on is byte-exact against the harness (`scripts/resolve.sh:148,322,333,339`; `scripts/lib/resolve.sh:648,2019,2051`); every `exit 0` in `continue-after-merge` sits below the merge commit and every exit above it is non-zero, so "only exit 0 is landed" holds; nothing before the merge commit prints `gitlore: memory merge prepared`; the merger and the skill split the outcomes identically, the later denied-call branch included; source files cite no plan, memory path or runbook item; the changelog entry is indexed.

## Gap Analysis

| Requirement | Status | Reference |
|---|---|---|
| M1 unrepairable arm prints non-carrier problems | covered | `scripts/lib/resolve.sh:2041-2054`; `tests/merge_memory.bats` |
| M2 transient arms print refusal + `Run /gitlore:merge again.` | covered | `scripts/lib/resolve.sh:2018-2077` |
| M3 walk-back names what `live` holds | covered | `scripts/lib/resolve.sh:2144-2156` |
| M4 one reporter for a failed tier push | covered | `scripts/lib/resolve.sh:1620-1641` (Minor 2) |
| M5 mid-push repair race | covered | `scripts/lib/resolve.sh:1501-1524`; both variants reproduced red (Minor 4) |
| M6 terminator preservation | covered | `scripts/lib/index-compose.sh` `gitlore_repair_index` |
| M7 scratch directory outside the repo | covered | `scripts/lib/resolve.sh:2018`; rejected alternative unrecorded (Major 1) |
| M8 comment verb | covered | `scripts/lib/index-compose.sh` |
| M9–M13 test specificity | covered | mutant-proven, `reports/item-5-*.md` |
| M14 merger states rule 1 | covered | `agents/memory-merger.md:28` |
| M15 pre-landing exits, harness + prose | covered | `scripts/resolve.sh:320-341`; `agents/memory-merger.md:37-45`; `skills/resolve/SKILL.md:80-84,98-108` (Minor 6, 7) |
| M16, M17, M18, M20, M21 | covered | `git-hooks.md:161-163`; `tier-arrival-repair.md:20-30`; `tier-stores.md:211-212`; `changelog.md:38`; `commit-gate.md:57-61` |
| M19 node count | partial | `index-authoring-sync.md:5` covered; `tier-arrival-repair.md:5` uncounted (Minor 8) |
| 7.2–7.4 mechanism and quote sweep | covered | Minor 9–11 are precision gaps inside it |
| 7.5 changelog entry | covered | `docs/changelog.md:23` (Minor 12) |

Test evidence this review ran: `scripts/run-bats.sh tests/push_behind_vs_diverged.bats` → 21 passed, 0 failed; a read-only probe of `gitlore_repair_index` on three unterminated weld/drop fixtures outside the suite, all obeying the terminator rule. No other suite was run and no mutant applied.

## Summary

Critical 0, Major 1, Minor 11. No excess or missing deliverables.

The Major and Minors 3–12 are fixed in the working tree after this review, and Minor 2 needed nothing; `review-fixes-code.md` and `review-fixes-prose.md` hold the detail.
