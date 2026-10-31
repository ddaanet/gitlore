## Remaining

- Plan steps 2-5 of plans/2026-10-31-add-tier-direct-call.md: script with red tests, retire add-tier-batch.sh and sweep, command and eval at k=5, changelog entry.
- Leftover D70 keys: installs predating D70 keep `gitlore.commitCommand`, `pushCommand`, `mergeCommand` and `memoryApprovalClauseFile` in `.git/config`; gitlore reads and unsets none of them. Left in place by decision; revisit only if they cause confusion.
- Postponed: propose a design for the silent tier-line loss. A line deleted from a tier index only, while root has it and HEAD carries it, is accepted by gitlore_compose_down's union merge, and no report fires.
- Plugin-creation (arriving from another session) should add new projects to `ddaanet/owned-projects.md`; wire it in when it lands.
- Delete each `gitlore/archive/2026-10-15` branch (tier and memory store) on or after 2026-11-15.
- MEMORY.md sits at 95% of its 25600-byte budget; run /gitlore:index-audit when my human partner asks for curation.- No suite runs `tests/evals/setups/mounted-tier.sh`: a change to add-tier.sh broke it silently (fixed in D71 step 2 after a hand smoke run). Add a bats case that runs it on a `make_parent_with_memory` fixture and asserts a clean store with the tier mounted and active.
