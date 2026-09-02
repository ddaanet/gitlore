# ddaanet index: design-moment facts, grouping and relocation

Follow-up to `plans/2026-09-02-recall-log-analysis.md`. That analysis found
the never-read set is not a type or an age but a trigger shape: facts whose
trigger is a design moment (an activity) rather than a token a tool result
can surface. This pass goes through all 99 ddaanet index lines, sorts each by
trigger shape, and for the design-moment set asks which project the lesson is
relevant to and which facts share one moment.

Read counts are total deliveries over the transcript corpus (2026-W30 to
W36). Relevance is judged from the fact body, not from which sessions read
it: the project the worked example comes from, and whether any other ddaanet
repo does the activity. The sibling mounts are claude-plugin-dev, cwd-safety,
edify, gitlore, handoff, micro, onekeys, prohibitions and shell-gotchas.
`ghmem` and the ledger are edify subprojects; SDD (subagent-driven
development) is a cross-repo practice named in shared-claude.

## Symptom-keyed facts: 52 lines, no change proposed

Claude Code mechanics, git, shell, sandbox, JSONL, plugin and gitlore
administration facts. Each hook carries an error string, a flag, a command or
an observable behaviour. Seven of these were never read because the index
line already answers the symptom (`cc-command-namespacing`,
`todo-tool-flag-gated`, `tmux-test-isolation`, `bang-shell-shared-cwd`,
`git-ext-transport`, `session-title-customtitle`, `cc-worktree-bash-guard`),
which is the index working as designed.

## Design-moment facts: 47 lines, in eight moments

### 1. Writing or reviewing a plan or spec

| fact | reads | example from |
| ---- | ----: | ------------ |
| plan-length-matches-work | 10 | gitlore |
| spec-enumerations-need-rederiving | 14 | general |
| plan-contracts-not-full-code | 4 | edify SDD |
| honest-line-count-caps | 6 | edify (line caps) |
| spec-contract-size-predicts-pr-size | 2 | edify (400-line PR cap) |
| no-doc-history-references | 2 | edify |
| reference-doc-scope | 2 | edify (mypy guideline) |
| test-with-live-data-before-designing | 1 | edify ledger |
| large-docs-review | 0 | gitlore |

One moment, nine facts, three of them explicit overrides to the superpowers
writing-plans skill. Proposal: one ddaanet fact, `plan-writing`, with a
section per rule, read at the writing-plans checkpoint. The two facts about
edify's line caps carry their edify-specific numbers to edify's own store and
leave a one-line general form ("a cap is soft; wrap, never cram") in the
merged fact. Index bytes held by the group: 1050.

### 2. Writing tests

| fact | reads | example from |
| ---- | ----: | ------------ |
| green-is-not-evidence | 35 | edify, general |
| genuine-red-not-missing-sut | 18 | edify |
| outside-in-tdd | 7 | general |
| test-the-invocation-path | 0 | gitlore |

Working: the three read facts are hubs the TDD checkpoint reaches.
`test-the-invocation-path` was never read because gitlore's CLAUDE.md states
it verbatim under Testing. Fold it into `green-is-not-evidence` as one more
fixture-satisfied shape, or retire it.

### 3. Writing prose, docs and directives

| fact | reads | example from |
| ---- | ----: | ------------ |
| design-doc-writing | 46 | general |
| directive-states-acts | 24 | general |
| uncram-prose-shapes | 1 | edify (line cap) |
| prose-voice-does-not-delegate | 1 | edify |
| imperative-form-scope | 1 | handoff |
| markdown-formatter-choice | 1 | toolkit decision |

`design-doc-writing` and `directive-states-acts` are checkpoint hubs and stay.
`uncram-prose-shapes` and `prose-voice-does-not-delegate` are one moment,
briefing a style edit, and both come from edify's line-cap regime: merge and
move to edify. `imperative-form-scope` is a skill-authoring rule: fold into
`skill-description-purpose-first`, which is that moment's hub (18 reads).
`markdown-formatter-choice` is a decision already embodied in the
claude-plugin-dev toolkit's rumdl pin: fold the one-line rationale into
`claude-plugin-dev`.

### 4. Preparing commits and review slices

| fact | reads | example from |
| ---- | ----: | ------------ |
| commit-bundling | 1 | gitlore, handoff |
| slice-history-forward-not-by-cherry-pick | 0 | edify ghmem |
| slice-uncommitted-tree-via-index | 0 | edify ghmem |

The two slice facts are one technique for one practice, review slices under
a PR cap, which only edify runs. Merge into one `review-slices` fact and move
it to edify. `commit-bundling` is general and stays.

### 5. Designing a guard, allowlist or validation

| fact | reads | example from |
| ---- | ----: | ------------ |
| guardrail-must-permit-real-commands | 5 | edify ghmem |
| harden-human-gates | 3 | gitlore |
| parse-dont-regex-structured-formats | 3 | edify ghmem |
| guard-reveals-singleton | 1 | general |
| guard-safety-visible-in-the-pattern | 0 | edify ghmem |
| detect-liveness-not-presence | 0 | edify SDD, handoff |

Three share the moment of writing or narrowing a guard:
`guardrail-must-permit-real-commands`, `harden-human-gates` and
`guard-safety-visible-in-the-pattern`. Merge into one `guard-design` fact
(590 index bytes today). The practice is cross-repo: cwd-safety and
prohibitions are guard plugins. `guard-reveals-singleton` keys on a review
finding's wording and `detect-liveness-not-presence` on a probe pattern, so
both stay as they are; `parse-dont-regex` is a code-review token and stays.

### 6. Data-model and scoring design

| fact | reads | example from |
| ---- | ----: | ------------ |
| no-code-for-impossible-cases | 4 | edify ghmem |
| ground-formulas-in-data | 1 | edify ghmem |
| shape-rules-are-not-duplication | 1 | edify ghmem |
| reconstructable-two-categories | 1 | edify ledger, handoff |
| provisional-values-not-provisional-code | 0 | edify ghmem |
| marginal-weakness-is-not-misweighting | 0 | edify ghmem |
| optional-means-source-can-omit | 0 | edify ledger |
| dont-bake-in-guarantees | 0 | edify ledger |

All eight are edify lessons. No other ddaanet repo builds scoring formulas
or a typed data model in Python. Two moments inside the group: a scoring
formula (`ground-formulas`, `provisional-values`, `marginal-weakness`: one
fact) and a data model or API surface (`optional-means`, `dont-bake`,
`shape-rules`, `no-code-for-impossible-cases`: one fact).
`reconstructable-two-categories` is a handoff-design lesson and belongs with
handoff's store. Move all to the owning project's store; re-promote a fact
to ddaanet the day a second repo hits its moment.

### 7. Writing a build recipe

| fact | reads | example from |
| ---- | ----: | ------------ |
| gate-cache-must-cover-every-check | 8 | edify, gitlore |
| justfile-gotchas | 2 | general |
| bash-prolog-common-foundations | 0 | edify |
| edify-python-standards | 0 | edify |

`bash-prolog-common-foundations` shares `justfile-gotchas`'s hook, "writing
a just recipe": merge into it. `edify-python-standards` names its repo in its
title and claims edify as the reference config for Python projects, of which
edify is the only one among the mounts: move to edify.

### 8. Changing your own tooling

| fact | reads | example from |
| ---- | ----: | ------------ |
| remove-cleanly-no-vestigial | 16 | general |
| no-transition-special-cases | 2 | gitlore |
| loose-generation | 0 | general |

`no-transition-special-cases` is one more thing not to leave behind when
changing tooling with a user base of one: fold into `remove-cleanly`.
`loose-generation` is a lone LLM-workflow design lesson with no project
example and no reads; it stays only if its description gains a trigger
("designing an agent step that must emit a constrained artifact"), else
retire.

Remaining design-moment facts that stay as they are, each with its own
recognisable moment or a token in the hook: `examine-evidence-drift` (7),
`perf-fix-check-parallelism-assumption` (1, keys on `--jobs`),
`verify-restart-before-structural-diagnosis` (1),
`transcripts-are-ground-truth` (1), `sdd-durable-state-across-compaction`
(1, SDD is cross-repo), `token-counting` (1), `cc-tui-tmux-driving` (5).

## Effect on the index

| action | lines out | lines in | index bytes freed |
| ------ | --------: | -------: | ----------------: |
| move to edify or handoff (moment 6, slices, style pair, python standards, cap specifics) | 15 | 0 | ~2380 |
| merge plan-writing (moment 1, after the cap split) | 7 | 1 | ~800 |
| merge guard-design | 3 | 1 | ~400 |
| fold singles into existing hubs (invocation path, imperative form, formatter, bash prolog, transitions) | 5 | 0 | ~1000 |
| total | 30 | 2 | ~4600 |

The ddaanet index is 26,617 bytes today against the ~24,985-byte loader cap.
This pass alone brings it under the cap with roughly 2,900 bytes to spare,
which changes the standing of the index-budget decision in
`plans/2026-08-27-memory-index-budget-decision.md`: curation can close the
gap once relocation is on the table, so the composition reorder is no longer
forced by the budget alone.

The moved facts do not vanish from the moment: edify's own MEMORY.md carries
them, and edify sessions are where the moment occurs. What is lost is the
chance that a second repo hits the same moment and finds nothing; the
re-promotion rule covers that at the cost of one miss.
