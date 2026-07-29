## Current task

No thread is mid-flight. The `docs/design.md` cleanup is finished end to end: the changelog is its own file, the tables are prose, D10-D19 state present-tense mechanism, and NFR10 carries a measured figure (530 s over 620 cases, 2-vCPU droplet, `--jobs 2`, `user + sys` 566 s — the suite is barely parallel, so per-case work is the lever rather than `--jobs`).

The next substantial thread is the `memory/MEMORY.md` compaction, at ~92% of the 25600-byte advisory budget. It is deliberately not started: `feedback_index_compaction_triggers` requires an adversarial audit of the diff by someone other than the author, and a rushed trim silently misroutes recall.

## Open decisions

- Upstream's compaction (`b044d35`/`d7a39ed`) cut `phantom dotfiles` and `own hooks.json unlink EROFS` from the `sandbox effects` index line, and `a brief dropped there leaves your task frame` from `no_in_place_other_repos`. Each of those literals now has zero occurrences anywhere in the index, so the facts are unreachable by their symptom strings even though the bodies still carry them. Restore the triggers, or accept the loss as intended compaction? The parallel `PostToolBatch` cut was restored on the different ground that it fell to one occurrence on a wrong line, which misroutes rather than merely losing reach.