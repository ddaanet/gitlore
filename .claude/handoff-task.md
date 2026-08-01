## Current task

Nothing is mid-flight. `brief-test-suite-negatives-rewrite.md` is applied over
its named scope — the `run !` sites — and the four clauses of the paired-negative
rule that did not survive contact with a real suite are recorded in
`memory/ddaanet/feedback_mutation_check_negatives.md`.

## Open decisions

- Whether to extend the rewrite to the three classes the brief's census missed.
  It counted 20 sites as `refute_output`/`refute_line`/`assert_failure`, forms
  this suite does not use; those 20 map onto the `run !` sites. The untouched
  remainder is roughly 155 assertions: `[ -z "$output" ]` ~49, `[ ! -f/-e ]`
  ~70, `[[ … != *…* ]]` ~40.
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
  same unpinned-literal class the rewrite just closed in four other places.
  Whether the emitted wrapper text is worth pinning, or is deliberately left
  loose.