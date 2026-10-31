## Remaining

- Leftover D70 keys: installs predating D70 keep `gitlore.commitCommand`, `pushCommand`, `mergeCommand` and `memoryApprovalClauseFile` in `.git/config`; gitlore reads and unsets none of them. Left in place by decision; revisit only if they cause confusion.
- Postponed: propose a design for the silent tier-line loss. A line deleted from a tier index only, while root has it and HEAD carries it, is accepted by gitlore_compose_down's union merge, and no report fires.
- Plugin-creation (arriving from another session) should add new projects to `ddaanet/owned-projects.md`; wire it in when it lands.
- add-tier eval (`03-add-tier`): the step 7/8 comments in `tests/evals/asserts/add-tier.sh` still describe the mount riding the next memory commit, and no eval covers add-tier handing off to `gitlore:commit`.
- Delete each `gitlore/archive/2026-10-15` branch (tier and memory store) on or after 2026-11-15.

