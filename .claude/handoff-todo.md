## Open decisions

- Where the `excludedCommands` whole-call-semantics skill lives. It has no
  symptom to match, so it is a skill rather than a hook; `craft` was my human
  partner's suggestion, but craft's own brief draws its boundary at "writing a
  document, a plan or a test" and this fires while configuring the harness
  sandbox. Settles only once the pilot says whether a sandbox plugin exists.
- Whether a one- or two-line phantom-dotfile prohibition (never delete, commit
  or report one) goes into `memory/ddaanet/shared-claude.md`. The `!`-expansion
  path is now proven out of hook reach, so prose is the only mechanism that
  covers the `/commit` `## Context` case.
- The memory index against Claude Code's ~24,985-byte loader cutoff, per
  `plans/2026-08-27-memory-index-budget-decision.md`. The root index is 26,171
  bytes and truncating; `sandbox-effects` alone holds 988 of that.
  `plans/2026-09-02-ddaanet-design-moment-facts.md` frees ~4,600 by relocation
  and merges, and the three dropped briefs a further ~10,400. Decide: run
  curation first and re-measure, or still do the composition reorder (D29
  layout rule, D36 rewrite, `gitlore_order_merge` in `index-composition.md`).
- Which gitlore-side tier merges from
  `plans/2026-09-02-ddaanet-design-moment-facts.md` to execute: `plan-writing`
  (7 facts to 1), `guard-design` (3 to 1), folding `test-the-invocation-path`
  into `green-is-not-evidence`, `imperative-form-scope` into
  `skill-description-purpose-first`, `markdown-formatter-choice` into
  `claude-plugin-dev`, `bash-prolog-common-foundations` into
  `justfile-gotchas`, `no-transition-special-cases` into
  `remove-cleanly-no-vestigial`; and whether `loose-generation` gets a trigger
  or is retired. Several are also brief-bound, so order matters: merge then
  convert, or convert then merge.
- Whether the guard and validation design facts go to `craft` (current default)
  or to `prohibitions`.
- Whether the toolkit release-and-vendoring skill belongs in `plugin-craft` or
  in `claude-plugin-dev`'s own `toolkit/README.md`, which already ships with
  the vendored files.
- `reconstructable-two-categories` is a handoff-design lesson: whether to drop
  a note in the handoff repo proposing it move to handoff's own store.

## Remaining

- Re-dispatch the bang-expansion decompile if
  `plans/2026-09-02-bang-expansion-hook-decompile.md` is absent — the subagent
  was still running at the session boundary and an in-process agent does not
  survive a clear. When the report exists, check its verbatim excerpts against
  the bundle before trusting the verdict.
- Run the pilot's layer 1: replay candidate matchers for the three detectors
  over every Bash `tool_result` in `~/.claude/projects` (~1,685 JSONL files
  across 60 projects), counting hits and classifying true vs false positives,
  then confirm the matchers would have caught the incidents `sandbox-effects`
  documents by date.
- Split the oversized token-keyed facts so recall reaches them:
  `hook-output-channels` (23% reachable), `bats-shellcheck-gotchas` (40%),
  `stale-plugin-code` (45%). Hub under 4KB carrying the symptom table,
  siblings beside it. `sandbox-effects` (13%) is the pilot's fallback rather
  than a standalone item.
- Extend the memory-writing skill's index-line guidance to both axes: a
  design-moment trigger needs a symptom-shaped hook or a home at a skill
  checkpoint, and a body past 4096 bytes is unreachable beyond that point
  whatever its trigger.
- Rerun `plans/2026-09-02-recall-log-analysis.py` once a week or two of
  native-recall attachments exist; report the harness class and selector
  precision.
- Continue the ddaanet review pass from the queue in
  `plans/ddaanet-memory-review.md` (entry 5, `hook-output-channels`).
- `docs/design.md` sits at exactly the 400-line cap; the next hub addition
  needs a split decision.