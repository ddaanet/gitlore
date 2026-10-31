## Remaining

- Plan steps 1-11 of plans/2026-10-31-size-check-and-changelog-retirement.md: retire the changelog (D72), six node splits, two resolve-library splits, the memory-writing hub split, then wire check-size and retire the line check (D73); afterwards mark the plan done.
- Leftover D70 keys: installs predating D70 keep `gitlore.commitCommand`, `pushCommand`, `mergeCommand` and `memoryApprovalClauseFile` in `.git/config`; left in place by decision.
- Postponed: propose a design for the silent tier-line loss (tier-index-only deletion accepted by gitlore_compose_down's union merge, no report).
- Plugin-creation should add new projects to `ddaanet/owned-projects.md`; wire it in when it lands.
- Delete each `gitlore/archive/2026-10-15` branch (tier and memory store) on or after 2026-11-15.
- MEMORY.md sits at 95% of its 25600-byte budget; run /gitlore:index-audit when my human partner asks.
- No suite runs `tests/evals/setups/mounted-tier.sh`: add a bats case that runs it on a `make_parent_with_memory` fixture and asserts a clean store with the tier mounted and active.
