## Current task

Migrate the gitlore sibling repos onto the shared `ddaanet` memory tier, one
repo at a time from inside each: `/gitlore:add-tier` in the repo, move that
repo's portable facts (`user` / CC-platform `reference` / portable `feedback`)
up into `ddaanet/`, then activate via the manifest. Not batchable — each mount
clones, and cross-repo git is classifier-denied, so it runs from the inside per
repo. Scope and the full worklist are in `memory/project_gitlore_global_memory.md`
(NEXT block): ddaanet is an org of one, so every gitlore sibling is a consumer;
public/private is not a tier boundary (the tier repo is private).

## Open decisions

- Re-rank the worklist by portable-fact COUNT per repo, not `MEMORY.md` byte
  size — a large index can be mostly `project` facts that stay put, so count is
  the real per-repo payload. Do this ranking first next session.
- Whether `general` is a gitlore repo at all — no gitlore wiring was detected in
  its `.claude/settings*.json`; verify before counting it in.
