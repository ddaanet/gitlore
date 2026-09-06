## Open decisions

- The `docs/design.md` line cap, which blocks runbook item 4.2. The file is at
  exactly 400 lines and `MAX_LINES = 400` (`scripts/check-docs-links.py:55`)
  blocks every file under `docs/` as `oversized-file`; the design record needs
  about four more lines. The runbook states a default: give the hub its own cap,
  `HUB_MAX_LINES = 440`, selected by comparing against the existing `HUB`
  constant at `:53`, moving the three prose surfaces with it (module docstring
  `:29-31`, `check_size`'s docstring `:251-253`, and the block message, which
  interpolates the constant) and adding a case to `tests/check_docs_links.bats`
  beside the 400-line filler pair at `:371`/`:383`. The alternative is splitting
  `docs/design.md` — which `check_size`'s own docstring prefers, but which means
  teaching the checker about a two-file hub, since the hub is where it collects
  decision conclusions. Compressing four lines out of §Architecture was rejected
  in the outline. An instruction to split replaces item 4.2's second half and
  adds a phase.
- The memory index against Claude Code's ~24,985-byte loader cutoff, per
  `plans/2026-08-27-memory-index-budget-decision.md`. The root index reports
  102% of budget and is truncating.
  `plans/2026-09-02-ddaanet-design-moment-facts.md` frees ~4,600 by relocation
  and merges, and the three dropped briefs a further ~10,400. Decide: run
  curation first and re-measure, or still do the composition reorder (D29
  layout rule, D36 rewrite, `gitlore_order_merge` in `index-composition.md`).
  `sandbox-effects` holds 988 bytes of the overshoot and retires as
  sandbox-lies phase 4, which changes the arithmetic.
- Which gitlore-side tier merges from
  `plans/2026-09-02-ddaanet-design-moment-facts.md` to execute: `plan-writing`
  (7 facts to 1), `guard-design` (3 to 1), folding `test-the-invocation-path`
  into `green-is-not-evidence`, `imperative-form-scope` into
  `skill-description-purpose-first`, `markdown-formatter-choice` into
  `claude-plugin-dev`, `bash-prolog-common-foundations` into
  `justfile-gotchas`, `no-transition-special-cases` into
  `remove-cleanly-no-vestigial`; and whether `loose-generation` gets a trigger
  or is retired. Several are brief-bound, so order matters: merge then convert,
  or convert then merge.
- Whether the guard and validation design facts go to `craft` (current default)
  or to `prohibitions`.
- Whether the toolkit release-and-vendoring skill belongs in `plugin-craft` or
  in `claude-plugin-dev`'s own `toolkit/README.md`, which already ships with
  the vendored files.
- `reconstructable-two-categories` is a handoff-design lesson: whether to drop
  a note in the handoff repo proposing it move to handoff's own store.
- Whether a one- or two-line phantom-dotfile prohibition (never delete, commit
  or report one) goes into `memory/ddaanet/shared-claude.md`. No hook fires on
  the `` !`cmd` `` expansion path, so prose is the only mechanism that covers
  the `/commit` `## Context` case.
- Whether `2026-09-02-bang-expansion-hook-decompile.md` belonged in the move to
  sandbox-lies. It was tracked here, and its finding — no hook dispatches on
  the `` !`cmd` `` path — matters to gitlore independently as a hook-heavy
  plugin.

## Remaining

- Finish `/proof` on `plans/index-edit-propagation/runbook.md`, then
  `/orchestrate` it in a fresh session.
- Fold a one-line fix into Phase 1 execution: the comment at
  `tests/index_compose.bats:930-931` says the `chmod a-w` induction stops the
  temp file being created in the carrier's directory. `gitlore_compose_write`
  puts its temp in the store's gitdir (`scripts/lib/index-compose.sh:656`), so
  what the chmod actually fails is the `mv` at `:676`.
- Triage `inbox/brief-add-tier-index-budget-advisory.md`: `/gitlore:add-tier`
  composes the root index but cannot warn that the result overflows the loader
  cutoff, and the mount is the one operation that adds tens of KB in a single
  step.
- Split the oversized token-keyed facts so recall reaches them:
  `hook-output-channels` (23% reachable), `bats-shellcheck-gotchas` (40%),
  `stale-plugin-code` (45%). Hub under 4KB carrying the symptom table,
  siblings beside it. `subagent-hook-output-confined` was written as its own
  file rather than a section of `hook-output-channels` for exactly this
  reason, and is a natural sibling once the hub exists.
- Extend the memory-writing skill's index-line guidance to both axes: a
  design-moment trigger needs a symptom-shaped hook or a home at a skill
  checkpoint, and a body past 4096 bytes is unreachable beyond that point
  whatever its trigger.
- Rerun `plans/2026-09-02-recall-log-analysis.py` once a week or two of
  native-recall attachments exist; report the harness class and selector
  precision.
- Continue the ddaanet review pass from the queue in
  `plans/ddaanet-memory-review.md` (entry 5, `hook-output-channels`).
- Check the bang-expansion decompile report's verbatim excerpts against the CC
  2.1.258 bundle before trusting its verdict; it now lives at
  `sandbox-lies/plans/2026-09-02-bang-expansion-hook-decompile.md`.
