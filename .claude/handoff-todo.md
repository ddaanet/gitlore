## Open decisions

- When the three `memory/ddaanet/` facts that describe the parent hook committing memory get rewritten: `preflight-excludes-memory-submodule.md`, `gitlore-memory-administration-no-parent-commit.md`, and the `--no-verify` bullet of `shared-claude.md`. They stay true in every ddaanet repo until the release, because consumers run the installed plugin. Stated default: rewrite them in the release commit, through the memory-writing skill, with a summary approved then.
- Whether an agent told "Looks good, proceed." after a memory commit should also commit the staged memory pointer in the parent. Some eval runs do, unrequested; the eval's pointer check accepts it. Nothing in the orientation text speaks to it.
- Whether the `SessionStart` `fetch origin live` needs a timeout: it runs on every launch for a store with a real remote, and an unreachable remote is reported only once git gives up.
- Whether `tests/evals/lib/real-claude.sh` should recognise only this repo's dogfood shim rather than any `plugin-dev/bin` entry on `PATH`. The tests in `tests/evals/lib/runner.bats` and `judge.bats` commit to the any-repo rule and fail a repo-anchored one. Stated default: keep the any-repo rule.
- Whether the `PreToolUse` hooks (`index-sync-pre.sh`, `edit-weld-pre.sh`) get the same death audit: exit 2 there blocks the tool call, and the plan leaves them out because an exit-0 report is the wrong default where a hook may need to fail closed.

## Remaining

- Execute `plans/batch-hook-deaths/plan.md` T1–T5. T1 first pins three unverified bash 3.2 behaviours the guard depends on (`exit` inside an `EXIT` trap, restoring a redirected stderr, an `ERR` trap under `set -E` handing `$BASH_COMMAND`/`$LINENO` to the `EXIT` trap); if any fails, the guard's design changes before T2.
- `plans/batch-hook-deaths/probe/run.sh` was relocated from `/tmp` and is lint-clean but has not been re-run from its new path; run one row unsandboxed before T5 cites it.
- Once D60 lands, drop a brief for `plugin-craft:hook-authoring` carrying the plan's exit-code table and the CC version: that skill says nothing of `PostToolBatch` exit 2 ending the turn or of the agent seeing nothing on exit 1. That repo is read-only from here.
- `tests/evals/README.md` describes how the eval repo's hooks are wired and does not say the runner bypasses the dogfood shim; add that, as prose, to Sonnet.
- `plans/macos-check/out/` is untracked and belongs to no task in this frame; decide whether it is kept, ignored or removed.
