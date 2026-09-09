## Open decisions

- **Two process items from my human partner, and the reason for this
  compaction — do these before resuming Phase 4.**
  1. `just precommit`'s bats output is far too noisy. It should print minimal
     output on green and full detail only for failures and errors. Check
     whether bats flags already do this before writing anything —
     `scripts/run-bats.sh` is the wrapper and already filters to `not ok`
     blocks plus a count, so the noise may be coming from somewhere else in
     the recipe.
  2. Orchestrate sessions churn through context. Delegate an **opus** agent to
     analyse recent orchestrate sessions: what consumes context, and what can
     be reduced or delegated? My human partner's own hypotheses, to test rather
     than assume: dispatch-prompt authoring and report reading are the big
     consumers; prompts could be prepared in files and referenced by path in
     the Agent call; and since every edify agent already reports to a file
     rather than by message, report *processing* can itself be delegated.

- **The `precommit` gate returns verdicts spanning two trees, cause still
  unidentified.** During Phase 3 it recurred from the main session, not a
  subagent. Sentinels resolve through `git rev-parse --git-path` into a gitdir
  every peer session shares, and nothing in a sentinel records which tree or
  process wrote it — so a disagreeing hash is the lucky case, and a peer whose
  tree happens to hash the same would write a pass for a suite you never ran.
  Decide whether to settle it or to stop treating sentinels as evidence and
  read verdicts from suite output. Did not recur across Item 1.2's or Item
  1.3's gate runs.

- **Whether `CLAUDE.md` §Testing's gate paragraph is rewritten. Four errors
  now.** It says a sentinel is "valid for the tree when its mtime postdates the
  last edit to any gated input", but the mechanism is a content hash and mtime
  ordering is not evidence at all. It points at `just check-sentinel`, which
  does not exist — that is a justfile-prolog shell function, so the command
  errors with `Justfile does not contain recipe`. Its OOM fallback ("three
  sequential `just` calls") failed outright in Phase 3. And new this session:
  chunking at 2 suites, which the paragraph would be rewritten to recommend,
  *also* OOMs when other sessions hold the box — only 1 suite at a time
  completed. `/tmp/claude-1000/gate-chunks1.sh` is that variant.

- The memory index against Claude Code's ~24,985-byte loader cutoff, per
  `plans/2026-08-27-memory-index-budget-decision.md`. The root index reports
  102% of budget and is truncating, which is why no memory was written this
  session. `plans/2026-09-02-ddaanet-design-moment-facts.md` frees ~4,600 by
  relocation and merges, the three dropped briefs a further ~10,400. Decide:
  curate first and re-measure, or do the composition reorder (D29 layout rule,
  D36 rewrite, `gitlore_order_merge` in `index-composition.md`). This gates
  every memory write below.

- Which gitlore-side tier merges from
  `plans/2026-09-02-ddaanet-design-moment-facts.md` to execute: `plan-writing`
  (7 facts to 1), `guard-design` (3 to 1), folding `test-the-invocation-path`
  into `green-is-not-evidence`, `imperative-form-scope` into
  `skill-description-purpose-first`, `markdown-formatter-choice` into
  `claude-plugin-dev`, `bash-prolog-common-foundations` into
  `justfile-gotchas`, `no-transition-special-cases` into
  `remove-cleanly-no-vestigial`; and whether `loose-generation` gets a trigger
  or is retired. Several are brief-bound, so order matters.

- Whether the guard and validation design facts go to `craft` (current default)
  or to `prohibitions`.

- Whether the toolkit release-and-vendoring skill belongs in `plugin-craft` or
  in `claude-plugin-dev`'s own `toolkit/README.md`.

- `reconstructable-two-categories` is a handoff-design lesson: whether to drop
  a note in the handoff repo proposing it move to handoff's own store.

- Whether a phantom-dotfile prohibition (never delete, commit or report one)
  goes into `memory/ddaanet/shared-claude.md`. No hook fires on the `` !`cmd` ``
  expansion path, so prose is the only mechanism. Seen again this session: a
  `git status` mid-run showed `.bashrc`, `.zshrc`, `.claude/agents` and a dozen
  more as untracked; they were excluded from the commit by staging explicitly.

- Whether `2026-09-02-bang-expansion-hook-decompile.md` belonged in the move to
  sandbox-lies. Its finding matters to gitlore independently as a hook-heavy
  plugin.

- The recall-size hook fires on `memory/ddaanet/shared-claude.md` demanding it
  be cut under 2.8KB, but that file is imported whole by `CLAUDE.md` and is
  never a recall target. Decide whether the hook should exempt it.

## Remaining

- Phase 4: Item 1.3 slice 2, then Items 4.1 + 4.2 in one commit, then 4.3.

- Write the testing facts Phases 3, 1.2 and 1.3 produced, once the index budget
  allows. **An assertion positioned after a test's death point has never
  executed** — bitten four times now. **A born-green case needs a mutation-red
  proof.** **`jq -r` prints the literal string `null` for an absent key.** **A
  fixture restore must be conditional.** New from Item 1.3: **a mutation proof
  can go stale** — case 15's comment claimed a naive-predicate red that stopped
  holding once staging became a pair, so a comment naming a mutation needs
  re-checking whenever the SUT's shape changes. And **the fixture must create
  the condition the projection actually acts on**: `gitlore_compose_down` keeps
  a carrier-only line (`o=0, t=1, b=0`) and rewrites one root also carries, so
  a probe whose upstream side *adds* an index line goes green against a
  destructive implementation and proves nothing — it must *re-text a line both
  surfaces already hold*.

- Write the orchestration fact: every one of three `edify:test-driver` GREEN
  dispatches in Item 2.1 went idle waiting on a background `just precommit`
  notification a subagent does not reliably receive, each time despite an
  explicit instruction not to wait. Instructing the agent does not work; the
  orchestrator owning the gate does. Corollary from Item 1.2: a born-green
  slice has no GREEN and no code review to run.

- Write the ambient-`CLAUDECODE` fact: a subagent dispatch exports
  `CLAUDECODE=1`, so a bats test branching on it passes under dispatch and
  fails for a human or CI. Run the suite in all three ambient worlds.

- Write the report-cannot-cite-its-own-commit fact.

- Write the citation-boundary fact: shipped plugin source cites neither
  `plans/` nor `memory/`, nor a runbook/slice identifier, nor a line number.
  Item 1.3's code review stripped three more.

- Record that `find` on this box is `bfs`, which rejects `-newermt '-60
  minutes'` and, under `2>/dev/null`, reads as "no files matched".

- Narrow `test-unit`'s gate inputs to exclude `tests/integration_*`.

- Triage `inbox/brief-add-tier-index-budget-advisory.md`.

- Split the oversized token-keyed facts so recall reaches them:
  `hook-output-channels` (23% reachable), `bats-shellcheck-gotchas` (40%),
  `stale-plugin-code` (45%), `design-doc-writing` (over 4KB).

- Extend the memory-writing skill's index-line guidance to both axes.

- Rerun `plans/2026-09-02-recall-log-analysis.py` once a week or two of
  native-recall attachments exist.

- Continue the ddaanet review pass from `plans/ddaanet-memory-review.md`
  (entry 5, `hook-output-channels`).

- Check the bang-expansion decompile report's verbatim excerpts against the
  CC 2.1.258 bundle before trusting its verdict.
