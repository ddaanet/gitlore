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
| 3 | 691 | `green-is-not-evidence` | update (index line) | pending |
| 4 | 590 | `index-compaction-triggers` | update (re-split with `memory-writing`) | pending |

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

## 3 · `green-is-not-evidence` — 691 B

Second largest line, 2.6% of the index. Body 15,073 B, 13 shapes in section 1
and 11 rules in section 2.

**Rubric.** Incident: yes — ghmem dispatch B1 (2026-07-21), five tasks each
shipping at least one wrong-reason test, plus the twins shape and the
seam/mutation-survival pair added later from the restart repair. Owner: the
nearest candidate is `superpowers:test-driven-development`, whose
`writing-good-tests.md` reference loads at "writing or changing tests" —
grepped, and it carries the mirror assertion, shared setup-and-assertion
objects, change detectors, mock-existence assertions and a mutation check.
That reaches three of the thirteen shapes and none of section 2, and the
plugin is a versioned third-party cache overwritten on update. Not owned.
Reader-unaided: no — every shape was found by deleting code and re-running,
never by reading. Reconstructable: model-inference, failure silent by
definition. Moment: one, and already the product of the three-file merge
(`tests-must-go-red` + `tests-that-cannot-discriminate` +
`tests-pass-for-the-wrong-reason`) that `memory-writing` cites as its own
worked example. Tier: correct. Strip: clean — no deictics, no first person,
every bullet leads with a present-tense rule and carries a past-tense exemplar
that supplies the discrimination.

**Siblings check out.** `genuine-red-not-missing-sut` states the
green-at-first-run rule in near-identical words, but the merge commit records
that as deliberate: the observation criterion was moved there because it fires
at write time, and the shapes stayed here for review time. Both ends
cross-link. `bats-shellcheck-gotchas` is the declared general-shape versus
framework-mechanism split, also cross-linked from both ends.

### (a) The closing sentence points at nothing

"It pairs with the sibling lesson that briefs themselves misdescribe the code"
names no target, and never did: in the pre-merge source it sat beside
`[[sdd-reviewer-tiering]]`, which has since been retired into
`shared-claude.md`'s reviewer-tiering rule, and the pairing sentence survived
alone. A reader cannot act on it.

Proposed: cut it. If the intended referent is
`spec-enumerations-need-rederiving` — a plan that hand-lists call sites while
conformance passes clean is a brief misdescribing the code — link that instead.

### (b) The index line enumerates diagnoses, not symptoms

`index-compaction-triggers` states the direction: an agent arrives holding a
symptom and needs the prescription. This line carries neither. It lists what
each shape is *called* — "birth state", "algebraic tautology", "parallel counts
all equal", "upsert idempotence for teardown" — and none of those is a string a
session can arrive holding. They are diagnoses, legible only once the file has
been read. The comparison is sharp against `sandbox-effects` and
`bats-shellcheck-gotchas`, whose lines carry `index.lock`, `SC2314`, `exits
127` — things that appear in output.

The line has also lagged the body. Nine additions are absent from it: the seam
that substitutes for the whole expression, errexit ordering of grouped
negatives, exact-block equality where the absent string is a variant of the
present one, decoy-first fixture ordering against a fallback, two channels
pinned independently, mutation-survival's two readings, third-party-tool
message negatives, the unreachable-fixture smell, and the bare negative
assertion.

Growing the line to cover all nine is the wrong move on a capped index, and
shortening it to hit a byte target is the thing `index-compaction-triggers`
forbids. The third option is available because the tokens at issue were never
trigger tokens: rewrite from diagnoses to arrivals. One symptom clause covers
eight shapes at once — *a test that stays green with the code it names
deleted* — which frees room for the arrivals that are currently missing:
`--partial` matched by another line, a negative that fails against working
code, a fixture pair that collides when setup lands inside one clock second, a
seam whose value spans more than the thing being faked.

Expected size: roughly unchanged at ~690 B. The rewrite buys routing, not
headroom; headroom is the separate retirement decision.

### (c) Two things this raises for later entries

`index-compaction-triggers` is entry 4. The symptom-versus-diagnosis rule
generalises past this file — `sandbox-effects`, `memory-writing` and
`design-doc-writing` all carry catalogue lines with the same shape — so it
belongs in that entry rather than being settled here.

`genuine-red-not-missing-sut`'s third section, interface contracts one per
line, fires at plan-writing rather than test-writing and sits beside
`plan-contracts-not-full-code` and `honest-line-count-caps`. Noted for its own
entry.

**Deferred: the skill question lands differently here.** `memory-writing` would
convert to a gitlore skill this repo owns. This fact's nearest skill home is
`superpowers:test-driven-development`, third-party and versioned. edify is the
intended replacement for superpowers, but its test-writing knowledge is spread
over runbook, inline and test-driver, with no component that fires at "about to
accept a green test" — three distinct HOWs sharing one WHEN, which is the
split-by-topic shape `memory-writing` names, one layer up at the skill
boundary. So the end-of-pass question for this fact is not whether to convert
it but whether edify wants a test-evidence component at all, which is an edify
design question and outside this session's write scope. Until such a home
exists this memory is the only artifact firing at that moment.

**Verdict: keep the body, rewrite the index line.**

## 4 · `index-compaction-triggers` — 590 B

Opened early, because entry 3's proposal (c) depends on where the
symptom-versus-diagnosis rule lands.

**The challenge.** `index-compaction-triggers` and `memory-writing` fire at the
same moment — writing and reviewing memories — so they are one memory split by
topic.

**The duplication tell fires, and only on part of the file.** Near-verbatim in
both: *merge for routing, never for headroom*, and *a merged line must still
carry both entries' distinctive literals*. Both also state the relocation rule
(`memory-writing`'s "CLAUDE.md's job" against the acted-inline class here) and
the retire-what-is-reconstructable rule (rubric questions 3 and 4 against "the
levers that buy real headroom"). `memory-writing`'s rubric question 8 is this
file's first 40% compressed into one line plus a pointer.

**But the body is two moments wearing one name.** Stated in one clause each:

- **A — I am writing or reviewing a memory.** An index line's only job;
  shortening is not a prose edit; the WHEN/HOW/acted-inline classification; the
  failure has a direction; what is safe to cut and what is not; over budget is
  never a reason to under-trigger; topical overlap is not coverage; a
  compressed rule must keep its exceptions; delete hooks that restate their own
  title.
- **B — I am deciding what the index as a whole should still contain.** The two
  budgets and the loader cap; truncation takes the tail; count tokens
  index-wide before and after; the three levers with their measurements;
  rewriting bodies is not a lever; relocating acted-inline is; retiring inverts
  the audit; brief two adversarial auditors on disjoint classes; sweep plain
  words, not just backticks; whole-index trimming measured as the wrong lever;
  restore a silent trim rather than weighing it as divergence; the 55-file
  frontmatter diff a one-line index edit produces.

Roughly 40% A, 60% B. The duplication is confined to A. `memory-writing` says
nothing about auditor briefs, before/after token counts or the frontmatter
diff, and never needs to.

**The file's own name describes only B.** "Compaction" is exactly the B moment.
The A class fires when no compaction is happening — every memory write — which
is why it reads as belonging to `memory-writing` and why the pointer at
question 8 exists at all.

**The seam is asymmetric, which is what makes it real.** A fires on every
memory write. B fires only on a curation pass, and a curation pass always needs
A with it. A split where one side is a strict consumer of the other is a seam,
not a topic heading: the frequent cheap moment should not have to route past a
procedure it never runs. The two also differ in trigger kind by this file's own
classification — B is WHEN-class, arriving on `MEMORY.md is 25.8KB (limit:
24.4KB) — Only part of it was loaded`, while A is HOW-class, arriving on a
decision being started. A merged line would have to be both kinds at once.

**Proposed: re-split along the moment seam, not merge 2 into 1.**

- The A class moves into `memory-writing`. Rubric question 8 stops being a
  pointer and becomes the rules themselves, so an agent writing a fact gets the
  line rules without a second lookup.
- `index-compaction-triggers` keeps the B class and needs no rename — the name
  becomes accurate rather than aspirational. It links `memory-writing` for the
  authoring rules a sweep also needs.
- Index effect is approximately zero, as this file's own 39-byte measurement
  predicts. This is a merge for routing.

**Consequence for entry 3.** Proposal 3(c) — an index line carries the symptom a
session arrives holding, never the diagnosis it will only recognise after
reading — is A class. It lands wherever the A class lands.

### 4b · Both convert to gitlore skills, which supersedes the re-split

Two claims from my human partner: correct authoring would have prevented the
need for index compaction; and granting an imperfect world, compaction belongs
with authoring, both as gitlore skills.

**On the first.** Right about this store, and about the pass that hurt: the
32,405 → 24,316 B trim was self-inflicted, and the measured wins — 24
acted-inline lines out of the index, a single 3.3 KB project-state line — were
authoring defects, lines that were never index material. Byte-driven trimming
exists only because bad lines were shipped.

What survives correct authoring is **retirement**, which is driven by the world
aging rather than by the line being wrong: a version-stamped observation, a
closed workstream, a tool no longer used. A perfectly authored fact about a
dead tool is still dead weight. The index is also O(N) against a fixed cap — at
a disciplined 180 B per line the cap binds at roughly 139 facts, against 100
today — so accumulation alone eventually forces the decision. Call that
curation rather than compaction and the claim holds; the knowledge does not
disappear, it narrows to *how to decide what to retire*, which is this pass.

The most load-bearing thing in the file is the prohibition, not the procedure:
trimming lines to hit a byte target is the wrong lever, and the levers are
relocate, retire, merge-for-routing. The auditor-brief machinery is only needed
by someone who ignored it.

**On the second.** It follows from `memory-writing`'s own ownership rule — a
body that reduces to "when doing X, do Y" belongs in the skill that fires at X,
and this body is "when writing a memory, do Y". gitlore ships `merge`, `push`,
`recall` and `resolve`; nothing owns authoring or curation, which is a gap in
the plugin's own surface rather than a memory to keep.

It also supersedes the A/B re-split above. Half that argument was about index
routing — two trigger kinds, one line unable to be both. Off the index, that
constraint disappears and the asymmetry argues for progressive disclosure
instead: A in `SKILL.md`, B in `references/`.

**The numbers make it the largest lever in the store.** The two index lines are
1,459 B. Removing them takes the index from 26,219 B to 24,760 B — under Claude
Code's 24,986 B loader cap and under gitlore's 25,600 B advisory budget. This
one move clears the overflow that motivated the pass, against 39 B for three
merges and 3,491 B for 24 relocations. Coupling is nearly nil: 8 inbound
`[[links]]` across 4 files, 5 of them between the two files themselves, leaving
3 external references in `gitlore-tier-merge-direction` and
`gitlore-tier-index-budget`.

**Conditions on the conversion.**

- **The descriptions must be short, and the hooks are what make that safe.**
  Skill descriptions are injected every session exactly as index lines are, so
  carrying the index line's routing surface into the description is a lateral
  move — it buys only escape from the silent-truncation cap, the same
  accounting relocation to `shared-claude.md` gets. Both triggers are
  computable (a write under `memory/`; the budget check gitlore already runs),
  so neither description needs routing surface at all: purpose-first and enough
  for deliberate invocation ([[skill-description-purpose-first]]). Two ~150 B
  descriptions against 1,459 B of index nets ~1.15 KB off every session.
  Shipping the skills without the hooks gives the lateral move plus pressure to
  write long descriptions to preserve routing, which is no gain.
- **What a hook can actually do.** Nothing forces a tool call. A `PreToolUse`
  hook injects `additionalContext`, and a payload over roughly 2 KB is spilled
  to a file with only the head inlined, so an 11 KB body cannot be injected.
  The hook carries a compact directive at the moment of the write and the skill
  body carries the rules — a pointer arriving unmissably at the right moment,
  which is what beats index recall.
- The design decision belongs in `docs/design.md`, not in a memory.
- Entries 1, 3 and 4 and `design-doc-writing` all resolve to verdict
  **plugin** together, as the deferred question anticipated.

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
