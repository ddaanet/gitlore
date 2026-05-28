# Gitlore Evals

End-to-end evaluation suite for the gitlore memory-commit flow. Runs real CC sessions via the Claude Agent SDK and grades both pipeline compliance and commit-message quality.

## Why the Agent SDK, not `claude --print`

`claude --print` (the `-p` flag) suppresses all hooks — PostToolUse never fires and `additionalContext` is never injected. The Agent SDK runs the full hook lifecycle, which is required to test the gitlore `post-tool-use.sh` flow. See [anthropics/claude-code#37559](https://github.com/anthropics/claude-code/issues/37559).

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
2. **Turn 1** — SDK runner: agent edits memory, runs the precommit command, PostToolUse hook injects `additionalContext`, agent summarises pending changes and stops
3. **Turn 2** — SDK runner resumes the session with the approval message; agent writes the commit-msg file
3. Fires `git commit` to trigger the pre-commit hook
4. Asserts: memory committed, `live` ff-pushed, commit-msg temp file deleted
5. LLM judge grades commit message quality against the scenario rubric

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
