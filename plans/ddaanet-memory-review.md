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
| 1 | 867 | `memory-writing` | plugin | done — `gitlore:memory-writing` skill, shape in 4c |
| 2 | 760 | `sandbox-effects` | update (relocate + merge out) | pending |
| 3 | 691 | `green-is-not-evidence` | update (index line) | pending |
| 4 | 590 | `index-compaction-triggers` | plugin | done — skill + `/gitlore:index-audit`, shape in 4c |

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

- **The descriptions must be short.** Skill and command descriptions are
  injected every session exactly as index lines are, so carrying the index
  line's routing surface into a description is a lateral move — it buys only
  escape from the silent-truncation cap, the same accounting relocation to
  `shared-claude.md` gets. Both triggers are computable, so neither description
  needs routing surface at all: purpose-first and enough for deliberate
  invocation ([[skill-description-purpose-first]]).
- **What a hook can actually do.** Nothing forces a tool call. A `PreToolUse`
  hook injects `additionalContext`, and a payload over roughly 2 KB is spilled
  to a file with only the head inlined, so a 14 KB body cannot be injected. A
  hook carries a compact directive at the moment of the write; the skill body
  carries the rules.
- The design decision belongs in `docs/design.md`, not in a memory.
- Entries 1 and 4 resolve to verdict **plugin**. The settled shape is 4c.

### 4c · The settled shape

**Two artifacts.**

- **`gitlore:memory-writing`**, a skill: `memory-writing` whole, plus the
  trigger-writing half of `index-compaction-triggers`. What a fact says, whether
  it should exist at all, which tier it lands in, and whether its index line
  routes.
- **`/gitlore:index-audit`**, a command, manual only: the store-wide pass — the
  two budgets and the loader cap, before-and-after token counts, the two
  adversarial auditor briefs, the plain-word sweep, and the whole-submodule
  frontmatter diff.

`index-compaction-triggers` does not survive as a unit, so the naming problem dissolves
with it: "compaction" named the lever its own body forbids, and "triggers"
named the authoring concern that moves into the skill.

**The seam runs differently than the A/B split above.** The file is a trigger
doctrine — an index line's only job, the WHEN/HOW/acted-inline classification,
the failure has a direction, count tokens index-wide, never under-trigger, sweep
plain words because bare identifiers carry routing weight. Budgets and the cap
are the occasion that puts triggers under attack, not the subject. Redirection
to CLAUDE.md and to skills belongs to `memory-writing`'s *What another artifact
already owns*; the relocation section here reaches the same destination by a
different test — no lookup step, so a routing table is the wrong surface — and
the two get stated once, in the skill.

**Gitlore owns one prompt surface inside handoff, and it lands at a different
point in each flow.** The approval clause file,
`reference/memory-approval-clause.txt`, is pinned to `git config
gitlore.memoryApprovalClauseFile` by `scripts/cc-hooks/session-start.sh` and
`scripts/install/write-settings.sh`. handoff resolves the key and reads the file
in `scripts/_checkpoint_lib.py:49-64`, then quotes it inside the directive
`memory_directive()` emits whenever the memory submodule is dirty. handoff's
design doc names it as the whole of the coupling — "two IPC filenames plus one
advertised `git config` key … so the wording has one owner instead of a copy per
consumer. Never gitlore internals" — so it is an advertised contract, and its
content is gitlore's to change.

**Where it lands is not uniform, and handoff has a standing decision about
precisely this.** *A directive is correct only where in the turn it lands*:
handoff runs its checkpoint in the same turn as the writes, so its directive
arrives **after** the memory files exist, while **precompact reads its directive
before it writes**. The `with-commit`/`without-commit` mode is a different axis —
commit awareness, not flow — and does not bear on timing.

So one file already reaches both moments, split by flow: under **precompact**,
quoting `gitlore:memory-writing` gives constrained generation before the facts
are drafted; under **handoff**, the same text is read after the drafts exist, at
the moment the summary is composed.

That asymmetry is a hazard as much as an opportunity. handoff's decision ends
"shared prompt text is shared only where the flows agree", and a review pointer
in shared text does not agree: under handoff the clause is quoted *inside* the
instruction to summarize the changes and get approval, so a review that rewrites
a fact falsifies the summary being approved in the same breath. Review guidance
has to be ordered ahead of the summarize step or hosted elsewhere. A further
constraint from the same doc: "with nothing to approve, the wrap-up completes in
a single turn", and "any rebalancing of the gitlore seam must preserve both
halves" — so nothing added here may introduce a detection round-trip.

**The FR11 pre-commit gate is the unambiguous review surface.** It blocks the
parent commit and emits its own directive before any summary is composed, so
review-driven edits land ahead of the message rather than behind it. It fires
only when a parent commit follows.

**No index-size trigger.** A size threshold fires on a condition that can be
permanently true — the index is O(N) against a fixed cap, binding near 139 facts
at a disciplined 180 B per line — so it is a livelock rather than diminishing
returns, and it would fire at session start, before the task has begun. The
budget warning gitlore already emits is the right altitude: a notice a human
acts on.

**No write-time hook in the first cut.** Gitlore already reaches the pre-write
moment through precompact, so a `PreToolUse` deny on writes under `memory/` is
not the only route to constrained generation, and it is the expensive one — a
turn on every session that writes memory. Both arms of the open question are
reachable by placing text in surfaces that already exist.

That also means the open question does not get a clean experiment for free: the
arms are split by flow rather than held apart deliberately, and precompact and
handoff differ in more than directive placement. A comparison has to control for
that, or run both placements within one flow.

**A command is not free, which changes the accounting and not the verdict.**
`gitlore:install` is a command with no `skills/` directory and still appears in
the injected list at <20 tokens; `gitlore:add-tier` at ~70. Plugin commands
carry their frontmatter description into every session exactly as skills do, so
the lever is description length rather than the skill-versus-command choice.
Index 26,327 B − 1,459 B = 24,868 B, under Claude Code's 24,986 B loader cap by
118 B and under gitlore's 25,600 B advisory, against ~140 B of new always-on
description. That margin is what keeps retirement live.

**What condensation cuts.** The bulk of both files is evidence rather than
worked examples, and it is there because a memory has no standing with a reader
who was not present. Three ways:

- numbers that make a counterintuitive rule survive an agent's disagreement stay
  inline, compressed to the figure — merging nets ~0, body rewrites moved the
  index by exactly zero, the 32,405 → 24,316 B trim whose repairs consumed
  almost the whole 8 KB it bought;
- rules that stand alone stay bare — present tense, strip deictics, no incident
  no entry;
- provenance — dates, session attributions, which repo, who said what — is cut
  rather than relocated, and it is most of the 30,201 B.

That leaves `references/` with nothing to hold. The one reusable artifact is the
pair of auditor briefs, which belong to `/gitlore:index-audit` as what it
dispatches with. Stripped evidence goes to `docs/design.md` and the changelog,
alongside the design decision. Estimate to verify while writing: ~6-8 KB
combined, against 30,201 B today.

**Only a fact with a gitlore-owned moment converts.** The conversion works
because gitlore owns a gate firing at memory-authoring time.
`green-is-not-evidence` fires at "about to accept a green test" and
`design-doc-writing` at "about to write a design doc"; gitlore owns neither
moment, so both stay memories, and entry 3's index-line rewrite stands on its
own. Guide shape is not the criterion — an owned trigger is.

**Open.** Whether constrained generation or unconstrained-then-review produces
better facts, which `just evals` can settle and which the first cut deliberately
leaves open.

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
