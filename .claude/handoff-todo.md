## Open decisions

- When the three `memory/ddaanet/` facts that describe the parent hook committing memory get rewritten: `preflight-excludes-memory-submodule.md`, `gitlore-memory-administration-no-parent-commit.md`, and the `--no-verify` bullet of `shared-claude.md`. They stay true in every ddaanet repo until the release, because consumers run the installed plugin. Stated default: rewrite them in the release commit, through the memory-writing skill, with a summary approved then.
- Whether an agent told "Looks good, proceed." after a memory commit should also commit the staged memory pointer in the parent. Two of five eval runs did, unrequested; the eval's pointer check accepts it. Nothing in the orientation text speaks to it.
- Whether the `SessionStart` `fetch origin live` needs a timeout: it runs on every launch for a store with a real remote, and an unreachable remote is reported only once git gives up.

## Remaining

- Rerun `just evals`. It refuses to run sandboxed ("Claude Code API is not accessible"), so launch it with the sandbox disabled, in the background; it has no scenario filter, so it is the full suite at 5 trials per scenario. Read the verdict per scenario: "Basic memory commit" and "Tier write" now fail with `before approval` when memory moved during turn 1. The run directories are deleted, but each run's transcript survives under `~/.claude/projects/-tmp-gitlore-eval-<suffix>/`, the suffix being the `/tmp/gitlore-eval.<suffix>` path the run prints.
- If the approval sentence does not hold in the rerun, the gate needs something mechanical: since D58 a summary passed to `commit-memory.sh` counts as approved by construction, so the orientation text is the only thing between the agent and the commit.
- `plans/macos-check/out/` is untracked and belongs to no task in this frame; decide whether it is kept, ignored or removed.