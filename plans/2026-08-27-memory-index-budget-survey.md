# Memory index budget survey — candidate list

Read-only survey per team-lead brief. Decides nothing, changes nothing.

`memory/MEMORY.md` is 27722 B; Claude Code's loader truncates at ~24985 B
(24.4 KB) — need to shed **≥ 2800 B** without losing a routable trigger.

Method followed: read `memory/ddaanet/index-compaction-triggers.md` and
`memory/ddaanet/memory-writing.md` in full, read `shared-claude.md` and both
`CLAUDE.md` files, then read the memory files behind ~20 sampled index lines
(the largest lines, plus every line that read as acted-inline or as
topically clustered with another). This is a sample, not an exhaustive
per-file read of all 103 entries — see "Coverage" at the end.

## Governing constraints from the two spec files

- Shortening a line is not a lever — it strips the literals routing depends
  on. Only relocation (acted-inline → `CLAUDE.md`/`shared-claude.md`) and
  retirement remove real bytes; merging measured near-zero (0.16% on one
  pass, one of three merges landed *larger*).
- A prior compaction pass already relocated 24 acted-inline lines
  (−3,491 B index / +4,305 B `shared-claude.md`), which is why
  `shared-claude.md` is already 14 KB+ and the index is still over budget
  again at 27,722 B. **The acted-inline well is largely dry**: I did not
  find a clean, undamaged acted-inline candidate in the sample — every
  standing-default-shaped entry I checked (`no-speculative-rules`,
  `directive-states-acts`, `plan-length-matches-work`) turns out to fire at
  a real, specific authoring/planning moment (writing a new skill rule,
  writing a script-emitted directive, starting a plan doc), not on every
  turn, so index placement is correct per the WHEN/HOW/acted-inline test.
- The spec's own worked example explicitly warns against exactly the
  mistake I nearly proposed: retiring the tmux cluster (`cc-tui-tmux-driving`,
  `tmux-test-isolation`) as a "finished workstream" was already tried once,
  found wrong (two live skills still depend on them), and reversed. I confirmed
  both are still live-relevant and did **not** put them on this list.

## Candidates, ranked bytes-freed / risk (best first)

### 1. Merge: `preflight-excludes-memory-submodule` + `gitlore-memory-administration-no-parent-commit`

- Line 62 (372 B):
  `- [preflight excludes the memory submodule](ddaanet/preflight-excludes-memory-submodule.md) — `
  M memory` in the parent's `git status
  --porcelain` is the resting state, not a dirty tree: a release-readiness gate like `ddaa:preflight` must not abort on it, since the parent's pre-commit hook commits and gates memory into the release commit; other dirty paths still block`
- Line 70 (316 B):
  `- [gitlore memory administration needs no parent commit](ddaanet/gitlore-memory-administration-no-parent-commit.md) — administering memory alone (merge/trim/curation, no parent-repo content change): write the approved `.claude/gitlore-memory-message` and stop, don't manufacture a parent commit to force it through`
- Category: (a) overlapping pair / (d) merge candidate.
- Evidence: both files' "Why" sections state the *same* mechanism — a dirty
  `M memory` is the resting state because nobody commits inside the
  submodule and the parent's pre-commit hook is what clears it — and both
  fire at the identical moment: an agent looking at `M memory` in
  `git status --porcelain` and deciding what to do about it. One file
  applies the mechanism to a gate script (`ddaa:preflight`), the other to a
  manual "do I need `git commit` on the parent" decision. This matches
  `memory-writing.md`'s own test verbatim: "Files with distinct HOW content
  and a single shared WHEN are one memory that was split by topic."
- Bytes freed: modest — merging buys mostly the duplicated "Why" prose, not
  the triggers. Estimate ~100–150 B net (the guide's own three-merge
  experiment averaged 13 B/merge; this pair has more duplicated
  explanatory prose than that experiment's, so I estimate a little above
  average, not at it).
- Risk: LOW if the merged line keeps every literal from both —
  `` ` M memory` ``, `git status --porcelain`, `ddaa:preflight`,
  `.claude/gitlore-memory-message`, "no parent commit". Losing any one
  misroutes the agent that arrives holding that specific symptom.

### 2. Merge/retire: `no-doc-history-references` into `design-doc-writing`

- Line 87 (149 B):
  `- [No doc-history references](ddaanet/no-doc-history-references.md) — specs never reference their own previous versions; keep standalone rejections`
- Line 10 (460 B, file itself is 282 lines): `design-doc-writing.md`'s
  "Superseding a decision" section ("Cut the museum narrative... Old sections
  stay, with a terse superseding *pointer*...") and "Present-tense standing
  truth" section ("Phrasings like 'no longer true'... read as museum-keeping...
  Git history already preserves what changed") state the same rule
  `no-doc-history-references.md` states, for the same artifact class
  (specs/design docs), with equal or greater specificity, plus a worked example
  (`docs/changelog/2026-05-19-original-activation-and-loading.md`).
- Category: (a) duplicate/overlap, content substantially contained in the
  larger file.
- Bytes freed: 149 B if the standalone line is dropped outright; realistically
  less, because the design-doc-writing index line does **not** currently
  carry the "previous version" / "rejected alternatives kept standalone"
  literals — it says "dated rationale vs present-tense truth" which is close
  but not identical. Net after adding ~20–30 B of trigger words to line 10:
  **~120 B**.
- Risk: MEDIUM. `no-doc-history-references.md`'s distinctive literals
  ("smoking gun", "(good) not (bad)" comparisons, "keep standalone
  rejections") are concrete example phrasing that doesn't survive a naive
  drop — the merged line must explicitly add "keep rejected-alternative
  entries standalone, scrub 'previous version of this doc' language" or an
  agent revising a spec who is *not* touching `docs/design.md` specifically
  (e.g. editing a frozen `plans/` doc) may not think to consult
  `design-doc-writing`, since its title reads design-doc-specific.

### 3. Rejected candidate, recorded for completeness: `no-transition-special-cases`

- Line 43 (149 B):
  `- [no transition special cases](ddaanet/no-transition-special-cases.md) — handling a version transition in your own tooling with a user base of one`
- Looked like an acted-inline candidate for folding into `shared-claude.md`'s
  existing "No compat aliases, no internal back-compat" bullet (Code
  section) — the file's own "Why" says "Same instinct as refusing compat
  aliases."
- **Not recommending.** The two rules cover different failure shapes: "no
  compat aliases" is about *removing a symbol* and patching callers; this
  fact is about *not writing a diagnostic branch* that enumerates causes
  ("installed before this session / updated since / the pinned path
  moved"). Folding it into the compat-aliases bullet either loses that
  distinct trigger shape or costs as many bytes in `shared-claude.md` as it
  frees from the index — exactly the wash the spec document measured
  (−2,200 B index / +2,692 B `shared-claude.md` on the last relocation
  pass). Listed so the team lead doesn't re-derive and re-reject the same
  idea.

## Running total

| # | Candidate | Bytes freed (est.) | Cumulative | Risk |
|---|---|---|---|---|
| 1 | preflight + admin-no-parent-commit merge | ~125 | ~125 | Low |
| 2 | no-doc-history-references → design-doc-writing | ~120 | ~245 | Medium |

**Target not reached.** ~245 B identified against a ~2800 B requirement —
roughly 9% of the gap, from a ~20-file sample out of 103 entries.

## Why the shortfall, and where to look next

Two structural reasons the easy levers are exhausted in this store
specifically:

1. **Relocation already ran once** (24 lines, 2026-08-01 per
   `index-compaction-triggers.md`) and the survivors that still read as
   "possibly acted-inline" turned out, on reading the file, to fire at a
   specific authoring moment rather than unconditionally — meaning they were
   correctly left in the index the first time.
2. **This store's own governing memory is itself heavy**: `memory-writing.md`
   (1022 B index line, 262-line file) and `index-compaction-triggers.md`
   (590 B index line) total ~1.6 KB of the 27.7 KB and are both meta-rules
   for administering this very store — retiring or shrinking either is
   self-defeating for a compaction pass and I did not consider them
   candidates.

To close the remaining ~2550 B, the highest-expectation next step is a
**full retirement sweep**: grep every distinctive literal in the ~85
entries I did not open against `docs/`, `scripts/`, `tests/` in *every*
repo that mounts the `ddaanet` tier (not just gitlore — retiring a
cross-repo tier fact needs the consuming repos checked, per
`memory-writing.md`'s tier-relevance test), looking specifically for a
mechanism that has since been superseded (a flag that shipped GA, a tool
version bump past a workaround's applicability). I did not have evidence
either way for the two flag-gated entries I flushed on (`Todo tool is
flag-gated`, `tengu_vellum_ash`) — confirming current flag state needs a
live probe, out of scope for this text-only pass.

## Coverage

Files actually read: `index-compaction-triggers.md`, `memory-writing.md`,
`shared-claude.md`, both `CLAUDE.md`s, `no-transition-special-cases.md`,
`bundle-memory-with-source.md`, `preflight-excludes-memory-submodule.md`,
`gitlore-memory-administration-no-parent-commit.md`,
`plan-length-matches-work.md`, `no-speculative-rules.md`,
`directive-states-acts.md`, `remove-cleanly-no-vestigial.md`,
`no-doc-history-references.md`, `design-doc-writing.md`,
`plan-contracts-not-full-code.md`, `honest-line-count-caps.md`,
`spec-contract-size-predicts-pr-size.md`. Byte-measured every line in
`MEMORY.md` via `awk '{print length}'`. Grepped `docs/` for gitlore-mechanism
literals (`gitlore-memory-message`, `placeholder`, tier-merge terms, index
budget terms) to check retirement evidence for gitlore-specific ddaanet
entries (67–70) — concluded that overlap with gitlore's *own* docs is not
retirement evidence for a cross-repo tier fact, since other repos mounting
`ddaanet` install gitlore as a plugin without vendoring its `docs/`, so the
tier fact is their only source; noted but not listed as a candidate.
