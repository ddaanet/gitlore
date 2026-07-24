## Current task

Migrating the gitlore sibling repos onto the shared `ddaanet` memory tier — full worklist, true-portable ranking, and per-repo mechanics live in `memory/project_gitlore_global_memory.md` (NEXT block). **Step 0 is DONE**: gitlore's own portable facts were promoted into `ddaanet/` (54 promoted, 16 kept local, tier now 60 files, compose + dangling clean). Sibling migrations run one repo at a time from INSIDE each repo — a mount clones and cross-repo git is classifier-denied, so they cannot be driven from the gitlore session.

## Open decisions

- Sibling sequence: after Step 0, run a small clean PILOT (edify — already self-triaged into a "Global candidates" section — or cwd-safety, 3 facts all portable) to validate the per-repo mount→move→activate→commit flow end to end, then the two richest (handoff ~42, micro ~40). Ranked list is in the memory NEXT block.
- Deliberate ordering within a tier's index block: the current order is insertion-order (NOT size, despite appearances). Decide whether to add a sort to `gitlore_compose` (by `metadata.type`, alphabetical, or curated) or leave it insertion-order-preserving.
- Borderline keep-local calls to revisit if the consumer-repo angle wins: the 3 specialist-deferred facts (`feedback_gitmoji`→gitmoji, `handoff_files_managed`/`handoff_with_commit`→handoff) and the deep memory-mechanics facts kept in gitlore-local.
- `general` and `micro` point their memory submodule at a local `./.git/gitlore-placeholder`, not a GitHub remote — their migration session must stand up a real remote before it can push.
