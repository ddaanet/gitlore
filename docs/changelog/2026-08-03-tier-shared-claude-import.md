# 2026-08-03 — A tier can carry always-on conventions, and mounting one reports the `CLAUDE.md` import line

A rule that must change what the agent does by default has no lookup step, so a
memory pointer cannot serve it: the index is a routing table, and a line there
is only ever an invitation to read. Rules of that kind were accumulating in the
index anyway, where they cost bytes against Claude Code's 24.4KB loader cutoff
and routed nothing — the cutoff truncates the tail silently, so the pressure
they created was paid by the project-local memories composition orders last.

The `ddaanet` tier now carries `shared-claude.md` at its root: the always-in-
context tier of conventions binding on every repo that mounts it. Each consuming
repo imports it as `@memory/<tier>/shared-claude.md` in its own `CLAUDE.md`, and
the file loads whole, every session. Its scope is the gap between a repo's own
`CLAUDE.md` and the user's `~/.claude/CLAUDE.md` — one file, one edit, every
consumer, where copying the conventions per repo would drift across five copies.

The name is not `CLAUDE.md` on purpose. A file by that name inside the memory
store would be auto-injected whenever an agent touched that directory, which is
a store and not a place conventions apply, and it would collide with the
consuming repo's own root file.

`scripts/add-tier.sh` now reports the import line on a successful mount, and
`commands/add-tier.md` acts on it. Two conditions gate the report: the mounted
tier must actually carry `shared-claude.md`, because an `@` import naming a path
that does not exist loads nothing and says nothing about it; and the repo's
`CLAUDE.md` must not already carry the line, so a re-run stays quiet. The append
itself stays with the agent rather than the script — the same pass has to read
the imported file and delete from `CLAUDE.md` the rules it now states, which is
judgement rather than detection.

This repo's own `CLAUDE.md` took that pass in the same change: the
`AskUserQuestion` prohibition, the grounded-mechanism and real-pushback rules,
decide-late, the whole `Scope` section on other repos staying read-only, three
of the four `Design` bullets, and three `Testing` bullets all came out, because
the shared file states them. What stayed is what is specific to gitlore — the
recall protocol, the memory-commit and approval-summary rules, the writing
conventions, and the `just`/`run-bats.sh` invocations.
