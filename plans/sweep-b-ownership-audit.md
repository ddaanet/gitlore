# Sweep B — ownership audit of the ddaanet tier

Classification only. Nothing was edited, and no retirement was executed.
Scope: the 100 fact files in `memory/ddaanet/` (`MEMORY.md` and
`shared-claude.md` excluded). The plan said 99; the tier has grown by one.

## The finding that decides most rows

**Only a tier-wide owner counts.** A ddaanet fact is reachable from every
repository that mounts the tier, so it is owned only by something equally
reachable: `memory/ddaanet/shared-claude.md`, an installed plugin skill, or a
hook. gitlore's `CLAUDE.md`, `docs/design.md` and `docs/changelog.md` are
project-local — a fact they cover is still unowned in every *other* ddaanet
repo, and retiring it there would strand them.

This matters because project-local coverage is where the overlap actually is.
`docs/design.md` restates `hook-cannot-inject-tool-calls` almost in full
(design.md:693 carries the `injectToolCall`/`requestTool`/`forceRead`/
`forceToolUse` zero-occurrence probe, the 15.6KB→2KB truncation, and the
file-read-ledger `Edit` failure). It is still not an owner.

**A third class is overrides, not duplicates.** Three facts exist because an
installed skill states the contrary rule, each confirmed against the line that
states it:

- `skill-description-purpose-first` vs `writing-skills/SKILL.md:150` —
  "**CRITICAL: Description = When to Use, NOT What the Skill Does**".
- `plan-contracts-not-full-code` vs `writing-plans/SKILL.md:133-135` — which
  lists "Write tests for the above (without actual test code)" as a defect and
  requires "code blocks … for code steps".
- `imperative-form-scope` vs `skill-development/SKILL.md:160` — "Write the
  entire skill using **imperative/infinitive form** … not second person".

Retiring any of these restores the rule it was written to beat, so they are
structurally un-retirable while those skills ship as they are.

## Consequence for the compaction

**Sweep B is not the long-run compaction strategy, but it clears the immediate
cliff.** The plan extrapolated ~20 retirements from a 5-file sample; the audit
finds **2 retire + 2 relocate**. The tier-wide-owner rule is what collapses the
estimate: the sample's candidate was judged against whatever text covered it,
not against text every ddaanet repo can reach.

Four lines is far short of ~25 entries, yet the byte effect is out of proportion
to the count, because two of the four are among the longest lines in the index:

| | bytes |
| --- | --- |
| `shell-gotchas-on-review` | 244 |
| `run-the-gate-not-a-suite-subset` | 197 |
| `skill-vs-command` | 172 |
| `verify-session-root` | 141 |
| **freed** | **754** |

That moves the index from 24722 bytes to 23968 — headroom against the
~24985-byte loader cutoff goes from 263 bytes to 1017, roughly 4×. So the
forcing deadline lifts, and the tier-wide-vs-sub-scoping fork can be decided on
its own merits instead of under byte pressure. It does not go away: at ~190
bytes per new entry, 1017 bytes is about five more facts.

## Verdicts

### retire — 2

| Fact | Owner | Grep confirming coverage |
| --- | --- | --- |
| `shell-gotchas-on-review` | `shell-scripting:shell-gotchas` own `description:` | `sed -n 1,6p …/shell-gotchas/SKILL.md` → "should be used when writing, editing, **reviewing**, or debugging shell scripts … `.bats` tests, git hooks, Makefile recipes". The fact is a workaround for a trigger that named only authoring; the shipped trigger now names review, `.bats` and hooks explicitly. |
| `run-the-gate-not-a-suite-subset` | `shared-claude.md:43` | `grep -Fn "precommit gate before committing"` → "**Run the repo's precommit gate before committing**, unprompted — it is a required step, not a suggestion to float." Acted-inline: the always-on line fires before any lookup could. Retiring loses the rationale (blast-radius guess, gate caching economics); the act survives. |

### relocate — 2

Both are acted-inline with no lookup moment, and both are currently stated in
gitlore's **project** `CLAUDE.md` only — so the act is missing from every other
ddaanet repo. Relocating to `shared-claude.md` frees the index line and fixes
that gap; the project `CLAUDE.md` line then goes as a Class A deletion.

| Fact | Current project-local statement | Note |
| --- | --- | --- |
| `verify-session-root` | `CLAUDE.md:31` "After a compaction, check `PWD`, `CLAUDE_PROJECT_DIR` and the gitStatus block" | Cannot be looked up after acting wrongly — the 2026-07-20 incident ran four commits into the wrong repo. The incident narrative is what would be lost. |
| `skill-vs-command` | `CLAUDE.md:37` "Self-triggering skill when the condition is mechanical and detectable; a command only for an explicitly user-initiated action." | The general rule is one sentence and already stated verbatim; the body's remainder is the gitlore `resolve` example and a D7 pointer, both project-local. |

### keep — 96

Grouped by *why* the verdict is keep. Named owner is the candidate that was
checked, not a confirmed one.

**Keep — no owner exists anywhere in the corpus (harness/tooling empirical).**
Signature-token sweep over all 112 owner files: `isSidechain`,
`isCompactSummary`, `hasTrustDialogAccepted`, `tengu_`, `custom-title`,
`count_tokens`, `remove_branch_state`, `TMUX=` each return **0 owner files**;
`PostToolBatch`, `reload-plugins`, `protocol.ext.allow`, `rebase-merge`,
`autoMemoryDirectory` return only gitlore's own `docs/`, which the rule above
disqualifies.

`agent-hooks-need-exact-trust-key`, `bang-shell-shared-cwd`,
`cc-agent-discovery`, `cc-command-namespacing`, `cc-project-dir-encoding`,
`cc-subagent-approval`, `cc-tui-tmux-driving`, `cc-worktree-memory-freeze`,
`classifier-denied-self-config`, `claude-project-dir`,
`detect-liveness-not-presence`, `git-checkout-clears-merge-state`,
`git-ext-transport`, `git-protocol-file-allow`, `git-replay-hooks`,
`hook-cannot-inject-tool-calls`, `hook-input-schema`, `hook-output-channels`,
`jsonl-reader-type-guard`, `jsonl-sidechain-segregation`,
`jsonl-slash-command-shape`, `named-dispatch-drops-frontmatter-hooks`,
`plugin-recurse-clone`, `posttooluse-print-mode`, `sandbox-effects`,
`skill-bundled-scripts`,
`session-jsonl-schema`, `session-title-customtitle`, `sessionstart-resume-cwd`,
`stale-plugin-code`, `submodule-url-arrives-rewritten`, `tmux-test-isolation`,
`todo-tool-flag-gated`, `token-counting`, `transcripts-are-ground-truth`,
`verify-restart-before-structural-diagnosis`.

**Keep — override: an installed skill states the contrary rule.**
`skill-description-purpose-first`, `plan-contracts-not-full-code`,
`imperative-form-scope` — each cited above against the line it overrides.

`skill-bundled-scripts` is **not** in this class. `CLAUDE_PLUGIN_ROOT` appears
in 20 plugin-dev files, but every one is in `hook-development`,
`command-development`, `mcp-integration` or `plugin-structure` — the contexts
where the variable genuinely is set, so plugin-dev is right there.
`skill-development`, the one skill covering skill bodies, mentions it **zero**
times (`grep -rn CLAUDE_PLUGIN_ROOT skills/skill-development` → no output). The
fact records a negative plugin-dev never addresses, which makes it
keep-no-owner. Its own body says the passes it contradicts were
`claude-code-guide` answers — an agent, not a shipped document.

**Keep — partial overlap, the distinctive half is uncovered.**

| Fact | Covered by | Not covered |
| --- | --- | --- |
| `no-stderr-suppression` | `shell-gotchas/SKILL.md:48`, `references/robustness.md:37` — guard-first and scoped-redirect rungs | the three-rung *ordering*, and rung 2 capture-and-match (`err=$(cmd 2>&1)` + `case` on a verified discriminator); "never replace git's message with a guess" |
| `git-hook-env-leak` | `references/environments.md:11-22` — the 15 repo-local vars and the documented unset | the `GIT_INDEX_FILE` save/restore around a staging `git add`, and its `Unable to create '.git/index.lock': File exists` symptom (`grep -iF index.lock` → 0 hits) |
| `submodule-escape-to-parent` | `SKILL.md:44`, `environments.md:45` — the `[ -e sub/.git ]` guard; `environments.md:57` covers worktree detection *better* than the fact | the bogus `160000` gitlink symptom (`grep -F 160000` → 0 hits) |
| `git-stderr-and-parsing` | `environments.md:94` — CDPATH | every other claim: silence-on-normal-absence set, the non-ff-vs-policy discriminator, ancestry vs wording, `fetch -q` asymmetry, `-z --get-regexp` |
| `green-is-not-evidence` | `test-driven-development/writing-good-tests.md:157-194` — mutation check, shared-object warning sign | the enumerated pass-anyway shapes and the negative-test structuring guidance |
| `bats-shellcheck-gotchas` | shell-gotchas lints `.bats` | every bats-specific mechanism (SC2314, `run missing_fn` → 127, `grep -qF` multi-line) |
| `genuine-red-not-missing-sut` | `test-driven-development/SKILL.md:122,128` — "Test fails (not errors)", "Test errors? Fix error, re-run until it fails correctly" | the stub-then-assert technique, "green-at-first is not evidence", the inert-stub batch reading absence as wrongness, one contract per interface line |

**Keep — no owner: judgement facts, checked against `shared-claude.md` and the
superpowers/plugin-dev skills and found absent.**
Term sweep (`singleton`, `impossible`, `provisional`, `corpus`, `vestigial`,
`optional`, `duplication`, `drift direction`, `liveness`, `speculative`,
`narration`, `em-dash`, `semicolon`, `outside-in`, `end-to-end`, `stub`,
`line count`, `lines of code`, `full implementation`, `previous version`,
`contract`) returned **0 hits** in `shared-claude.md`, `writing-plans`,
`brainstorming`, and — for the last group — anywhere in `writing-skills`.

`bash-prolog-common-foundations`, `bundle-memory-with-source`,
`design-doc-writing`, `directive-states-acts`, `dont-bake-in-guarantees`,
`examine-evidence-drift`, `gate-cache-must-cover-every-check`,
`ground-formulas-in-data`, `guard-reveals-singleton`,
`guard-safety-visible-in-the-pattern`, `guardrail-must-permit-real-commands`,
`harden-human-gates`, `honest-line-count-caps`, `large-docs-review`,
`loose-generation`, `marginal-weakness-is-not-misweighting`,
`no-code-for-impossible-cases`, `no-doc-history-references`,
`no-speculative-rules`, `no-transition-special-cases`,
`optional-means-source-can-omit`, `outside-in-tdd`,
`parse-dont-regex-structured-formats`, `perf-fix-check-parallelism-assumption`,
`plan-length-matches-work`, `prose-voice-does-not-delegate`,
`provisional-values-not-provisional-code`, `reconstructable-two-categories`,
`reference-doc-scope`, `remove-cleanly-no-vestigial`,
`sdd-durable-state-across-compaction`, `shape-rules-are-not-duplication`,
`shared-trigger-means-merge`, `slice-history-forward-not-by-cherry-pick`,
`slice-uncommitted-tree-via-index`, `spec-contract-size-predicts-pr-size`,
`test-the-invocation-path`, `test-with-live-data-before-designing`,
`uncram-prose-shapes`.

`plan-length-matches-work` and `test-the-invocation-path` are each also stated
in gitlore's `CLAUDE.md` (lines 14 and 51). Both keep their file: each has a
real lookup moment — before writing a plan doc, and when building a test
harness — and the bodies carry incident detail the one-line rule does not.

**Keep — gitlore/ddaanet product facts; the only coverage is project-local.**
`gitlore-tier-index-budget` (design.md:649 states gitlore's advisory 25600-byte
budget but never the ~24.4KB CC loader cutoff — `grep -iE "24\.4|24985|loader|
cutoff"` → 0 hits, and the cutoff is the fact's whole point),
`gitlore-tier-merge-direction`, `index-compaction-triggers`, `memory-writing`,
`tier-links-cross-a-boundary`, `tier-routing-plugin-shaped`,
`preflight-excludes-memory-submodule`.

**Keep — other repos' conventions; no owner is readable from here.**
`claude-plugin-dev`, `edify-python-standards`, `justfile-shebang-indent`,
`uv-direnv-venv`.

## Proposals this audit produced, none executed

- Push the two uncovered halves upstream into `shell-scripting:shell-gotchas`:
  the `GIT_INDEX_FILE` save/restore around a staging `git add`, and the
  `160000` gitlink symptom. That would make `git-hook-env-leak` and
  `submodule-escape-to-parent` genuinely retirable later. `shell-scripting` is
  another repo — proposal only.
- `no-stderr-suppression`'s rung 2 (capture-and-match) is the same shape of
  gap, in the same skill.
