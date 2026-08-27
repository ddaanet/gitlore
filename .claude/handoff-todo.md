## Open decisions

- `brief-orphaned-merge-head-no-state-file.md` (untracked, repo root): whether to write the merge-state file *before* `gitlore_prepare_merge` and upgrade it on success, which would make `orphaned-merge-head` (MERGE_HEAD, no state file) unreachable and fold it into the landed/staged/dead classifier `gitlore_recover_stale_no_merge_head` already runs; and separately whether `gitlore_prepare_merge` should read `pending` from `live` rather than HEAD. The brief's line 94 reasons about `abort-then-retry`, which no longer exists — a prepared merge is always continued.

## Remaining

In this order, each its own commit, gated by `just precommit`:

- Shell-gotchas audit of the files unchanged since v0.5.0, macOS compatibility required (see the task file).
- SessionStart repair of a store with no root `MEMORY.md`: write the `# Memory Index` scaffold as a dirty file the next FR11 commit reviews, say so on `systemMessage`; record it in `docs/references/session.md` and the changelog. Motivated by `plans/brief-continue-after-merge-needs-root-index.md`'s third decision (the first two landed in `d54fc63`).
- `brief-orphaned-merge-head-no-state-file.md` — settle the open decision above, then implement; file the brief under `plans/` once applied.
- `brief-commit-memory-missing-skill.md` (untracked, repo root): add a `commit` skill for `commit-memory.sh`, the shape `skills/push/SKILL.md` uses for `pushCommand`; read `commit-memory.sh`'s actual CLI first. File under `plans/` once applied.
- `/ddaa:preflight`.
- Release — only after preflight. 0.5.0 consumers still run the `sh -c` sentinel replay and `abort-then-retry`.
- Propose the two `plugin-dev/` NITs from the audit upstream in claude-plugin-dev (vendored; never edit in place).
- `memory/MEMORY.md` is over Claude Code's 24.4KB loader cutoff, so tail entries are silently dropped every session; fix by retiring and merging entries, never by shortening lines to hit the number.
