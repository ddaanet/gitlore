# ddaanet memory review

Working ledger for a pass over the `memory/ddaanet/` facts, ordered by index
line size, largest first. Each entry records the verdict against the
`gitlore:memory-writing` rubric and my human partner's decision. An entry whose
ruling has been applied leaves the ledger; git history holds it.

Index now: 27,363 B across 100 lines (99 ddaanet + 1 project), 100 ddaanet fact
files, against Claude Code's ~24,985 B loader cap. This pass buys routing, not
headroom: the structural question is
`2026-08-27-memory-index-budget-decision.md`, and both governing texts forbid
shortening a line to hit a byte target.

Verdict vocabulary: **keep** (save as written) · **update** (edit body or index
line) · **merge** (fold into another fact) · **retire** (delete) · **relocate**
(to `shared-claude.md` or a repo `CLAUDE.md`) · **plugin** (becomes a skill,
feature request or bug report). A fact converts to a plugin artifact only when
gitlore owns the moment it fires at; guide shape alone is not the criterion.

## Queue

Next entries by current line size. `sandbox-effects` (987 B) and
`green-is-not-evidence` (691 B) are ruled and applied; their lines have since
grown by addition, not by drift, and are not re-opened.

| # | Bytes | Fact | Verdict | Decided |
|---|-------|------|---------|---------|
| 5 | 810 | `hook-output-channels` | retire — owned by plugin-craft | 2026-09-21: mechanics already in `plugin-craft:hook-authoring`, wording in `craft:directive-writing`; the ANSI-rendering remainder and the retirement itself are briefed to plugin-craft, the plugin incorporating the fact |
| 6 | 550 | `hook-input-schema` | | |
| 7 | 529 | `design-doc-writing` | | |
| 8 | 501 | `skill-bundled-scripts` | | |
| 9 | 492 | `git-stderr-and-parsing` | | |
| 10 | 472 | `classifier-denied-self-config` | | |
| 11 | 452 | `bats-shellcheck-gotchas` | | |
| 12 | 445 | `posttooluse-print-mode` | | |

## Carried notes

- `genuine-red-not-missing-sut`'s third section, interface contracts one per
  line, fires at plan-writing rather than test-writing and sits beside
  `plan-contracts-not-full-code` and `honest-line-count-caps`. Weigh a
  relocation at its entry.
- `green-is-not-evidence` has no skill home: gitlore does not own "about to
  accept a green test", `superpowers:test-driven-development` covers three of
  its thirteen shapes, and edify spreads test-writing over three components with
  no one firing at that moment. Whether edify wants a test-evidence component is
  an edify design question, outside this repo's write scope.

## Open

- Whether constrained generation (the skill quoted before facts are drafted, as
  precompact reads it) or unconstrained-then-review (the FR11 gate after the
  drafts exist, as handoff reads it) produces better facts. `just evals` can
  settle it; the two arms are split by flow rather than held apart, so a
  comparison has to control for that or run both placements within one flow.
