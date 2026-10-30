## Remaining

- Fact edit eval (`06-fact-edit-reason`) passes 2/5 on its judge rubric, even after the commit skill's no-retell rule was extended to the closing sentence. One failure still closes on the fact's new content; two fail for naming the old value, which the skill asks for ("what the old wording got wrong"). Reconcile the rubric with the skill before tuning the skill further.
- The shared fact `memory/ddaanet/preflight-excludes-memory-submodule.md` is false under D70 (says the parent pre-commit hook commits memory); rewrite it — dirty memory waits for its own approved commit, clean-tree gates still exclude the `memory` path. Commit memory via the gitlore:commit skill with an approved summary.
- Installed handoff 0.18.0 still uses the retired clause-file protocol, so its memory step is broken here until it updates.
- Leftover D70 keys: installs predating D70 keep `gitlore.commitCommand`, `pushCommand`, `mergeCommand` and `memoryApprovalClauseFile` in `.git/config`; gitlore reads and unsets none of them. The installed `handoff` plugin still reads `memoryApprovalClauseFile` and writes the retired message and trigger files, so that key stays meaningful there until handoff updates. Left in place by decision; revisit only if they cause confusion.
- Postponed: propose a design for the silent tier-line loss. A line deleted from a tier index only, while root has it and HEAD carries it, is accepted by gitlore_compose_down's union merge, and no report fires.
- Plugin-creation (arriving from another session) should add new projects to `ddaanet/owned-projects.md`; wire it in when it lands.
- Delete each `gitlore/archive/2026-10-15` branch (tier and memory store) on or after 2026-11-15.
- Push memory with the next parent push, via /gitlore:push first.
