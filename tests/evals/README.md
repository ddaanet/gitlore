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
1. Creates a fresh gitlore-installed repo with the scenario's initial memory content, and runs the scenario's fixture script if it names one
2. Records where the memory store stands, before the agent touches anything
3. **Turn 1** — eval runner: agent works the flow and stops
4. **Turn 2** — eval runner resumes the session with the approval message, for scenarios that have an approval gate
5. Runs the scenario's assertion script, which owns everything after the turns — including firing the parent `git commit`, where the flow has one

The eval repo's hooks are copied wholesale from the plugin's own `hooks/hooks.json`, with `${CLAUDE_PLUGIN_ROOT}` resolved. Derived, never hand-listed: a hand-written subset is a registration the evals never exercise, and an eval's whole point is to walk the wiring production ships. Skills and commands are copied in too, so the prompt contracts the agent reads are the real ones.

Fixtures reach no network — every remote in here is a local bare repo, and `GIT_CONFIG_*` loosens `protocol.file.allow` for the process tree so `git submodule add` can clone one.

### Flows covered

| Scenario | Assertion | What only an eval sees |
|---|---|---|
| 01 basic memory commit | `memory-commit` | PostToolUse `additionalContext` → summary → approval → commit |
| 02 dirty, no precommit | `memory-commit` | the pre-commit hook's exit-1 path as the fallback trigger |
| 03 add tier | `add-tier` | intent file → PostToolBatch hook mounts (agent runs no git) → manifest edit recomposes the root index |
| 04 tier write | `tier-write` | routing a portable fact to the tier, the mirror-down, and one approved summary committing memory *and* the tier |
| 05 active recall | `recall` | a probe surfaces the trigger mid-task → the agent Reads the body *after* it → the answer uses it |

### Trigger paths

**PTU injection path** (precommit command scenario): agent runs the configured precommit command (`true`), PostToolUse hook fires and injects `additionalContext`, agent summarises and stops. Turn 2 approval → agent writes commit-msg file. The assertion's `git commit` fires the pre-commit hook which commits memory.

**Pre-commit failure path** (no precommit command scenario): agent runs `git commit` directly, pre-commit hook exits 1 with the `$CLAUDECODE`-addressed error message, agent summarises and stops. Turn 2 approval → agent writes commit-msg and retries `git commit`, which succeeds. The assertion's subsequent `git commit` is a no-op on the memory side (already clean).

## Adding scenarios

Add a JSON file to `tests/evals/scenarios/`:

```json
{
  "name": "Human-readable name",
  "description": "What this tests",
  "initial_memory": "Initial content of memory/MEMORY.md",
  "prompt": "Turn 1 user message",
  "approval_message": "Turn 2 message — omit for a single-turn flow",
  "setup": "name of a script in setups/ — omit if the base fixture is enough",
  "assert": "name of a script in asserts/ — defaults to memory-commit",
  "rubric": "Pass/fail criteria for the commit message, where one is judged"
}
```

`{{EVAL_REPO}}` in a prompt expands to the trial's throwaway repo. A scenario that has to name something the fixture created — a tier remote's URL — can only learn its path at trial time, and telling the agent to go find it would grade a search instead of the flow.

The runner processes all `*.json` files in scenarios/ alphabetically.

### Assertion scripts

`asserts/<name>.sh` runs after the turns with `EVAL_REPO`, `EVAL_OUT_DIR`, `EVAL_RUBRIC`, `EVAL_TRIGGER`, `PLUGIN_ROOT` and `LIB_DIR` in the environment. Exit 0 to pass; exit non-zero with the reason on stdout to fail.

`EVAL_OUT_DIR` holds `turn1.txt` / `turn2.txt` (each turn's final text), `session-id`, `memory-baseline` (memory's HEAD before the agent ran), and `transcript.jsonl` — the session transcript, which is how an assertion sees which *tools* ran. Some contracts are only visible there: active recall is meant to fire on a trigger that surfaced mid-task, and Claude Code's own prompt-time recall leaves an identical repo and an identical answer — only the order of the tool calls tells them apart.

Assertions are themselves tested, in `lib/asserts.bats`, against a good end state and against the specific breakage each one exists to catch. An assertion that always passes turns its scenario into an expensive no-op, and the eval run looks green either way.

### Fixture scripts

`setups/<name>.sh` runs after the base fixture with cwd = `$EVAL_REPO`. A non-zero exit is reported as a setup failure rather than a graded one — a broken fixture and a failed flow want different fixes.
