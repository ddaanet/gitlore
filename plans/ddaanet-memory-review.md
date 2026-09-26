# ddaanet memory review

Working ledger for a pass over the `memory/ddaanet/` facts, ordered by index
line size, largest first. Each entry records the verdict against the
`gitlore:memory-writing` rubric and my human partner's decision. An entry whose
ruling has been applied leaves the ledger; git history holds it.

Index: 22,546 B across 70 lines (69 ddaanet + 1 project), 69 ddaanet fact files,
against Claude Code's ~24,985 B loader cap — inside it, with the retirement
waves into `craft`, `plugin-craft` and `shell-scripting` having taken the store
there. This pass buys routing, not headroom: the structural question is
`2026-08-27-memory-index-budget-decision.md`, and both governing texts forbid
shortening a line to hit a byte target.

Verdict vocabulary: **keep** (save as written) · **update** (edit body or index
line) · **merge** (fold into another fact) · **retire** (delete) · **relocate**
(to `shared-claude.md` or a repo `CLAUDE.md`) · **plugin** (becomes a skill,
feature request or bug report). A fact converts to a plugin artifact only when
gitlore owns the moment it fires at; guide shape alone is not the criterion.

## Queue

Next entries by current line size. `sandbox-effects` (1163 B) and
`green-is-not-evidence` are ruled and applied; their lines have since grown by
addition, not by drift, and are not re-opened. A number is never reused: 6–12
named facts the retirement waves took before this pass reached them, and the
queue resumes at 13.

| # | Bytes | Fact | Verdict | Decided |
|---|-------|------|---------|---------|
| 5 | 607 | `hook-output-channels` | retire — owned by plugin-craft | 2026-09-21: mechanics already in `plugin-craft:hook-authoring`, wording in `craft:directive-writing`; the ANSI-rendering remainder and the retirement itself are briefed to plugin-craft, the plugin incorporating the fact |
| 6–12 | — | `hook-input-schema`, `design-doc-writing`, `skill-bundled-scripts`, `git-stderr-and-parsing`, `bats-shellcheck-gotchas`, `posttooluse-print-mode` | retired before review | retired into `plugin-craft:hook-authoring`, the `craft` skills and `shell-scripting:shell-gotchas` by the dedicated extraction waves; `classifier-denied-self-config` was the seventh and re-enters below |
| 13 | 749 | `markdown-formatter-choice` | relocate the doc-authoring half to craft, keep the gate-wiring residue | 2026-09-26: applied. The file was 4756 B, so recall silently dropped the 660 B its own line advertised. The tool choice and the render-diff method back two claims craft already ships — `splitting-an-oversized-doc.md` asserts rumdl changes no rendering with no evidence, and `contracts-and-size.md`'s "wrap then measure" is wrong under rumdl's default `reflow-mode` — so they went to `craft/inbox/2026-09-26-brief-rumdl-claims-lack-their-evidence.md`. The residue is `markdown-reflow-gate`, renamed for the moment it fires at: a gate misbehaving, not a doc being written |
| 14 | 679 | `cc-bash-background-no-duration-cap` | | |
| 15 | 634 | `git-config-multivalued-read` | | |
| 16 | 604 | `classifier-denied-self-config` | | |
| 17 | 597 | `frontmatter-hooks-two-silent-gates` | | |
| 18 | 505 | `cc-nested-subagent-spawning` | | |
| 19 | 454 | `uv-direnv-venv` | | |
| 20 | 432 | `extracting-memory-into-skills` | | |

## Carried notes

- `craft:test-discipline` is the skill home the pass could not find for
  `green-is-not-evidence`: its `references/vacuous-green.md` owns "about to
  accept a green test", and `references/genuine-red.md` took the interface
  contracts section of `genuine-red-not-missing-sut`. Both facts, along with
  `plan-contracts-not-full-code` and `honest-line-count-caps`, left the store
  with the craft-seed wave, so neither note has an entry left to carry.
- Entry 13's defect is a class, not an instance, and the queue's ordering does
  not select for it: index-line size and file size are independent, so sorting
  by the line finds an over-cap body only by luck. Measured across the queue,
  `frontmatter-hooks-two-silent-gates` (5763 B, entry 17) is over too, and
  `sandbox-effects` is at 35,247 B. Check `wc -c` against 4096 at every
  remaining entry.
- The synced `description:` compounds it: §7 makes the index line canonical and
  the frontmatter a copy, so a long line is charged twice — 877 B of
  `markdown-formatter-choice`'s 4096 B budget is its own description. The
  routing the line has to carry (§7 forbids trimming for bytes) is what shrinks
  the body recall can deliver, which is an argument for splitting early rather
  than for a shorter line.
- `sandbox-effects` is another session's work and is not touched by this pass.
  It carries §4's symptom map but not §4's remedy — sections still inline at
  35,247 B, so recall delivers the map and roughly one section of thirteen. The
  map lands inside the first 4096 B, so the reader is routed and can `Read` the
  file at the right heading: degraded rather than broken, with nothing
  signalling the truncation.
- Entry 13 is the shape for a fact whose halves fire at different moments: the
  half a `craft` skill already asserts goes to craft as a brief against the
  sentences that assert it, and the symptom-keyed residue stays in the store
  under a name matching its trigger. Relocation is not all-or-nothing, and §2's
  owner test applies per section rather than per file.

## Open

- Whether constrained generation (the skill quoted before facts are drafted, as
  precompact reads it) or unconstrained-then-review (the FR11 gate after the
  drafts exist, as handoff reads it) produces better facts. `just evals` can
  settle it; the two arms are split by flow rather than held apart, so a
  comparison has to control for that or run both placements within one flow.
