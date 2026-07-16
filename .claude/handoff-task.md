## Current task

Dogfood the just-built PostToolBatch memory-commit trigger hook (`memory-commit-batch.sh`) — the agent writes `.claude/gitlore-memory-message` + `.claude/gitlore-commit-memory` and the hook commits memory on its behalf — which could not run this session because hook registration freezes at session start.

## Open decisions

- The live index-sync post-hook (`index-sync-post.sh`) still overwrites frontmatter on an *added* MEMORY.md line; apply the settled fill-if-empty rule (set `description:` only when it is empty) before running the D17 reconcile slice.
