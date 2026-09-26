# ddaanet memory review

Working ledger for a pass over the `memory/ddaanet/` facts, ordered by index
line size, largest first. Each entry records the verdict against the
`gitlore:memory-writing` rubric and my human partner's decision. An entry whose
ruling has been applied leaves the ledger; git history holds it.

**The queue is empty.** Every entry the pass opened is ruled and applied, so
what remains below is the measurement and the one question the pass could not
settle. The file itself is finished work and can go whenever the open question
lands somewhere durable.

Index: 21,529 B across 67 pointer lines (66 ddaanet + 1 project), 68 ddaanet
fact files, against Claude Code's ~24,985 B loader cap — inside it. Two of those
files carry no index line by design: they are the siblings of the
`frontmatter-hooks-two-silent-gates` hub, reachable by path once the hub is
read. This pass bought routing, not headroom; the structural question is
`2026-08-27-memory-index-budget-decision.md`, and both governing texts forbid
shortening a line to hit a byte target.

Verdict vocabulary: **keep** (save as written) · **update** (edit body or index
line) · **merge** (fold into another fact) · **retire** (delete) · **relocate**
(to `shared-claude.md` or a repo `CLAUDE.md`) · **plugin** (becomes a skill,
feature request or bug report). A fact converts to a plugin artifact only when
gitlore owns the moment it fires at; guide shape alone is not the criterion.

## What the pass settled

- **A fact's halves fire at different moments, and §2's owner test applies per
  section rather than per file.** Two entries resolved that way: the half a
  `craft` skill already asserts went to craft as a brief against the sentences
  asserting it, and the symptom-keyed residue stayed in the store under a name
  matching its trigger. Relocation is not all-or-nothing.
- **Index-line size does not select for an over-cap body.** The queue was
  ordered by line size and the two over-cap files it found were coincidence, so
  `wc -c` against 4096 belongs at every entry. `sandbox-effects` is the standing
  exception at 35 KB: its symptom map lands inside the first 4096 B, so recall
  routes the reader and degrades rather than breaking.
- **A file past the cap becomes a hub plus siblings, not a shorter file.**
  `frontmatter-hooks-two-silent-gates` is the worked example: the hub keeps the
  index line, the trigger and a symptom → file map, and each gate moved to its
  own file beside it. The split costs about 650 B of duplicated frontmatter and
  buys a body recall actually delivers.
- **The synced `description:` charges a routing line twice** — once in the
  capped index, once inside the fact's own 4096 B. A 670-character line leaves a
  frontmatter block near 800 B, a fifth of the budget before a word of body.
  `skills/memory-writing/SKILL.md` §4 now says so, since §7 forbids the obvious
  reading that the line should get shorter.
- **A retirement into a shipped skill is an extraction**, and the checklist for
  it belongs to the moment gitlore owns: `commands/index-audit.md` §2, under the
  Retire lever. `extracting-memory-into-skills` left the store for it.

## Open

- Whether constrained generation (the skill quoted before facts are drafted, as
  precompact reads it) or unconstrained-then-review (the FR11 gate after the
  drafts exist, as handoff reads it) produces better facts. `just evals` can
  settle it; the two arms are split by flow rather than held apart, so a
  comparison has to control for that or run both placements within one flow.
