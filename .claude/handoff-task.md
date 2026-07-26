## Current task

The quality-gate rework is finished — the gate lives in the justfile's
`bash_prolog`, hashes two declared input sets, and `tests/justfile_gates.bats`
covers it. Two threads are still live.

**The memory index is over its read limit.** `memory/MEMORY.md` is 25140 bytes
against a 24985-byte read limit and 98% of the 25600 budget. A compaction is
now forced rather than advisory, and `feedback_index_compaction_triggers`
requires an adversarial audit of the diff — last time the pass over-cut 15
lines. Nothing may be trimmed opportunistically to make room.

**The vanished-pointer bug reproduced once, with evidence.** During this
session's index edits, `- [loose generation + post-hoc fix]` for
`ddaanet/feedback_loose_generation.md` disappeared from both the root index
and the `ddaanet` carrier in a single compose pass. The file was tracked,
present on disk, and no dangling report fired. Re-adding the line to root and
composing again kept it, so a plain re-add does not reproduce it.

The evidence that matters, because it is about to be unrecoverable:
`refs/gitlore/compose-base` in the tier is blob `99cae0b`, and its pointer set
is now byte-identical to the post-drop carrier — compose refreshed the base
*after* the drop. That ref has no reflog (git does not keep one for a
non-branch ref by default), so the base as it stood before the drop is gone.
Every occurrence of this bug therefore destroys its own evidence, which is why
five sessions of green suites have not caught it.

## Open decisions

- How to bring `memory/MEMORY.md` under the read limit. Trimming the longest
  lines is what pays in bytes (`project_gitlore_global_memory` at 723,
  `ddaanet/reference_git_stderr_and_parsing` at 456), but those are the lines
  densest in routing triggers. The alternative is splitting the index, which
  the tier mechanism half-implements already.

- Whether compose should record the base it merged against — a reflog on
  `refs/gitlore/compose-base`, or a line in the compose report naming the blob.
  Without it the next drop is as undiagnosable as this one.

- Whether the `agents`/`commands`/`skills` exclusion from the precommit input
  set should stand. It is what was asked for, and it means an edit to any of
  those three leaves a green precommit green while `plugin_distribution`,
  `cc_hook_recall` and `cc_hook_add_tier` still assert on their real content.
