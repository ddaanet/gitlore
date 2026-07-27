## Current task

Two threads carried from the prior handoff: the open-decisions walk and
the memory proof pass (items 9-16, not started). This session resolved
decision 1 — `check-version.sh`'s three mis-wirings fixed and the script
moved into the `claude-plugin-dev` toolkit repo (committed there as
4f68836, unreleased — no tag cut yet). Two open decisions remain.

## Open decisions

- `tests/evals/lib/judge.sh`: land the 3-state exit (0 pass / 1 fail / 2
  invalid-or-unavailable, dropping the `2>/dev/null`) before or instead of
  hardening the verdict parse. Hardening the parse first strictly worsens
  reporting — it raises the unparseable rate while each new instance
  still arrives disguised as a rubric failure. Both call sites
  (`asserts/memory-commit.sh:59`, `asserts/tier-write.sh:145`) currently
  turn any non-zero into "commit message failed judge rubric" regardless
  of cause.
- The vanished `refs/gitlore/compose-base` pointer stays undiagnosed —
  the audit chain records only from this point forward, and the ref never
  left the machine (outside `refs/heads`, nothing pushes it), so a fresh
  clone starts blank. No path to close this one.
- When to cut a `claude-plugin-dev` release including `check-version.sh`,
  then run `just update-plugin-dev` in gitlore to adopt it and delete
  gitlore's local `scripts/check-version.sh` (still the old hardcoded,
  mis-wired version until then).
