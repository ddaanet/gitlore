## Open decisions

- The memory index against Claude Code's ~24,985-byte loader cutoff, per `plans/2026-08-27-memory-index-budget-decision.md`. Its standing changed: `plans/2026-09-02-ddaanet-design-moment-facts.md` finds that relocating the edify-only facts and merging by design moment frees ~4,600 bytes of the 26,617-byte ddaanet index, landing it under the cap with ~2,900 to spare, so the composition reorder (D29 layout rule, D36 rewrite, `gitlore_order_merge` in `index-composition.md`) is no longer forced by the budget. Decide: run the curation pass first and re-measure, or still reorder.
- Which of the gitlore-side tier merges in `plans/2026-09-02-ddaanet-design-moment-facts.md` to execute: `plan-writing` (7 facts → 1, after edify takes the cap specifics), `guard-design` (3 → 1), folding `test-the-invocation-path` into `green-is-not-evidence`, `imperative-form-scope` into `skill-description-purpose-first`, `markdown-formatter-choice` into `claude-plugin-dev`, `bash-prolog-common-foundations` into `justfile-gotchas`, `no-transition-special-cases` into `remove-cleanly-no-vestigial`; and whether `loose-generation` gets a trigger or is retired.
- `reconstructable-two-categories` is a handoff-design lesson: whether to drop a note in the handoff repo proposing it move to handoff's own store (other repos are read-only; a note is the permitted end of involvement).

## Remaining

- Execute the approved tier-side merges through the memory-writing skill, then `/gitlore:push`.
- Add to the memory-writing skill's index-line guidance: a fact whose trigger is a design moment needs either a symptom-shaped hook or a home at a skill checkpoint, else it is never read (evidence: the 20 never-read facts in `plans/2026-09-02-recall-log-analysis.md`).
- Rerun `plans/2026-09-02-recall-log-analysis.py` once a week or two of native-recall attachments exist; report the harness class and selector precision (first delivery: 5 files, 2 off-target, selected from a skill body rather than the user's words).
- Continue the ddaanet review pass from the queue in `plans/ddaanet-memory-review.md` (entry 5, `hook-output-channels`).
- `docs/design.md` sits at exactly the 400-line cap; the next hub addition needs a split decision.
