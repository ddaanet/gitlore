## Open decisions

- **The `precommit` gate has three times returned a verdict spanning two
  trees**, each time with the recipes disagreeing on the input hash they
  recorded. All three splits came from a gate launched in the background from
  inside a *subagent*. Since then two full runs launched from the main session
  have been hand-verified clean — every sentinel matching an independent
  recomputation of `gate-inputs-hash` over its own declared inputs, and
  internally coherent timings. That is consistent with a subagent artifact but
  does not establish it: seven-plus interactive peers share the gitdir and
  could have been the cause either time. Decide whether to settle it or leave
  the current practice (orchestrator runs every gate in the main session, and
  compares all four sentinels against a hand recomputation before committing)
  standing as the mitigation. Until settled, a gate verdict is not evidence
  without that hand check.

- **Whether `CLAUDE.md` §Testing's gate-sentinel paragraph is rewritten.** Two
  errors. It says a sentinel is "valid for the tree when its mtime postdates
  the last edit to any gated input", but the mechanism is a content hash — the
  sentinel holds `cksum` output over the gate's declared inputs, and mtime
  ordering is not evidence at all (a sentinel legitimately written by a
  subagent's own `just lint` appeared out of recipe order during this run). And
  it points at `just check-sentinel`, which does not exist: `check-sentinel` is
  a shell function in the justfile prolog, not a recipe, so the command errors
  with `Justfile does not contain recipe`. That wrong command reached two
  dispatch prompts before it was caught. Can ride Phase 4.

- The memory index against Claude Code's ~24,985-byte loader cutoff, per
  `plans/2026-08-27-memory-index-budget-decision.md`. The root index reports
  102% of budget and is truncating. `plans/2026-09-02-ddaanet-design-moment-facts.md`
  frees ~4,600 by relocation and merges, and the three dropped briefs a further
  ~10,400. Decide: run curation first and re-measure, or still do the
  composition reorder (D29 layout rule, D36 rewrite, `gitlore_order_merge` in
  `index-composition.md`). `sandbox-effects` holds 988 bytes of the overshoot
  and retires as sandbox-lies phase 4, which changes the arithmetic.

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
  on a tree whose only dirt is those phantoms, so a mechanical gate already
  misreads them as uncommitted work — seen at every slice boundary in this run.

- Whether `2026-09-02-bang-expansion-hook-decompile.md` belonged in the move to
  sandbox-lies. Its finding — no hook dispatches on the `` !`cmd` `` path —
  matters to gitlore independently as a hook-heavy plugin.

- The recall-size hook fires on `memory/ddaanet/shared-claude.md` demanding it be
  cut under 2.8KB, but that file is imported whole by `CLAUDE.md` and is never a
  recall target, and it has been well past 4KB for a long time. Decide whether
  the hook should exempt the tier conventions file or whether the warning is
  doing something the exemption would lose.

## Remaining

- Phase 3, Item 3.1 — the subagent report relay, four slices: the keyed
  `gitlore_relay_marker_file` write/drain contract; both PostToolBatch reports
  relaying on the same wiring; SessionStart draining a marker that outlived its
  session; and a failed relay write not losing the subagent's own report.

- Item 1.2 after Phase 3 — the D-1 pin abort, `gitlore_compose_check_pins` at
  the `gitlore_sync_memory_to_live` call site, aborting on refusal.

- Phase 4, Items 4.0 through 4.3 — 4.0 narrows
  `docs/references/index-authoring-sync.md`, whose per-batch baseline invariant
  Item 2.1 falsified; then the decision node, the design/decisions conclusion,
  and the changelog's two surfaces.

- Write the orchestration fact to memory: every one of three `edify:test-driver`
  GREEN dispatches went idle waiting on a background `just precommit` completion
  notification that a subagent does not reliably receive, each time despite an
  explicit instruction in its prompt not to wait for one. Instructing the agent
  does not work; the orchestrator owning the gate does, and that is now the
  standing dispatch contract.

- Write the ambient-`CLAUDECODE` fact to memory: a subagent dispatch exports
  `CLAUDECODE=1`, so a bats test that branches on it passes under dispatch and
  fails for a human or CI.

- Write the report-cannot-cite-its-own-commit fact: a slice report committed
  *with* the work cannot carry that commit's sha, because amending the report in
  changes it. Item 2.1 slice 2's report names `b76a253`, which is not in the
  log; slice 3's identifies its commit by subject instead.

- Write the citation-boundary fact: shipped plugin source must not cite files
  under `memory/`, which reach the tree through a submodule gitlink and are not
  distributed. The only precedent in `scripts/` is `scripts/lib/util.sh:442`
  citing `docs/design.md`; a slice 4 review fix had to be retargeted for this.

- Record that `find` on this box is `bfs`, which rejects `-newermt '-60 minutes'`
  with `Invalid timestamp` and accepts only ISO 8601-like forms — a relative
  `-newermt` returns nothing and, under `2>/dev/null`, reads as "no files
  matched" rather than as an error.

- Narrow `test-unit`'s gate inputs to exclude `tests/integration_*` once the
  split has run a while; all three gates share `precommit_inputs` for now, which
  is why `test-unit` and `test-integration` carry the same input hash.

- Triage `inbox/brief-add-tier-index-budget-advisory.md`: `/gitlore:add-tier`
  composes the root index but cannot warn that the result overflows the loader
  cutoff, and the mount is the one operation that adds tens of KB in a single
  step.

- Split the oversized token-keyed facts so recall reaches them:
  `hook-output-channels` (23% reachable), `bats-shellcheck-gotchas` (40%),
  `stale-plugin-code` (45%), `design-doc-writing` (over 4KB, and being cut into a
  craft skill — check before splitting). Hub under 4KB carrying the symptom
  table, siblings beside it. `subagent-hook-output-confined` is a natural sibling
  of `hook-output-channels` once the hub exists.

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