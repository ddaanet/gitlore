# Gitlore Evals

End-to-end evaluation suite for the gitlore memory-commit flow. Runs real CC sessions via the `claude` CLI and grades both pipeline compliance and commit-message quality.

## The harness

`lib/claude-runner.sh` drives one `claude --print` process per turn; turn 2 replays the session by id via `--resume`. Hooks fire and `hookSpecificOutput.additionalContext` injects under `--print` (verified on 2.1.212), which is all these evals need from a harness.

This suite used the Claude Agent SDK until 2026-07-17. The SDK bought nothing: its `query()` is one-shot and stateless by design ("each query is independent, no conversation state"), spawning a subprocess per call and resuming by id — the same shape as `--print --resume`. Both re-prime the project context every turn. Measured on this repo (2026-07-17, trivial two-turn probe, warm cache, per two-turn trial):

| harness | cost | wall |
|---|---|---|
| SDK (`query()` ×2) | $0.379 | 14.4s |
| `claude --print --resume` | $0.425 | 24.3s |

The gap was ~5s of process startup per turn plus ~7k of context, the latter because the CLI loaded user settings while the runner passed `setting_sources=["project"]` — closed here by `--setting-sources project`. Across the 2-scenario × 5-trial matrix the remainder is roughly $0.5 and 2 minutes per run: fixed overhead that does not grow with turn length, and not worth a `uv` + Python + `claude-agent-sdk` dependency in a bash/bats suite. (`ClaudeSDKClient` is the SDK's stateful API and would give genuine process persistence; it also keeps the dependency.)

The SDK's `max_turns=20` runaway guard has no CLI equivalent; the runner uses `--max-budget-usd` instead (default `2.00`, override with `EVAL_MAX_BUDGET_USD`).

## Requirements

- `claude` in `$PATH` (2.1.212+, for `--setting-sources` and `--max-budget-usd`)
- `ANTHROPIC_API_KEY` set
- `jq` installed

## Running

```bash
make evals
```

Or directly:

```bash
tests/evals/run-evals.sh
```

## What it tests

Each scenario runs 5 trials (`pass^k`). A scenario passes only if all 5 pass.

Each trial:
1. Creates a fresh gitlore-installed repo with the scenario's initial memory content
2. **Turn 1** — eval runner: agent edits memory, triggers the flow (see below), agent summarises pending changes and stops
3. **Turn 2** — eval runner resumes the session with the approval message; agent writes the commit-msg file (and may retry git commit depending on the scenario)
4. Fires `git commit` to trigger the pre-commit hook (if memory not already committed by the agent)
5. Asserts: memory committed, `live` ff-pushed, commit-msg temp file deleted
6. LLM judge grades commit message quality against the scenario rubric

### Trigger paths

**PTU injection path** (precommit command scenario): agent runs the configured precommit command (`true`), PostToolUse hook fires and injects `additionalContext`, agent summarises and stops. Turn 2 approval → agent writes commit-msg file. Eval's `git commit` fires the pre-commit hook which commits memory.

**Pre-commit failure path** (no precommit command scenario): agent runs `git commit` directly, pre-commit hook exits 1 with the `$CLAUDECODE`-addressed error message, agent summarises and stops. Turn 2 approval → agent writes commit-msg and retries `git commit`, which succeeds. Eval's subsequent `git commit` is a no-op on the memory side (already clean).

## Adding scenarios

Add a JSON file to `tests/evals/scenarios/` with these fields:

```json
{
  "name": "Human-readable name",
  "description": "What this tests",
  "initial_memory": "Initial content of memory/MEMORY.md",
  "prompt": "Turn 1 user message — should instruct Claude to edit memory and run the precommit command",
  "approval_message": "Turn 2 message — sent after Claude summarises pending changes",
  "rubric": "Pass/fail criteria for the commit message"
}
```

The runner processes all `*.json` files in scenarios/ alphabetically.
