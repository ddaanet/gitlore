# ddaanet memory review

Working ledger for a pass over all 100 `memory/ddaanet/` facts, ordered by index
line size, largest first. Each entry records the verdict against the
`memory-writing` rubric and my human partner's decision.

Index at start of pass: 26,219 B across 101 lines (100 ddaanet + 0 project),
against Claude Code's 24.4 KB loader cap. 100 ddaanet fact files.

Verdict vocabulary: **keep** (save as written) · **update** (edit body or index
line) · **merge** (fold into another fact) · **retire** (delete) · **relocate**
(to `shared-claude.md` or a repo `CLAUDE.md`) · **plugin** (becomes a skill,
feature request or bug report).

| # | Bytes | Fact | Verdict | Decided |
|---|-------|------|---------|---------|
| 1 | 867 | `memory-writing` | keep | done — skill question deferred to end of pass |
| 2 | 760 | `sandbox-effects` | update (relocate + merge out) | pending |

## Parts

This file holds the table, the short entries, and any entry that still fits.
An entry that outgrows a screen moves to its own part file, kept under 400
lines each.

- [2a · the exclusion mechanism](ddaanet-memory-review-2a-exclusion-mechanism.md)
  — entry 2's rubric, change (a), and the `excludedCommands` matcher decompiled
  from the CC 2.1.233 bundle.
- [2b · what an exclusion covers and costs](ddaanet-memory-review-2b-exclusion-scope.md)
  — the phantom masks, the corpus tallies, and why `git:*` and `ls:*`/`grep:*`
  are the wrong shape.
- [2c · the deny predicate, the remaining changes, and the decisions](ddaanet-memory-review-2c-deny-and-decisions.md)
  — the deny predicate, proposed changes (a-bis) through (f), the permission
  pipeline, and what is taken versus open.
- [2d · the corpus scrape](ddaanet-memory-review-2d-corpus-scrape.md)
  — `cd`/`git -C` frequency and the replay of the proposed `cwd-safety` rule,
  measured over 20,481 Bash calls. Supplies the numbers for the two decisions
  2c left open.

---

## 1 · `memory-writing` — 867 B

Largest line in the store, 3.3% of the index.

**Rubric.** Incident: yes, several quoted corrections. Reader-unaided: no.
Reconstructable: model-inference class, failure silent — carry it. Moment: one
— about to write, review, merge or retire a fact; the file already absorbed
three by-topic splits into that single moment. Tier: correct. Strip: clean —
present tense, no deictics, the two first-person quotes are attributed
corrections and already carry `hygiene-ok` markers. Index line: carries four
distinct trigger sets (what to cut · new-file-vs-merge · which tier · routing a
fact up); not compressible without dropping one whole.

**Verdict: keep as written.**

**Deferred: ship it as a `gitlore:memory-writing` skill instead.** gitlore ships
`merge`, `push`, `recall`, `resolve` — nothing owns authoring. This file is a
procedure with a mechanical, detectable trigger (a write under `memory/`), which
is the skill-not-command case, and its own doctrine says a fact whose body
reduces to "when writing a memory, do X" belongs in the skill that fires at that
moment. Converting it frees 867 B of capped index and moves the text to a budget
that is not silently truncated. Raised once at the end of the pass, together
with the other guide-shaped facts that pose the same question.

## 2 · `sandbox-effects` — 760 B

In [2a](ddaanet-memory-review-2a-exclusion-mechanism.md),
[2b](ddaanet-memory-review-2b-exclusion-scope.md),
[2c](ddaanet-memory-review-2c-deny-and-decisions.md) and
[2d](ddaanet-memory-review-2d-corpus-scrape.md).

## 1b · `memory-writing` — reopened

`memory-writing` governs what a fact says and which file it lands in.
`index-compaction-triggers` governs the line pointing at it. Neither says how to
organise the file itself once it holds a dozen independent facts under one
trigger — which is the shape every merged reference in this store converges on.
Proposed addition, drawn from what went wrong in `sandbox-effects`:

- Order sections by the literal a reader arrives holding, never by discovery
  order.
- One section per symptom. A symptom whose cases differ gets one section with a
  discriminator, not one section per case.
- Discuss a shared remedy in one place and reference it; a remedy restated in
  four sections drifts in four directions.
- Past roughly a screen of sections, lead with a symptom → section map.
- A fact that is a *cost of the remedy* files under the remedy, not under the
  symptom that led you to it.
