# 2026-07-17 — Eval harness dropped the Agent SDK for `claude --print --resume`

The SDK's stated rationale — holding one process across both turns so context
primes once — was false about its own code: `sdk-runner.py` called `query()`,
which is stateless (spawns a subprocess per call, replays via `resume`), the
same shape as `--print --resume`, so both re-primed context every turn. Measured
warm (README table), the SDK's whole edge was ~$0.05 / ~10s per two-turn trial:
process startup plus ~7k context, the latter because the CLI loaded user
settings while the runner passed `setting_sources=["project"]` — closed by
`--setting-sources project`. Not worth a `uv` + Python + `claude-agent-sdk`
dependency in a bash/bats suite. New `tests/evals/lib/claude-runner.sh` (~35
lines) keeps `sdk-runner.py`'s CLI contract; `--max-turns` has no CLI equivalent
so the runaway guard became `--max-budget-usd`. Gained 8 unit tests against a
mocked `claude` (the Python runner had none).
**Dogfooding found two live bugs the unit tests couldn't:** (1) the suite had
been red since 2026-07-16 — its assertions resolved
`git -C memory rev-parse --git-path gitlore-commit-msg`, a path production
abandoned in `431faf7` when the IPC file moved to
`.claude/gitlore-memory-message`; no harness could satisfy it, so the "2/2 SDK
baseline" predated the breakage and was never valid. (2) `claude -p` stalled
3s/turn on absent piped stdin → runner redirects `</dev/null`. Also: the API is
reachable *inside* the CC sandbox but `~/.claude/projects/` is read-only there,
so turn 1's transcript never persists and turn 2's `--resume` fails — the
single-turn pre-flight probe cannot detect this. Fixed run (`EVAL_K=5`,
unsandboxed):
**scenario 2 (pre-commit-failure path) 5/5; scenario 1 (basic-commit) 4/5**, the
one failure a genuine judge-rubric miss (a commit message that didn't name the
eval-suite change) — a real agent-side flake under `pass^k`, not a harness
regression, though it can't be compared to the SDK since no valid SDK baseline
exists. `run-evals.sh` now also captures the judge's stderr (its verdict,
reason, and the offending commit message) into `fail_reason`, where a rubric
failure previously reported *that* it failed but not *what*. Design.md's five
`gitlore-commit-msg` references (lines 81, 320, 323-324, 493) — which likely
seeded the eval's stale assumption — were then corrected to the current
`.claude/gitlore-memory-message` path and its `--show-superproject-working-tree`
resolution.
