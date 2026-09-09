## Open decisions

- **Whether Item 1.2's interrupted-merge residual is fixed or accepted.**
  `gitlore_guard_stale_merge_state` does not always refuse: on
  `stale-no-merge-head` it delegates to `gitlore_recover_stale_no_merge_head`,
  which can repair and return 0 — and neither of its branches stages the moved
  gitlink, which the normal continuation does as its last act (D43). So the
  per-tier loop can hand the new pin guard a tier that is off its pin *because
  gitlore just repaired it*: the commit aborts, and the remedy offers
  `checkout --detach <pinned>`, which would move HEAD off a landed, approved
  merge. Either the recovery path stages the gitlink it moved, or the accepted
  blocking cost covers this case too. Item 4.1's node has to say which.

- **The `precommit` gate returns verdicts spanning two trees, and the cause is
  still unidentified.** During Phase 3 it recurred from the *main* session, not
  a subagent, which was the previous hypothesis: `test-unit` and
  `test-integration` held `2146629698 1104208` while an independent hand
  recomputation of `gate-inputs-hash` over `precommit_inputs` gave
  `638743299 1104210` — a tree 2 bytes different that never existed in this
  working copy — and both sentinels were rewritten twice more, 0.4s and 1.1s
  apart, including once in a run where only `just test-unit` was invoked.
  `lint` and `check-distribution` hand-verified clean each time. Two
  explanations were tested and disproved: the `run-bats.sh` logs showing only
  an argument list are the wrapper's own test stub, not a pass recorded for
  nothing, and `tests/justfile_gates.bats` writes an isolated `$GATE_REPO`.
  What is established is that sentinels resolve through `git rev-parse
  --git-path` into a gitdir every peer session shares, and nothing in a
  sentinel records which tree or process wrote it — so a disagreeing hash is
  the lucky case, and a peer whose tree happens to hash the same would write a
  pass for a suite you never ran. Decide whether to settle it, or to stop
  treating sentinels as evidence and read verdicts from suite output. It did
  not recur across Item 1.2's three gate runs.

- **Whether `CLAUDE.md` §Testing's gate paragraph is rewritten.** Three errors
  now. It says a sentinel is "valid for the tree when its mtime postdates the
  last edit to any gated input", but the mechanism is a content hash and mtime
  ordering is not evidence at all. It points at `just check-sentinel`, which
  does not exist — `check-sentinel` is a justfile-prolog shell function, so the
  command errors with `Justfile does not contain recipe`. And its OOM fallback
  ("three sequential `just` calls") failed outright in Phase 3: five whole-suite
  runs were killed, at 2 jobs and at 1. What worked is chunking —
  `scripts/run-bats.sh --jobs 1` over 2-5 suites at a time, which completed
  every attempt and yields a per-chunk verdict, and which every Item 1.2
  subagent used without incident. `/tmp/claude-1000/gate-chunks.sh` is a
  resumable version (appends each chunk's verdict, skips recorded ones on
  re-run). Can ride Phase 4.

- The memory index against Claude Code's ~24,985-byte loader cutoff, per
  `plans/2026-08-27-memory-index-budget-decision.md`. The root index reports
  102% of budget and is truncating. `plans/2026-09-02-ddaanet-design-moment-facts.md`
  frees ~4,600 by relocation and merges, and the three dropped briefs a further
  ~10,400. Decide: run curation first and re-measure, or still do the
  composition reorder (D29 layout rule, D36 rewrite, `gitlore_order_merge` in
  `index-composition.md`). `sandbox-effects` holds 988 bytes of the overshoot
  and retires as sandbox-lies phase 4, which changes the arithmetic. This also
  gates every memory write listed below — each adds an index line.

- Which gitlore-side tier merges from `plans/2026-09-02-ddaanet-design-moment-facts.md`
  to execute: `plan-writing` (7 facts to 1), `guard-design` (3 to 1), folding
  `test-the-invocation-path` into `green-is-not-evidence`, `imperative-form-scope`
  into `skill-description-purpose-first`, `markdown-formatter-choice` into
  `claude-plugin-dev`, `bash-prolog-common-foundations` into `justfile-gotchas`,
  `no-transition-special-cases` into `remove-cleanly-no-vestigial`; and whether
  `loose-generation` gets a trigger or is retired. Several are brief-bound, so
  order matters: merge then convert, or convert then merge.

- Whether the guard and validation design facts go to `craft` (current default)
  or to `prohibitions`.

- Whether the toolkit release-and-vendoring skill belongs in `plugin-craft` or
  in `claude-plugin-dev`'s own `toolkit/README.md`, which already ships with the
  vendored files.

- `reconstructable-two-categories` is a handoff-design lesson: whether to drop a
  note in the handoff repo proposing it move to handoff's own store.

- Whether a one- or two-line phantom-dotfile prohibition (never delete, commit
  or report one) goes into `memory/ddaanet/shared-claude.md`. No hook fires on
  the `` !`cmd` `` expansion path, so prose is the only mechanism that covers the
  `/commit` `## Context` case. The orchestrate skill's `verify-step.sh` exits 1
  on a tree whose only dirt is those phantoms.

- Whether `2026-09-02-bang-expansion-hook-decompile.md` belonged in the move to
  sandbox-lies. Its finding — no hook dispatches on the `` !`cmd` `` path —
  matters to gitlore independently as a hook-heavy plugin.

- The recall-size hook fires on `memory/ddaanet/shared-claude.md` demanding it be
  cut under 2.8KB, but that file is imported whole by `CLAUDE.md` and is never a
  recall target, and it has been well past 4KB for a long time. Decide whether
  the hook should exempt the tier conventions file or whether the warning is
  doing something the exemption would lose.

## Remaining

- Phase 4, Items 4.0 through 4.3, per the task file.

- Write the testing facts Phases 3 and 1.2 produced, once the index budget
  allows. **An assertion positioned after a test's death point has never
  executed** — written but unverified. This bit three times now: a
  `grep -o -F "$frame"` whose leading `---` GNU grep parsed as options; a `run`
  that merged a failing redirect's stderr into the JSON it then parsed; and, in
  Item 1.2 slice 1, seven assertions behind a first-line `[ "$status" -ne 0 ]`.
  The same trap has a mutation form: a mutation that reds a test via an *earlier*
  assertion proves nothing about the target one — Item 1.2 slice 3's literal
  arm-collapse reds the retry-ending assertion, not the negative it was meant to
  isolate, so isolating it needed a narrower mutation. Verify by reordering or an
  isolating mutation, never by reading. **A born-green case needs a mutation-red
  proof** — back the behaviour out, watch it red, restore — or it is not a
  regression pin; and for a born-green case, per-assertion mutation is the whole
  review, since a green run shows an assertion ran and held but never that it
  could fail. **`jq -r` prints the literal string `null` for an absent key**, so
  a refutation on a channel passes against JSON that dropped the channel
  entirely; guard with `!= "null"` first. **A fixture restore must be
  conditional** (`[ -e … ] && chmod …`): unconditional cleanup dies under errexit
  on something a fixed implementation has since removed, before any assertion
  runs.

- Write the orchestration fact: every one of three `edify:test-driver` GREEN
  dispatches in Item 2.1 went idle waiting on a background `just precommit`
  notification a subagent does not reliably receive, each time despite an
  explicit instruction not to wait. Instructing the agent does not work; the
  orchestrator owning the gate does, and that is now the standing contract. Its
  corollary, from Item 1.2: a slice whose behaviour an earlier slice already
  landed has no GREEN and no code review to run — dispatching them anyway buys a
  no-op and a review with no subject.

- Write the ambient-`CLAUDECODE` fact: a subagent dispatch exports
  `CLAUDECODE=1`, so a bats test that branches on it passes under dispatch and
  fails for a human or CI. Item 1.2's reviews settled the discipline — run the
  suite in all three ambient worlds (`CLAUDECODE=1`, `env -u CLAUDECODE`,
  `env CLAUDECODE=0`), since `gitlore_say_for_agent_or_user` branches on
  `[ -n "${CLAUDECODE:-}" ]` and any non-empty value selects the agent arm.

- Write the report-cannot-cite-its-own-commit fact: a slice report committed
  *with* the work cannot carry that commit's sha, because amending the report
  in changes it. Item 2.1 slice 2's report names `b76a253`, which is not in the
  log; slice 3's identifies its commit by subject instead.

- Write the citation-boundary fact: shipped plugin source must cite neither
  `plans/` (prospective, swept) nor `memory/` (reaches the tree through a
  submodule gitlink, not distributed), nor a runbook/slice identifier, nor a
  line number. Four reviews in Phase 3 stripped one of these, and Item 1.2
  slice 1 found another already committed — `(index-compose.sh:787)` in the
  rc-1 arm's comment. Tests are exempt by precedent and cite freely. The only
  precedent in `scripts/` is `scripts/lib/util.sh:442` citing `docs/design.md`.

- Record that `find` on this box is `bfs`, which rejects `-newermt '-60
  minutes'` with `Invalid timestamp` and accepts only ISO 8601-like forms — a
  relative `-newermt` returns nothing and, under `2>/dev/null`, reads as "no
  files matched" rather than as an error.

- Narrow `test-unit`'s gate inputs to exclude `tests/integration_*` once the
  split has run a while; all three gates share `precommit_inputs` for now,
  which is why `test-unit` and `test-integration` carry the same input hash.

- Triage `inbox/brief-add-tier-index-budget-advisory.md`: `/gitlore:add-tier`
  composes the root index but cannot warn that the result overflows the loader
  cutoff, and the mount is the one operation that adds tens of KB in a step.

- Split the oversized token-keyed facts so recall reaches them:
  `hook-output-channels` (23% reachable), `bats-shellcheck-gotchas` (40%),
  `stale-plugin-code` (45%), `design-doc-writing` (over 4KB, and being cut into
  a craft skill — check before splitting). Hub under 4KB carrying the symptom
  table, siblings beside it. `subagent-hook-output-confined` is a natural
  sibling of `hook-output-channels` once the hub exists.

- Extend the memory-writing skill's index-line guidance to both axes: a
  design-moment trigger needs a symptom-shaped hook or a home at a skill
  checkpoint, and a body past 4096 bytes is unreachable beyond that point
  whatever its trigger.

- Rerun `plans/2026-09-02-recall-log-analysis.py` once a week or two of
  native-recall attachments exist; report the harness class and selector
  precision.

- Continue the ddaanet review pass from the queue in
  `plans/ddaanet-memory-review.md` (entry 5, `hook-output-channels`).

- Check the bang-expansion decompile report's verbatim excerpts against the
  CC 2.1.258 bundle before trusting its verdict; it lives at
  `sandbox-lies/plans/2026-09-02-bang-expansion-hook-decompile.md`.
