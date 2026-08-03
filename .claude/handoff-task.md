## Current task

The ddaanet test memories are consolidated. `green-is-not-evidence` replaces
`tests-must-go-red`, `tests-that-cannot-discriminate` and
`tests-pass-for-the-wrong-reason` — eleven fixture and assertion shapes in one
catalogue, the structural rules for negatives carried over intact, roughly
2.5KB of duplication removed. The write-time residue moved to
`genuine-red-not-missing-sut`: green-at-first is not evidence, and one
inert-stub run reds a whole batch but proves absence rather than wrongness.
Nine inbound wikilinks across seven files were repointed and no reference to
the three retired slugs survives. `shared-trigger-means-merge` records the
heuristic that produced the merge.

The merged index hook keeps its full nine-shape enumeration: findability wins
over the roughly 400 bytes a trimmed hook would recover, so collapsing three
lines to one bought no index relief and none is sought.

## Open decisions

- Whether gitlore's recall replaces `additionalContext` injection with an
  instruction to batch-Read the memory files not yet in context. Injection
  truncates past ~2KB into a spill file and does not satisfy the Read
  requirement, so a memory just shown still needs a Read before it can be
  edited; a Read-based recall primes the update path and simplifies the ledger.
  What it gives up is unconditional delivery, since an instruction can be
  deferred mid-task — which is the condition recall exists for. Needs a
  `docs/design.md` entry stating what happens on non-compliance.