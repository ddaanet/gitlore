## Open decisions

- `record-rewrite.sh --rebuild` (re-review R2 fix: keep every parseable line of the remote record, merge the commit-map, replace with `--force-with-lease`, no delete window; new D-entry). Stated default: yes — the agent is building it on that default.
- Inbox briefs (six under `inbox/`): my human partner said to hold them until the rest of the backlog is done.

## Remaining

- On a green `just precommit` (log `/tmp/claude-1000/gitlore-backlog/precommit-main.log`): parent commit on `dev` recording the memory gitlink plus `.claude/rules/shell.md` (links to skill references), `docs/changelog/2026-09-20-the-bats-gates-keep-a-pass-per-suite.md` (timings cited via `git show a274b4c:…`), `docs/references/tiered-memory.md` (D48, D57), `docs/decisions.md` (D47's three rejected alternatives). Fold this TODO update into it.
- Merge `fix/lib-path` (reviewed clean at fb33c57) into `dev` with a merge commit, then remove `.claude/worktrees/lib-path` and the branch.
- `fix/rewrite-scripts`: wait for the agent's re-review fixes (R1–R4 in `/tmp/claude-1000/gitlore-backlog/review-rewrite-scripts.md`), re-review with the same reviewer, merge into `dev`, remove `.claude/worktrees/rewrite-scripts` and the branch.
- `tests/install_run.bats` writes into the real home directory; isolate `HOME`/`XDG_*`/`GITLORE_HOME` like the `run.sh` test in fb33c57.
- Drop a note in `/Users/david/code/sandbox-lies/inbox/`: `lib/probes.sh:169,310` cite the retired `no-stderr-suppression` memory fact; the content now lives in the shell-gotchas skill's `references/robustness.md`.
- The Claude worktree `.claude/worktrees/agent-a72e34055c290a9aa` (branch `worktree-agent-a72e34055c290a9aa`, merged into `dev`) is locked by the harness; remove it and the branch once released.
- Removing a worktree prints `error: could not lock config file .git/config` even unsandboxed; cause unknown.
- `tier-triage-nudge` is fully merged into `dev`; deleting it with `git branch -d` is my human partner's call.
- Delete each `gitlore/archive/2026-10-15` branch (tier and memory store) on or after 2026-11-15.
- Simplification (my human partner's plan): agent commits memory directly via heredoc + script, no hook commits, no memory pre-commit approval gate, no SessionStart ff — explicit `gitlore:merge` only. G3 (identity scrub) is moot under it; record that in the simplification's D-entry.
- A clone taking in the rewritten parent history needs one `git fetch --no-recurse-submodules origin` (old subtree squash `1f981ed` carries a `memory` gitlink `59ed770` that exists nowhere); after that a plain fetch works.