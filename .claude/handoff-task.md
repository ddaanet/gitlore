## Current task

The path-keyed three-way root↔carrier compose rework and the live ddaanet heal
are complete, tested (`just precommit` green), and verified (root ddaanet 78 /
carrier 78 / 0 dangling / carrier clean at `origin/live`). The FR11 parent commit
lands this episode. The next body of work is the sibling-repo migration worklist
documented in `memory/project_gitlore_global_memory.md` — promote each repo's
portable facts into the `ddaanet/` tier, front-loaded handoff → micro per the
distinct-yield ranking; every repo's `/gitlore:add-tier` now self-triages.

## Open decisions

- Push of the FR11 parent commit is held for David's diff review. Safe when it
  happens: local ddaanet `live` now equals `origin/live`, so the tier has nothing
  to push — the corrupt unpushed `cabd7c6` is unreachable and never propagates.
