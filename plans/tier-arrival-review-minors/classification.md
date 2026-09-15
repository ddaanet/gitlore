# Classification: tier-arrival-review-minors

Source: the 21 Minor findings of
`plans/unadoptable-tier-arrival/reports/deliverable-review.md` (implicit
bundling). The Major is out of scope, tracked in `.claude/handoff-todo.md`.

Composite classification: **Moderate** (non-prose path), because several items
change logic paths. Work type: Production.

| # | Item | Behavioral code | Class | Destination |
|---|---|---|---|---|
| 1 | Unrepairable arm omits non-carrier problems | Yes: new argument, new output | Moderate | production |
| 2 | Transient repair arms: no problem list, wrong remedy | Yes: per-arm remedy | Moderate | production |
| 3 | Walk-back says `live` keeps the arrival when it holds the repair | Yes: new parameter | Moderate | production |
| 4 | Behind-arm retry push reports a race as "not divergence" | Yes: classify the retry error | Moderate | production |
| 5 | A take mid-push repairs a tier already pushed | Yes | Defect (unprobed, needs reproducing) | production |
| 6 | Unterminated last duplicate dropped, survivor loses newline | Yes | Defect (probed, cause known) | production |
| 7 | Killed take leaves a scratch directory in the tier gitdir | Yes: scratch location | Moderate | production |
| 8 | Comment verb "walk back from" | No | Simple | production |
| 9 | `(K3)` outline id in test header | No | Simple | production |
| 10 | Attribution test lacks a suffix decoy | No (test only) | Simple | production |
| 11 | Unrepairable test: worktree prefix, memory HEAD | No (test only) | Simple | production |
| 12 | S1 abort split across entry points | No (test only) | Simple | production |
| 13 | Three untested rule paths | No (test only) | Simple | production |
| 14 | Merger never states rule 1 | No | Simple | agentic-prose |
| 15 | Merger/resolve "otherwise" misreads pre-landing exits | Yes: harness line for two arms | Moderate | production + agentic-prose |
| 16 | git-hooks.md ambiguous dirtiness clause | No | Simple | investigation |
| 17 | tier-arrival-repair.md opening tense | No | Simple | investigation |
| 18 | tier-stores.md dangling "instead" | No | Simple | investigation |
| 19 | Node count "four" | No | Simple | investigation |
| 20 | Changelog dangling "other" | No | Simple | investigation |
| 21 | commit-gate.md off-pin tier "edit" | No | Simple | investigation |

- **Implementation certainty:** High for everything except item 5, where it is
  Moderate until the race is reproduced.
- **Requirement stability:** High; each finding names its anchor and the defect.
- **Evidence:**
  - The code was read at `scripts/lib/resolve.sh:1370-1440, 1850-2040`,
    `scripts/lib/index-compose.sh:266-270, 395-450` and
    `scripts/resolve.sh:100-140, 300-316`.
  - Recall: the unadoptable-tier-arrival dispatch constraints and
    `craft:directive-writing` for message wording.
- **Routing:** everything runs as one job, per my human partner's instruction.
  The Moderate and Defect items get TDD phases; the Simple items batch into
  inline phases.
