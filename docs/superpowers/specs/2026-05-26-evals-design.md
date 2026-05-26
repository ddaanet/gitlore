# Evals Design — Memory Commit Flow

**Status:** Approved
**Date:** 2026-05-26

---

## Goal

Add an end-to-end eval suite that tests the gitlore memory commit flow through a real Claude Code session. Existing bats tests verify the shell pipeline deterministically; evals add coverage of the agent's behavior: does it correctly interpret the `additionalContext` signal, complete the multi-turn approval protocol, and produce a meaningful commit message?

---

## Scope

First scenario: the basic memory commit flow.

1. Agent edits `memory/MEMORY.md`
2. Agent runs the configured pre-commit command via Bash
3. `post-tool-use.sh` fires and injects `additionalContext` signaling the agent to write a commit summary
4. Agent generates a prose summary and presents it for user approval
5. User approves (second turn)
6. Agent writes the commit-msg temp file
7. Eval runner triggers `git commit`; the pre-commit hook commits memory and ff-pushes to `live`

---

## Directory Layout

```
tests/evals/
  run-evals.sh          # runner script
  lib/
    setup.sh            # repo lifecycle helpers (install, write memory, SessionStart)
    judge.sh            # LLM judge wrapper
  scenarios/
    01-basic-memory-commit.json
```

---

## Scenario Format

```json
{
  "name": "Basic memory commit",
  "description": "Agent edits MEMORY.md, pre-commit fires, agent summarizes, user approves — memory committed and live ff-pushed",
  "initial_memory": "# Memory\n\nInitial content.",
  "prompt": "Add a note to MEMORY.md that we are building an eval suite.",
  "approval_message": "Looks good, proceed.",
  "rubric": "Pass only if the commit message describes the actual change (adding an eval-suite note). Fail if it is generic (e.g. 'update memory') or mentions nothing about evals."
}
```

Fields:
- `initial_memory` — content written to `memory/MEMORY.md` before the session
- `prompt` — turn 1 user message
- `approval_message` — turn 2 user message (simulates explicit approval)
- `rubric` — passed to the LLM judge to assess commit message quality

---

## Runner Flow

`run-evals.sh` runs `k=5` trials per scenario. Each trial:

1. **Setup** — temp git repo, `install/run.sh memory "true"` (dummy pre-commit), write `initial_memory`, commit it, run `session-start.sh`
2. **Turn 1** — `claude --print --output-format json "$prompt"` in the repo directory; `post-tool-use.sh` fires automatically when the agent calls Bash with the pre-commit command
3. **Session ID** — parsed from the JSON output of turn 1
4. **Turn 2** — `claude --resume "$session_id" --print --output-format json "$approval_message"`; agent writes the commit-msg file
5. **Parent commit** — `git commit --allow-empty -m "parent: eval test"` triggers the pre-commit hook
6. **Outcome assertions** — must all pass before the judge runs
7. **LLM judge** — grades commit message quality against the rubric
8. **Trial result** — pass only if all assertions pass AND judge returns `pass`

Scenario passes (`pass^k`) only if all 5 trials pass.

---

## Graders

### Outcome Assertions (code-based)

| Assertion | Check |
|---|---|
| Memory committed | `git -C memory log --oneline` has ≥2 commits |
| `live` ff-pushed | `git -C memory rev-parse HEAD` == `git -C memory rev-parse live` |
| Commit-msg file gone | temp file path (from `git -C memory rev-parse --git-path gitlore-commit-msg`) does not exist |

Any assertion failure short-circuits the trial (no judge call).

### LLM Judge (`lib/judge.sh`)

Calls `claude --print` at temperature 0 with:
- The memory diff (`git -C memory show HEAD`)
- The commit message (`git -C memory log -1 --format=%B`)
- The scenario's rubric

Prompt shape:
```
You are a strict evaluator. Given the DIFF and COMMIT_MESSAGE below, decide
whether the commit message satisfies the RUBRIC. Reply with exactly one word:
pass or fail. Then on the next line, one sentence explaining why.

RUBRIC: <rubric>
DIFF: <git show output>
COMMIT_MESSAGE: <log -1 output>
```

Runner parses the first word of stdout (`pass`/`fail`). The explanation line is logged per trial for debugging.

---

## CI Integration

| Target | What runs | Blocks PR |
|---|---|---|
| `make test` | bats suite | Yes |
| `make evals` | `tests/evals/run-evals.sh` | No (opt-in) |

Evals require `ANTHROPIC_API_KEY`. They are slow (multiple CC sessions per trial × 5 trials × N scenarios) and non-deterministic, so they are not wired as a hard PR gate. The runner exits non-zero on any scenario failure, enabling future CI wiring once the suite stabilizes.

A `tests/evals/README.md` documents the `ANTHROPIC_API_KEY` requirement and how to run locally.

---

## What This Does Not Cover

- The resolve flow (`/gitlore:resolve`) — separate future eval
- Session restore after `git clone` — already covered deterministically by `integration_clone_restore.bats`
- The pre-push hook — future eval

