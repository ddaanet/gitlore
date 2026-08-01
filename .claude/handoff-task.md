## Current task

Nothing is mid-flight. `brief-test-suite-negatives-rewrite.md` is applied over
its named `run !` scope and over the three classes its census missed —
`[ -z "$output" ]`, `[ ! -f/-e ]` and `[[ … != *…* ]]` — with each guard mutated
singly to confirm which test watches it. The clauses of the paired-negative rule
that did not survive contact with a real suite are recorded in
`memory/ddaanet/feedback_mutation_check_negatives.md`.

## Open decisions

- Whether an applied brief belongs in `plans/` or stays in the root inbox.
  `brief-docs-plans-layout.md` and `brief-test-suite-negatives-rewrite.md` are
  both applied and both still sit at the repo root, while
  `brief-compose-full-tier-clear-gap.md` and
  `brief-memory-commit-batch-model-channel.md` moved into `plans/`.
- Whether to bump the plugin version and release now, or batch the release with
  the remaining memory work. The D21 detector reaches no other repo until a
  release lands and each repo runs `/plugin update`, so every session started
  elsewhere in the meantime keeps the failure it exists to explain.
- `scripts/lib/util.sh`'s stale-hooksDir wrapper hint is pinned by no test — the
  same unpinned-literal class the rewrite just closed elsewhere, and outside the
  three classes this pass covered. Whether the emitted wrapper text is worth
  pinning, or is deliberately left loose.
- Whether the ~58 `[ ! -f/-e ]` sites that sit beside a positive in their own
  test body are worth mutating individually. They were read and screened
  mechanically for tests whose only assertion is a file absence, not pinned one
  guard at a time the way the rest of the pass was.