## Current task

No thread is mid-flight. The next substantial work is the `memory/MEMORY.md` compaction, now pressing at ~22.8KB against the 24.4KB read-truncation limit.

## Open decisions

- Upstream's compaction (`b044d35`/`d7a39ed`) cut `phantom dotfiles` and `own hooks.json unlink EROFS` from the `sandbox effects` index line, and `a brief dropped there leaves your task frame` from `no_in_place_other_repos`. Each of those literals now has zero occurrences anywhere in the index, so the facts are unreachable by their symptom strings even though the bodies still carry them. Restore the triggers, or accept the loss as intended compaction? The parallel `PostToolBatch` cut was restored this session on the different ground that it fell to one occurrence on a wrong line, which misroutes rather than merely losing reach.