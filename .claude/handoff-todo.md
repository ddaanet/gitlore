## Open decisions

- The memory index against Claude Code's ~24,985-byte loader cutoff, per
  `plans/2026-08-27-memory-index-budget-decision.md`. The ddaanet index is
  26,410 bytes and truncating today. `plans/2026-09-02-ddaanet-design-moment-facts.md`
  frees ~4,600 by relocation and merges; the three briefs would free a further
  ~10,400 (craft 4,748, plugin-craft 3,659, shell-scripting 2,042). Decide: run
  curation first and re-measure, or still do the composition reorder (D29 layout
  rule, D36 rewrite, `gitlore_order_merge` in `index-composition.md`).
- Which gitlore-side tier merges from `plans/2026-09-02-ddaanet-design-moment-facts.md`
  to execute: `plan-writing` (7 facts → 1), `guard-design` (3 → 1), folding
  `test-the-invocation-path` into `green-is-not-evidence`, `imperative-form-scope`
  into `skill-description-purpose-first`, `markdown-formatter-choice` into
  `claude-plugin-dev`, `bash-prolog-common-foundations` into `justfile-gotchas`,
  `no-transition-special-cases` into `remove-cleanly-no-vestigial`; and whether
  `loose-generation` gets a trigger or is retired. Several of these facts are
  also brief-bound, so the order matters: merge then convert, or convert then
  merge.
- `sandbox-effects` (31KB, 13% reachable): split into a hub plus siblings using
  the symptom table it already carries at the top, and/or a `prohibitions`
  PostToolUse(Bash) hook that annotates phantom-dotfile output at the moment of
  confusion. Separately, whether a one- or two-line prohibition (never delete,
  commit or report a phantom dotfile) belongs in `shared-claude.md`.
- Whether the guard and validation design facts go to the new `craft` plugin
  (the current default) or to `prohibitions`, whose stated premise is hooks
  replacing always-on prose.
- Whether the toolkit release-and-vendoring skill belongs in `plugin-craft` or
  in `claude-plugin-dev`'s own `toolkit/README.md`, which already ships with the
  vendored files. Raised in that brief and left open there.
- `reconstructable-two-categories` is a handoff-design lesson: whether to drop a
  note in the handoff repo proposing it move to handoff's own store (other repos
  are read-only; a note is the permitted end of involvement).

## Remaining

- Execute the approved tier-side merges through the memory-writing skill, then
  `/gitlore:push`.
- Split the oversized token-keyed facts so recall reaches them: `sandbox-effects`
  (13% reachable), `hook-output-channels` (23%, grew past the cliff in this
  session's tier merge), `bats-shellcheck-gotchas` (40%), `stale-plugin-code`
  (45%). Hub under 4KB carrying the symptom table, siblings beside it.
- Extend the memory-writing skill's index-line guidance to both axes: a
  design-moment trigger needs a symptom-shaped hook or a home at a skill
  checkpoint, and a body past 4096 bytes is unreachable beyond that point
  whatever its trigger.
- Rerun `plans/2026-09-02-recall-log-analysis.py` once a week or two of
  native-recall attachments exist; report the harness class and selector
  precision.
- Continue the ddaanet review pass from the queue in
  `plans/ddaanet-memory-review.md` (entry 5, `hook-output-channels` — its content
  changed in this session's merge).
- `docs/design.md` sits at exactly the 400-line cap; the next hub addition needs
  a split decision.
