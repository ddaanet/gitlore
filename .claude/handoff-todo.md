## Open decisions

- **The memory index against Claude Code's ~24,985-byte loader cutoff**, per `plans/2026-08-27-memory-index-budget-decision.md`. The root index reports 102% of budget and is truncating, which is why no memory has been written across two sessions. `plans/2026-09-02-ddaanet-design-moment-facts.md` frees ~4,600 by relocation and merges, the three dropped briefs a further ~10,400. Decide: curate first and re-measure, or do the composition reorder (D29 layout rule, D36 rewrite, `gitlore_order_merge` in `index-composition.md`). This gates every memory write below.

- **Whether `CLAUDE.md` §Testing's gate paragraph is rewritten. Five errors.** It says a sentinel is "valid for the tree when its mtime postdates the last edit to any gated input", but the mechanism is a content hash and mtime ordering is not evidence at all. It points at `just check-sentinel`, which does not exist — that is a justfile-prolog shell function, so the command errors with `Justfile does not contain recipe`. Its OOM fallback ("three sequential `just` calls") failed outright in Phase 3. Chunking at 2 suites also OOMs when other sessions hold the box. And `just test-unit` alone at `GITLORE_TEST_JOBS=1` OOMs too, so the paragraph's fallback has no working rung left above the per-suite chunker.

- **Where the chunked gate runner should live.** `/tmp/claude-1000/gate-chunks1.sh` is the only fallback that has completed a full verdict twice, and it is in a tmpfs that will not survive a reboot. It runs one bats suite per invocation, appends `KEY=<tag>:<suite> bats: N passed, M failed` per chunk, and is resumable by skipping recorded keys — which means its results file must be deleted before a fresh run or it reports stale passes. Decide whether it becomes a tracked script with its own recipe.

- **The `precommit` gate returns verdicts spanning two trees, cause still unidentified.** Sentinels resolve through `git rev-parse --git-path` into a gitdir every peer session shares, and nothing in a sentinel records which tree or process wrote it — so a disagreeing hash is the lucky case, and a peer whose tree happens to hash the same would write a pass for a suite you never ran. Decide whether to settle it or to stop treating sentinels as evidence and read verdicts from suite output.

- **Which of the orchestrate context-analysis recommendations to act on.** Report at `plans/2026-09-10-orchestrate-context-analysis.md`. Recommendation A — split a run across sessions at phase boundaries — measured 35% saving at two splits, 55% at four. Recommendation B's cleanest form is excluding `plans/*/reports/` from what `just format-docs` hard-wraps, which changes this repo's wrapping policy. C (dispatch preamble to a fragment), D (verdict head on corrector reports) and E (delegate RED/GREEN roll-up only) are all edify-plugin edits, i.e. another repo.

- **The TDD audit's two standing items**, from `plans/index-edit-propagation/reports/tdd-audit.md`. M3a (`ls | grep` instead of `find -print0` in the drain) is argued unenforceable by the existing cases and the runbook's "never an `ls` pipeline" clause is style rather than behaviour — decide whether to accept it as such in the design node. Separately, eleven of nineteen slices have no auditable record that the suite was green at commit time; the audit's recommendation 4 is to record the gate verdict in each green report.

- **Whether `docs/references/git-hooks.md` should carry the pre-split history.** Git's similarity detection paired the old `git-hooks-and-entry-points.md` with `memory-entry-points.md` (55%) at commit time, overriding the staged `git mv`, so `git log --follow` reaches the full history from the entry-points half and `git-hooks.md` starts fresh at `951b83a`. Defensible as it stands — the entry-points half took the larger share of the text. Changing it needs a re-commit with `-M` tuning or an explicit two-step.

- Which gitlore-side tier merges from `plans/2026-09-02-ddaanet-design-moment-facts.md` to execute: `plan-writing` (7 facts to 1), `guard-design` (3 to 1), folding `test-the-invocation-path` into `green-is-not-evidence`, `imperative-form-scope` into `skill-description-purpose-first`, `markdown-formatter-choice` into `claude-plugin-dev`, `bash-prolog-common-foundations` into `justfile-gotchas`, `no-transition-special-cases` into `remove-cleanly-no-vestigial`; and whether `loose-generation` gets a trigger or is retired. Several are brief-bound, so order matters.

- Whether the guard and validation design facts go to `craft` (current default) or to `prohibitions`.

- Whether the toolkit release-and-vendoring skill belongs in `plugin-craft` or in `claude-plugin-dev`'s own `toolkit/README.md`.

- `reconstructable-two-categories` is a handoff-design lesson: whether to drop a note in the handoff repo proposing it move to handoff's own store.

- Whether a phantom-dotfile prohibition (never delete, commit or report one) goes into `memory/ddaanet/shared-claude.md`. No hook fires on the `` !`cmd` `` expansion path, so prose is the only mechanism.

- Whether `2026-09-02-bang-expansion-hook-decompile.md` belonged in the move to sandbox-lies. Its finding matters to gitlore independently as a hook-heavy plugin.

- The recall-size hook fires on `memory/ddaanet/shared-claude.md` demanding it be cut under 2.8KB, but that file is imported whole by `CLAUDE.md` and is never a recall target. Decide whether the hook should exempt it.

## Remaining

- Add to `.claude/rules/shell.md`: **`set -e` does not abort a Bash tool command.** A subagent's probe began `W="$TMPDIR/mbprobe"; cd "$W"` with `$TMPDIR` unset, so `cd` failed — and the rest of the script ran in the repo root, re-running `git init` and leaving HEAD on an unborn orphan branch. Hit again this session: a `cd "$TMPDIR"` with `$TMPDIR` unset is a no-op that leaves the shell in the repo root, so the following `mkdir -p` created a stray fixture directory there. The unset-`$TMPDIR` half is already recorded there; the non-aborting half is not.

- Write the testing facts Phases 1-3 produced, once the index budget allows. **An assertion positioned after a test's death point has never executed.** **A born-green case needs a mutation-red proof.** **`jq -r` prints the literal string `null` for an absent key.** **A fixture restore must be conditional.** **A mutation proof can go stale.** **The fixture must create the condition the projection actually acts on.** **A negative assertion needs the mutation that makes the string appear**, not the one that removes it. **A fixture helper's name is not its shape.**

- Write the two traps this session's relay work produced. **POSIX `mv` moves its source INTO an existing-directory destination rather than failing**, exit 0 — so a write-to-temp-then-rename needs an explicit `[ -d "$dest" ]` refusal, or a squatted destination silently lands the file one level too deep and reports success. **A temp file sharing a name prefix with what a `find` glob enumerates is consumed as one of them** — narrow the glob when introducing a `.tmp` sibling.

- Write the orchestration fact: every one of three `edify:test-driver` GREEN dispatches in Item 2.1 went idle waiting on a background `just precommit` notification a subagent does not reliably receive, each time despite an explicit instruction not to wait. Instructing the agent does not work; the orchestrator owning the gate does. Corollary from Item 1.2: a born-green slice has no GREEN and no code review to run.

- Write the ambient-`CLAUDECODE` fact: a subagent dispatch exports `CLAUDECODE=1`, so a bats test branching on it passes under dispatch and fails for a human or CI. Run the suite in all three ambient worlds.

- Write the report-cannot-cite-its-own-commit fact.

- Write the citation-boundary fact: shipped plugin source cites neither `plans/` nor `memory/`, nor a runbook/slice identifier, nor a line number.

- Record that `find` on this box is `bfs`, which rejects `-newermt '-60 minutes'` and, under `2>/dev/null`, reads as "no files matched".

- Narrow `test-unit`'s gate inputs to exclude `tests/integration_*`.

- Triage `inbox/brief-add-tier-index-budget-advisory.md`.

- Split the oversized token-keyed facts so recall reaches them: `hook-output-channels` (23% reachable), `bats-shellcheck-gotchas` (40%), `stale-plugin-code` (45%), `design-doc-writing` (over 4KB).

- Extend the memory-writing skill's index-line guidance to both axes.

- Rerun `plans/2026-09-02-recall-log-analysis.py` once a week or two of native-recall attachments exist.

- Continue the ddaanet review pass from `plans/ddaanet-memory-review.md` (entry 5, `hook-output-channels`).

- Check the bang-expansion decompile report's verbatim excerpts against the CC 2.1.258 bundle before trusting its verdict.

- Run `/deliverable-review plans/index-edit-propagation` (opus, fresh session) — the orchestrate run's closing follow-up.
