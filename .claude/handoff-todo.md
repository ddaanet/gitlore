## Open decisions

- **The memory index against Claude Code's ~24,985-byte loader cutoff**, per `plans/2026-08-27-memory-index-budget-decision.md`. The root index reports 102% of budget and is truncating, which is why no memory has been written across five sessions. `plans/2026-09-02-ddaanet-design-moment-facts.md` frees ~4,600 by relocation and merges, the three dropped briefs a further ~10,400. Decide: curate first and re-measure, or do the composition reorder (D29 layout rule, D36 rewrite, `gitlore_order_merge` in `index-composition.md`). This gates every memory write below.

- **Whether `CLAUDE.md` §Testing's gate paragraph is rewritten.** Errors:
  - It says a sentinel is valid when its mtime postdates the last edit to any gated input. The mechanism is a content hash, and mtime ordering is not evidence.
  - It points at `just check-sentinel`, which is a justfile-prolog function, not a recipe.
  - Its OOM fallback of three sequential `just` calls failed in Phase 3. Chunking at 2 suites also OOMs, and so does `just test-unit` alone at `GITLORE_TEST_JOBS=1`.
  - The deliverable review's M7 adds: `format-docs`, `check-memory-hygiene.py`, `check-docs-links.py` and `check-version` write no gate file, so a docs-only failure reads green. The gates path is per-worktree. The fallback omits `check-distribution`.
  - It cites a `plans/` file.

- **Where the chunked gate runner should live.** `/tmp/claude-1000/gate-chunks1.sh` is the only fallback that has completed a full verdict twice, and it is in a tmpfs that will not survive a reboot. It runs one bats suite per invocation, appends `KEY=<tag>:<suite> bats: N passed, M failed` per chunk, and resumes by skipping recorded keys, so its results file must be deleted before a fresh run. Decide whether it becomes a tracked script with its own recipe.

- **The `precommit` gate returns verdicts spanning two trees; the cause is unidentified.** Sentinels resolve through `git rev-parse --git-path` into a gitdir every peer session shares, and nothing in a sentinel records which tree or process wrote it. A concurrent session's precommit ran during the relay pass and the gate files moved under it. Decide whether to settle it, or to stop treating sentinels as evidence and read verdicts from suite output.

- **Whether `relay-drain.sh` should omit `additionalContext` when the ctx half is empty.** It follows `index-compose.sh` and always emits the key; `index-sync-post.sh` omits it. An empty context injects nothing, so this is shape, not behaviour.

- **Which of the orchestrate context-analysis recommendations to act on.** Report at `plans/2026-09-10-orchestrate-context-analysis.md`. A: split a run across sessions at phase boundaries (35% saving at two splits, 55% at four). B: exclude `plans/*/reports/` from `just format-docs`. C, D and E are edify-plugin edits, i.e. another repo.

- **The TDD audit's two standing items**, from `plans/index-edit-propagation/reports/tdd-audit.md`. M3a (`ls | grep` in the drain) is moot since the drain rewrite. Eleven of nineteen slices have no auditable green-at-commit record; recommendation 4 is to record the gate verdict in each green report. The relay pass ran no TDD audit; its slice reports are `plans/index-edit-propagation/reports/relay-s*.md`.

- **Whether `docs/references/git-hooks.md` should carry the pre-split history.** Git paired the old `git-hooks-and-entry-points.md` with `memory-entry-points.md` (55%), so `git log --follow` reaches the full history from the entry-points half, and `git-hooks.md` starts fresh at `951b83a`. Changing it needs a re-commit with `-M` tuning or an explicit two-step.

- Which gitlore-side tier merges from `plans/2026-09-02-ddaanet-design-moment-facts.md` to execute:
  - `plan-writing` (7 facts to 1) and `guard-design` (3 to 1);
  - folding `test-the-invocation-path` into `green-is-not-evidence`, `imperative-form-scope` into `skill-description-purpose-first`, `markdown-formatter-choice` into `claude-plugin-dev`, `bash-prolog-common-foundations` into `justfile-gotchas`, and `no-transition-special-cases` into `remove-cleanly-no-vestigial`;
  - whether `loose-generation` gets a trigger or is retired.

  Several are brief-bound, so order matters.

- Whether the guard and validation design facts go to `craft` (the current default) or to `prohibitions`.

- Whether the toolkit release-and-vendoring skill belongs in `plugin-craft` or in `claude-plugin-dev`'s own `toolkit/README.md`.

- `reconstructable-two-categories` is a handoff-design lesson: whether to drop a note in the handoff repo proposing it move to handoff's own store.

- Whether a phantom-dotfile prohibition (never delete, commit or report one) goes into `memory/ddaanet/shared-claude.md`. No hook fires on the `` !`cmd` `` expansion path, so prose is the only mechanism. Seen again 2026-09-13: twelve zero-byte read-only dotfiles in the repo root, timestamped to a concurrent session's precommit start.

- Whether `2026-09-02-bang-expansion-hook-decompile.md` belonged in the move to sandbox-lies. Its finding matters to gitlore independently, as a hook-heavy plugin.

- The recall-size hook fires on `memory/ddaanet/shared-claude.md`, demanding it be cut under 2.8KB. That file is imported whole by `CLAUDE.md` and is never a recall target. Decide whether the hook should exempt it.

## Remaining

- Work through the deliverable review's Minor findings, dispatched to sonnet. Already folded: the stale approval, the unquoted adoption remedies and the `gitlore_compose_check_pins` caller comment (C1 fix); every relay-side comment and design-record item (relay redesign). Still open: the `gitlore_adopt_recovered_merge` short-circuit; the squatted-marker and mutation-red comments in `tests/index_sync.bats`, `tests/cc_hook_index_compose.bats`, `tests/commit_memory.bats`, `tests/resolve_recovery.bats`; the untested `|| agent_id=""` and the unargued fatal reads; `tests/git_hook_pre_commit.bats` items; the `pre-commit` step list in `docs/references/git-hooks.md` (order, tier sync, landed-tier staging) and the changelog's sequence; the untracked-file count; the three unrecorded rejected alternatives and D50's dirty-only scope in `decisions.md`; `cc-platform.md` "all four"; `session.md` steps 6 and 10 exit disagreement; `merge-state-recovery.md:80-84`; the hub's hooks bullet; `CLAUDE.md:61`'s `plans/` citation; the two runbook-drift lines.

- Then, in a fresh opus session: `/deliverable-review plans/index-edit-propagation`.

- `_gitlore_nudge_reset`'s `find … -mtime +7 -delete` is unguarded under the calling hook's errexit; `gitlore_relay_sweep` guards its own. Flagged by the relay slice 1 code review, untouched.

- `plans/index-edit-propagation/recall-artifact.md` names four memory files that no longer exist under `memory/ddaanet/`: `hook-input-schema`, `genuine-red-not-missing-sut`, `green-is-not-evidence`, `design-doc-writing`. Find where they went and repoint or retire the artifact lines.

- Check whether a tier whose local `live` failed to advance after its commit, for a non-divergence reason, ever advances. `gitlore_sync_tiers_to_live` pushes `HEAD:live` only for dirty tiers, so the retry that stages the landed commit skips the push. Pre-existing, not probed.

- Write the platform fact once the index budget allows: **all hooks matching one Claude Code event run in parallel** (code.claude.com/docs/en/hooks). Two `PostToolBatch` hooks sharing a file race. The relay was designed on the opposite assumption, and a vendored `plugin-dev:hook-development` skill already says "Assuming Hook Order" is a pitfall.

- Write the approval-freshness facts once the index budget allows: `commit-memory.sh` rewrites the summary file on every call, so an approval-restamp bug surfaces only on the `pre-commit` path; and a merge preparation checks merged content out into the worktree, so restamping an approval after a merge yield would approve content no summary covered.

- Add to `.claude/rules/shell.md`: **`set -e` does not abort a Bash tool command.** A `cd "$TMPDIR"` with `$TMPDIR` unset leaves the shell in the repo root and the following commands run there. The unset-`$TMPDIR` half is already recorded; the non-aborting half is not.

- Write the testing facts Phases 1-3 produced, once the index budget allows:
  - An assertion positioned after a test's death point has never executed.
  - A born-green case needs a mutation-red proof.
  - `jq -r` prints the literal string `null` for an absent key.
  - A fixture restore must be conditional.
  - A mutation proof can go stale.
  - The fixture must create the condition the projection actually acts on.
  - A negative assertion needs the mutation that makes the string appear.
  - A fixture helper's name is not its shape.
  - A fixed-order test cannot exercise a same-file race between parallel hooks.
  - `$$` is fixed at shell startup and shared by `&` subshells; `$BASHPID` is per-subshell but absent on bash 3.2; a concurrency test spawns `bash -c` processes.
  - Inside bats, stdin is a socket, not `/dev/null`: a hook that `cat`s its payload hangs when invoked bare (`exec 0</dev/null` in `setup_tmp_repo` now covers it).
  - `grep -c` over a hook's JSON cannot see a doubled block inside a one-line `systemMessage`.

- Write the two relay traps:
  - POSIX `mv` moves its source INTO an existing-directory destination with exit 0, so a temp-then-rename needs an explicit `[ -e "$dest" ]` refusal.
  - A temp file sharing a name prefix with what a `find` glob enumerates is consumed as one of them.

- Write the orchestration fact: every `edify:test-driver` GREEN dispatch across two runs went idle waiting on a suite notification a subagent does not reliably receive, even when told to run it in the foreground; one `SendMessage` nudge naming the gate artifact gets the report. The orchestrator owning the gate works. Corollary: a born-green slice has no GREEN and no code review to run.

- Write the ambient-`CLAUDECODE` fact: a subagent dispatch exports `CLAUDECODE=1`, so a bats test branching on it passes under dispatch and fails for a human or CI. Run the suite in all three ambient worlds.

- Write the report-cannot-cite-its-own-commit fact.

- Write the citation-boundary fact: shipped plugin source cites neither `plans/` nor `memory/`, nor a runbook or slice identifier, nor a line number.

- Record that `find` on this box is `bfs`, which rejects `-newermt '-60 minutes'`, and under `2>/dev/null` that reads as "no files matched".

- Narrow `test-unit`'s gate inputs to exclude `tests/integration_*`.

- Triage `inbox/brief-add-tier-index-budget-advisory.md`.

- Split the oversized token-keyed facts so recall reaches them: `hook-output-channels` (23% reachable), `bats-shellcheck-gotchas` (40%), `stale-plugin-code` (45%), `design-doc-writing` (over 4KB).

- Extend the memory-writing skill's index-line guidance to both axes.

- Rerun `plans/2026-09-02-recall-log-analysis.py` once a week or two of native-recall attachments exist.

- Continue the ddaanet review pass from `plans/ddaanet-memory-review.md` (entry 5, `hook-output-channels`).

- Check the bang-expansion decompile report's verbatim excerpts against the CC 2.1.258 bundle before trusting its verdict.
