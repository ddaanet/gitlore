## Open decisions

- **D-1 — whether a memory commit should adopt an off-pin tier gitlink.**
  Reproduced end-to-end against committed code through the `pre-commit` entry
  point: run 1 takes the rc-1 refusal, reports, and the commit's own `add -A`
  stages the tier's moved gitlink, removing the condition that made it refuse;
  run 2 projects root's older text over the carrier with no refusal at all, and
  `gitlore_sync_tiers_to_live` then commits it inside the tier and advances that
  tier's local `live`, which `pre-push` publishes. So the approved upstream fact
  is destroyed and then shipped, one commit after the warning. Not a regression
  — `add -A` predates the job. Options sized in the checkpoint report: (a) call
  `gitlore_compose_check_pins "$mempath"` at the call site before
  `gitlore_compose` and abort on its refusal — about six lines, pure reads,
  leaves the 0/1/2 contract and slice 4's stub test intact, costs the user a
  blocked parent commit until the pin is fixed; (b) exclude refused tiers from
  the memory `add -A` — three coupled changes, and it manufactures the
  live-ahead-of-pin state `strand_live_ahead_of_pin` exists to reproduce as a
  field defect; (c) record as a known residual. Recommended: (a), narrowed to
  the pin subset, as a follow-up item rather than inside Phase 1. It needs the
  runbook's rc-1 rule amended to "a compose_check refusal proceeds; a pin
  refusal aborts", which is why it is a decision and not a review fix. Note the
  earlier claim that (b) collides with the `GIT_INDEX_FILE` handoff is wrong:
  that is the parent repo's index, and Phase 2 does not touch `resolve.sh`.

- **D-2 — which of the four unpinned remedy sentences to assert.** Measured by
  in-place mutation against the committed tree: mutating any one of four whole
  sentences leaves both suites 33-green — the rc-1 **agent** sentence, the rc-2
  **agent** sentence, and both arms of `*)`. The rc-1 agent sentence is the fix
  `item-1-1-s3-code-review.md` made for its own Major 2 (it tells an agent the
  pin figure printed above is already stale), and it reverts silently. Closing
  all four is four `[[ "$stderr" == *"…"* ]]` lines in tests that already run
  with the right `CLAUDECODE` value and `--separate-stderr`, plus one extra case
  for the `*)` user arm. Not applied because the runbook enumerates each test's
  assertions by name, so it changes an accepted assertion list. Recommended:
  take the rc-1 and rc-2 agent sentences; leave the two `*)` ones as a recorded
  residual while `gitlore_compose` returns only 0, 1 or 2.

- **D-3 — the two tests that depend on ambient `CLAUDECODE`.**
  `tests/push_memory.bats:114` and `tests/tier_lockstep.bats:215` assert on
  strings that exist only in the agent arm (`scripts/lib/resolve.sh:1177`,
  `scripts/git-hooks/memory-pre-commit:16`), and neither sets nor unsets the
  variable — so they pass inside a subagent dispatch, which exports
  `CLAUDECODE=1`, and fail for a human or CI. The full unit suite under
  `env -u CLAUDECODE` goes 782 passed / 2 failed, exactly those two. One line
  each. Recommended: take it, outside this job.

- **D-4 — whether a successful commit-path compose should say anything.** On
  rc 0 the captured `$compose_result` (`composed memory/<tier>/MEMORY.md`, one
  line per file rewritten) is discarded, so a commit that repairs a stale
  carrier is silent. The counter-argument is that a non-empty result on the
  commit path means the in-session compose was missed, which is the hole this
  job exists to close. Cost: one `[ -n "$compose_result" ]` branch.
  Recommended: leave it, and record the reasoning in Phase 4's decision node.

- **D-5 — whether the suite neutralises `CDPATH`.** Every entry point under
  `scripts/` opens with `unset CDPATH`; `tests/helpers/setup.bash` does not, and
  six sites carry the raw `$(cd … && pwd)` pattern
  (`tests/helpers/fixtures.bash:25`, `tests/tier_divergence.bats:96,339,341,392`,
  `tests/index_compose.bats:259`, `tests/resolve_recovery.bats:339`). Measured
  with `CDPATH=.` exported, `tests/helpers/fixtures.bash:25` fails. The
  in-diff instance is already fixed. Recommended: one line in
  `tests/helpers/setup.bash`, as its own change outside this job.

- **D-6 — whether to correct the up-front tier guard's comment.** The loop
  iterates `gitlore_tier_paths` (every tier in `.gitmodules`) while
  `gitlore_compose` only writes into tiers listed in `.gitlore-tiers`, so the
  comment's justification is false for a dormant tier. The width is right
  anyway, because it mirrors `gitlore_sync_tiers_to_live`, which commits inside
  dormant tiers too. One sentence, stating ordering against the tier commits as
  the real reason.

- Whether `CLAUDE.md` §Testing's gate-sentinel rule should be rewritten. It
  tells an agent a sentinel is "valid for the tree when its mtime postdates the
  last edit to any gated input", but the mechanism is a content hash — the
  sentinel holds `cksum` output over the gate's declared inputs and `justfile`'s
  `check-sentinel` compares `gate-inputs-hash`. The heuristic is conservative
  (it can only read stale when the gate is fresh) but it produced a false alarm
  in two separate slice-4 dispatches. Two lines to fix; can ride Phase 4.

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
  on a tree whose only dirt is those phantoms — seen at the end of both Item 1.1
  and slice 4 — so a mechanical gate already misreads them as uncommitted work.

- Whether `2026-09-02-bang-expansion-hook-decompile.md` belonged in the move to
  sandbox-lies. Its finding — no hook dispatches on the `` !`cmd` `` path —
  matters to gitlore independently as a hook-heavy plugin.

- The recall-size hook fires on `memory/ddaanet/shared-claude.md` demanding it be
  cut under 2.8KB, but that file is imported whole by `CLAUDE.md` and is never a
  recall target, and it has been well past 4KB for a long time. Decide whether
  the hook should exempt the tier conventions file or whether the warning is
  doing something the exemption would lose.

## Remaining

- Write the ambient-`CLAUDECODE` fact to memory: a subagent dispatch exports
  `CLAUDECODE=1`, so a bats test that branches on it passes under dispatch and
  fails for a human or CI. Deliberately not written this session — a memory file
  would have put an FR11 approval round-trip inside a transition that was asked
  to run.

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

- Rerun `plans/2026-09-02-recall-log-analysis.py` once a week or two of native-recall
  attachments exist; report the harness class and selector precision.

- Continue the ddaanet review pass from the queue in
  `plans/ddaanet-memory-review.md` (entry 5, `hook-output-channels`).

- Check the bang-expansion decompile report's verbatim excerpts against the
  CC 2.1.258 bundle before trusting its verdict; it lives at
  `sandbox-lies/plans/2026-09-02-bang-expansion-hook-decompile.md`.
