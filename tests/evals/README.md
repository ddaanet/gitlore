# Gitlore Evals

End-to-end evaluation suite for the gitlore memory-commit flow. Runs real CC sessions and grades both pipeline compliance and commit-message quality.

## Requirements

- `claude` CLI in `$PATH`
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
2. Runs `claude --print "<prompt>"` — agent edits memory, runs pre-commit, gets the `additionalContext` signal, generates a commit summary
3. Resumes the session with `claude --resume <id> --print "<approval>"` — agent writes the commit-msg file
4. Fires `git commit` to trigger the pre-commit hook
5. Asserts: memory committed, `live` ff-pushed, commit-msg temp file deleted
6. LLM judge grades commit message quality against the scenario rubric

## Adding scenarios

Add a JSON file to `tests/evals/scenarios/` with these fields:

```json
{
  "name": "Human-readable name",
  "description": "What this tests",
  "initial_memory": "Initial content of memory/MEMORY.md",
  "prompt": "Turn 1 user message",
  "approval_message": "Turn 2 approval message",
  "rubric": "Pass/fail criteria for the commit message"
}
```

The runner processes all `*.json` files in scenarios/ alphabetically.
