## Current task

Verify the gitlore `memory-merger` two-turn approval flow end-to-end in a fresh session — `/plugin install gitlore@ddaanet` (now installable; recurse-clone, agent-registration, and flat-command-name fixes are all pushed) or a fresh `--plugin-dir` session, then force a branch-vs-live memory divergence and run `/gitlore:resolve`, confirming the sub-agent dispatches, returns its synthesis, and waits for approval before running the continuation.

## Open decisions

- Once this verification closes Plan 04, whether to start Plan 05 (the memory redirect launcher, D10) — write that plan then, not before.
