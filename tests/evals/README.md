# Gitlore Evals

End-to-end evaluation suite for the gitlore memory-commit flow. Runs real CC sessions via the Claude Agent SDK and grades both pipeline compliance and commit-message quality.

## Why the Agent SDK

Both the Agent SDK and `claude --print --resume` can drive these evals — each fires the PostToolUse hooks, injects `hookSpecificOutput.additionalContext`, and supports the two-turn summarise-then-approve flow. The SDK is chosen for **efficiency at scale**: it holds one process across both turns, whereas each `claude --print` spawn re-primes the full session context (~40k cache-creation tokens) and pays ~10s process-startup latency every turn — overhead that dominates across the scenario × trial matrix. `--print --resume` is a viable lighter-weight harness if the SDK dependency is unwanted.

## Requirements

- `uv` in `$PATH` (manages the Python SDK dependency inline)
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
2. **Turn 1** — SDK runner: agent edits memory, triggers the flow (see below), agent summarises pending changes and stops
3. **Turn 2** — SDK runner resumes the session with the approval message; agent writes the commit-msg file (and may retry git commit depending on the scenario)
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
