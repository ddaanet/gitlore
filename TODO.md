## Remaining

- D70: implement the memory commit simplification per `plans/2026-10-26-memory-commit-simplification-decision.md` and its removals file; record the D-entry when the code is true.
- Postponed: propose a design for the silent tier-line loss. A line deleted from a tier index only, while root has it and HEAD carries it, is accepted by gitlore_compose_down's union merge, and no report fires.
- Plugin-creation (arriving from another session) should add new projects to `ddaanet/owned-projects.md`; wire it in when it lands.
- Delete each `gitlore/archive/2026-10-15` branch (tier and memory store) on or after 2026-11-15.
- Push memory with the next parent push, via /gitlore:push first.
- D70 commit 4: a test that fills the `gitlore:commit` skill's summary template and pipes it to `bin/gitlore-commit`, so the skill's format and the script's section parser cannot drift apart (the subject-above-the-first-header template shipped in commit 1 and was refused on first real use).
