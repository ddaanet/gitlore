## Remaining

- Probe whether CC 2.1.310 honors autoMemoryDirectory from trusted project settings (D10 may be stale; see the launcher containment notes in docs/references/memory-redirect.md).
- Fix the dangling `[[removing-cleanly]]` link in `memory/ddaanet/simplicity-no-unneeded-code.md` (likely means the `craft:removing-cleanly` skill); memory commit needs an approved summary.
- Simplification (my human partner's plan): the agent commits memory directly via heredoc + script, with no hook commits, no memory pre-commit approval gate and no SessionStart ff; only an explicit `gitlore:merge`. Record its D-entry, noting G3 as moot.
- Postponed: propose a design for the silent tier-line loss. A line deleted from a tier index only, while root has it and HEAD carries it, is accepted by gitlore_compose_down's union merge, and no report fires.
- Plugin-creation (arriving from another session) should add new projects to `ddaanet/owned-projects.md`; wire it in when it lands.
- Delete each `gitlore/archive/2026-10-15` branch (tier and memory store) on or after 2026-11-15.
- Push memory (owned-projects commit and the https tier-url commit) with the next parent push, via /gitlore:push first.