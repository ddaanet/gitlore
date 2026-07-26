## Current task

Between tasks. The tier re-detach guard is landed, tested on both output
channels and mutation-checked; the next item is the `memory-commit-batch.sh`
silent-trigger case at the top of the todo file.

One finding from this session outlives it. `just precommit` exits 0 across
three consecutive full runs, with `tests/resolve_compose.bats` in the same
one-shot bats invocation as the other 43 suites — the recorded "test 1 fails
only in the full unit run, dropping a tier line from a composed root index"
does not reproduce, and nothing touched composition to explain why. That
failure was the handle on the unexplained live pointer loss, on the theory
that the two shared a mechanism. The handle is gone; the pointer loss is not.

## Open decisions

- How to recover a way in to the live pointer loss now that the suite is
  green. Either reproduce the drop directly against the live store (the
  `b=1, o=1, t=0` three-flag mechanism recorded in memory says what shape to
  build), or re-run the suite under the conditions that produced the red —
  different bats version, different `--jobs`, a dirtier tmp — to get it back.
  It still blocks 0.4.2, so a green suite must not be read as closing it.

- How to reconcile the 21 stale root-index pointers: drop each line, or trace
  where the fact now lives in a shared tier and redirect it. The SessionStart
  notice suggests another consumer merged or renamed them, so dropping blind
  would lose live facts. Either way the index must come under budget, and the
  byte cost is concentrated in a few long lines (`project_gitlore_global_memory.md`
  at 822 bytes, then `ddaanet/feedback_posttooluse_print_mode.md` at 623 and
  `reference_nested_submodule_tier.md` at 540).

- `micro` and `general` point their memory submodule at a local
  `./.git/gitlore-placeholder` rather than a GitHub remote. Each one's
  migration has to settle a real remote before its tier can push — decide
  whether that is worth doing inline or whether they drop to the end of the
  order.
