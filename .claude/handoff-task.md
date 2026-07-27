## Current task

This session cut `claude-plugin-dev` v0.4.2 (a retried `just release`
briefly produced a local-only v0.4.1 tag — never pushed, no GitHub
release, deleted) and pulled it into gitlore's `plugin-dev/` subtree.
gitlore's local `scripts/check-version.sh` (the mis-wired copy) is
deleted; the justfile's `check-version` recipe now calls the vendored
`release.just` recipe of the same name. `just precommit` is green.
Asked whether to push gitlore's `main` (several commits ahead of
`origin/main`, most pre-existing from before this session) — awaiting
an answer.

## Open decisions

- Push gitlore's `main` to `origin`, or hold.
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
