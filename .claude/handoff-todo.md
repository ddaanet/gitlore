## Open decisions

- `brief-orphaned-merge-head-no-state-file.md` (untracked, repo root): whether to write the merge-state file *before* `gitlore_prepare_merge` and upgrade it on success, which would make `orphaned-merge-head` (MERGE_HEAD, no state file) unreachable and fold it into the landed/staged/dead classifier `gitlore_recover_stale_no_merge_head` already runs; and separately whether `gitlore_prepare_merge` should read `pending` from `live` rather than HEAD. The brief's line 94 reasons about `abort-then-retry`, which no longer exists — a prepared merge is always continued.

## Remaining

In this order, each its own commit, gated by `just precommit` (split per CLAUDE.md Testing — one invocation outruns the tool cap):

- SessionStart repair of a store with no root `MEMORY.md` (see the task file).
- `brief-orphaned-merge-head-no-state-file.md` — settle the open decision above, then implement; file the brief under `plans/` once applied.
- `brief-commit-memory-missing-skill.md` (untracked, repo root): add a `commit` skill for `commit-memory.sh`, the shape `skills/push/SKILL.md` uses for `pushCommand`; read `commit-memory.sh`'s actual CLI first (`-m <summary> | -F <file> | -F -`, usage exit 2 on a missing operand). File under `plans/` once applied.
- Propose upstream to the `cwd-safety` plugin: its PreToolUse hook matches `cd` textually inside heredoc bodies and quoted inline scripts, refusing commands that never change directory; workaround is writing the script to a file. Other repo — propose, never edit.
- `/ddaa:preflight`.
- Release — only after preflight. 0.5.0 consumers still run the `sh -c` sentinel replay and `abort-then-retry`, and their test suite and `lint-shell.sh` do not run on macOS.
- Propose the two `plugin-dev/` NITs from the first audit upstream in claude-plugin-dev (vendored; never edit in place).
- `memory/MEMORY.md` is over Claude Code's 24.4KB loader cutoff, so tail entries are silently dropped every session; fix by retiring and merging entries, never by shortening lines to hit the number.
