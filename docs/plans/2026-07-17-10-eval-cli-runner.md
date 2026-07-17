# Eval CLI Runner Implementation Plan

> **For agentic workers:** execute this inline (superpowers:executing-plans). Do **not** dispatch a sub-agent per task — the whole change is ~35 lines of runner, ~70 of tests, and three comment fixes across files a single reader holds at once. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace `tests/evals/lib/sdk-runner.py` (Claude Agent SDK, run via `uv`) with a bash runner that drives `claude --print --resume`, removing the `uv` + Python + `claude-agent-sdk` dependency from an otherwise bash/bats suite.

**Architecture:** The SDK bought nothing the CLI lacks. `query()` is stateless — it spawns a subprocess per call and replays the session via `resume`, exactly as `claude --print --resume` does — so both harnesses re-prime context every turn. Measured warm (2026-07-17, README table), the SDK's whole edge is ~$0.05 and ~10s per two-turn trial: process startup, plus ~7k of context because the CLI loads user settings by default while the runner passed `setting_sources=["project"]`. `--setting-sources project` closes the context half. The replacement is a ~35-line bash script with the same CLI contract as `sdk-runner.py`, so `run-evals.sh` changes only in the path it calls and the dependency it checks.

**Tech Stack:** Bash (`set -euo pipefail`), `claude` CLI 2.1.212+, `jq`, bats-core (`tests/helpers/`).

## Global Constraints

- The new runner must keep `sdk-runner.py`'s exact CLI contract: `--cwd <path> --prompt <text> --approval <text>` for the two-turn flow, `--probe --cwd <path>` for the connectivity check, exit 0 on success and 1 on any failure, diagnostics to stderr.
- Settings parity with the SDK: pass `--setting-sources project`. The eval repo's gitlore PostToolUse hook lives in `<cwd>/.claude/settings.json` (`setup.sh:49-54`), so `project` is required; `user` must stay out so the operator's own `~/.claude` settings cannot contaminate a trial.
- Permission parity: `--permission-mode bypassPermissions`.
- **`--max-turns` has no CLI equivalent** (verified against `claude --help`, 2.1.212). `sdk-runner.py` passed `max_turns=20` purely as a runaway guard; the guard becomes `--max-budget-usd` (documented as "only works with --print"). The `--max-turns` flag disappears from the contract — no caller passes it (`run-evals.sh:75-77` never did).
- Every `claude` invocation uses `--output-format json` and is parsed with `jq`. Success is `.subtype == "success"`; the session id for turn 2 is `.session_id`. Both fields are confirmed present in this CLI's JSON result (2026-07-17 harness benchmark).
- Unit tests must not hit the network. Mock `claude` on `$PATH`, following the established pattern in `tests/evals/lib/judge.bats:16-23`.
- Shell style follows the repo: `set -euo pipefail`, shellcheck-clean. Note a comment beginning `# shellcheck` parses as a malformed directive — do not start any comment with that word.

---

## File Structure

- **Create** `tests/evals/lib/claude-runner.sh` — the two-turn + probe runner; drives `claude --print`/`--resume`. Sole responsibility: turn Claude sessions into an exit code.
- **Delete** `tests/evals/lib/sdk-runner.py` — superseded.
- **Modify** `tests/evals/run-evals.sh` — call `claude-runner.sh`; replace the `uv` dependency check with a `claude` check; drop the false "unlike `claude --print` which suppresses all hooks" comment (lines 7-9).
- **Modify** `tests/evals/lib/runner.bats` — the pre-flight test's fake runner becomes a shell stub; add direct tests for `claude-runner.sh`.
- **Modify** `tests/evals/lib/setup.sh:44-46` — the comment still explains the settings wiring in terms of the SDK.
- **Modify** `tests/evals/README.md` — "Why the Agent SDK" section, requirements, and the numbered flow.
- **Modify** `docs/design.md` — one Decision Log row (Task 2, after the dogfood settles the outcome).

Run the eval unit tests with `bats tests/evals/lib/`. Run the full suite with `make test` from the repo root. The evals themselves (`make evals`) need network and an unsandboxed environment.

---

### Task 1: Swap the harness

Build the runner test-first, then cut the suite over and delete the SDK in the same task: a runner nothing calls is dead code, and a reviewer cannot sensibly accept one half without the other. One commit.

This is a net coverage gain. `sdk-runner.py` had no unit tests at all — its argument handling and turn-2 resume wiring were only ever exercised by a live eval run.

**Files:**
- Create: `tests/evals/lib/claude-runner.sh`
- Modify: `tests/evals/lib/runner.bats` (append tests; rework the pre-flight test at lines 8-19)
- Modify: `tests/evals/run-evals.sh:5-29` and `:68-77`
- Modify: `tests/evals/lib/setup.sh:44-46` (comment)
- Modify: `tests/evals/README.md`
- Delete: `tests/evals/lib/sdk-runner.py`

- [ ] **Step 1: Write the failing tests**

Append to `tests/evals/lib/runner.bats`. The mock records each invocation's argv to `$MOCK_BIN/argv.log` and replies with a canned JSON result, so tests can assert on what the runner asked the CLI to do.

```bash
RUNNER="$BATS_TEST_DIRNAME/claude-runner.sh"

setup() {
  MOCK_BIN="$(mktemp -d "${TMPDIR:-/tmp}/runner-mock.XXXXXX")"
  export MOCK_BIN
  export PATH="$MOCK_BIN:$PATH"
}

teardown() {
  rm -rf "$MOCK_BIN"
}

# Mock claude: logs argv, prints one JSON result per call.
# $1.. — the `subtype` value for each successive call, in order.
_make_mock_claude() {
  local subtypes=("$@")
  printf '%s\n' "${subtypes[@]}" > "$MOCK_BIN/subtypes"
  cat > "$MOCK_BIN/claude" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$MOCK_BIN/argv.log"
n=$(wc -l < "$MOCK_BIN/argv.log" | tr -d ' ')
subtype=$(sed -n "${n}p" "$MOCK_BIN/subtypes")
printf '{"subtype":"%s","session_id":"sid-%s","result":"canned"}\n' "$subtype" "$n"
EOF
  chmod +x "$MOCK_BIN/claude"
}

@test "claude-runner: is executable" {
  [ -x "$RUNNER" ]
}

@test "claude-runner: probe exits 0 on a success result" {
  _make_mock_claude success
  run "$RUNNER" --probe --cwd "$BATS_TEST_TMPDIR"
  [ "$status" -eq 0 ]
}

@test "claude-runner: probe exits 1 on an error result" {
  _make_mock_claude error_during_execution
  run "$RUNNER" --probe --cwd "$BATS_TEST_TMPDIR"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "probe" ]]
}

@test "claude-runner: two turns, turn 2 resumes turn 1's session" {
  _make_mock_claude success success
  run "$RUNNER" --cwd "$BATS_TEST_TMPDIR" --prompt "do the thing" --approval "looks good"
  [ "$status" -eq 0 ]

  local turn1 turn2
  turn1=$(sed -n 1p "$MOCK_BIN/argv.log")
  turn2=$(sed -n 2p "$MOCK_BIN/argv.log")
  [[ "$turn1" =~ "do the thing" ]]
  [[ "$turn1" != *"--resume"* ]]
  [[ "$turn2" =~ "looks good" ]]
  [[ "$turn2" =~ "--resume sid-1" ]]
}

@test "claude-runner: passes project-only settings and bypass permissions" {
  _make_mock_claude success success
  run "$RUNNER" --cwd "$BATS_TEST_TMPDIR" --prompt "p" --approval "a"
  [ "$status" -eq 0 ]
  local turn1
  turn1=$(sed -n 1p "$MOCK_BIN/argv.log")
  [[ "$turn1" =~ "--setting-sources project" ]]
  [[ "$turn1" =~ "--permission-mode bypassPermissions" ]]
}

@test "claude-runner: turn 1 failure exits 1 without running turn 2" {
  _make_mock_claude error_during_execution success
  run "$RUNNER" --cwd "$BATS_TEST_TMPDIR" --prompt "p" --approval "a"
  [ "$status" -eq 1 ]
  [ "$(wc -l < "$MOCK_BIN/argv.log" | tr -d ' ')" -eq 1 ]
  [[ "$output" =~ "turn 1" ]]
}

@test "claude-runner: turn 2 failure exits 1" {
  _make_mock_claude success error_during_execution
  run "$RUNNER" --cwd "$BATS_TEST_TMPDIR" --prompt "p" --approval "a"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "turn 2" ]]
}

@test "claude-runner: --prompt without --approval is a usage error" {
  _make_mock_claude success
  run "$RUNNER" --cwd "$BATS_TEST_TMPDIR" --prompt "p"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "--approval" ]]
}
```

In the same pass, rework the pre-flight test already at lines 8-19 — rename it and swap the Python fake for a shell one:

```bash
@test "run-evals: exits 1 with sandbox hint when the runner probe fails" {
    local fake_lib="$BATS_TEST_TMPDIR/lib"
    mkdir -p "$fake_lib"
    # Replace the runner with one that always fails (simulates a sandboxed env)
    printf '#!/usr/bin/env bash\necho "probe: API not accessible" >&2\nexit 1\n' \
        > "$fake_lib/claude-runner.sh"
    chmod +x "$fake_lib/claude-runner.sh"

    run env LIB_DIR="$fake_lib" bash "$RUN_EVALS"

    [ "$status" -eq 1 ]
    [[ "$output" =~ "sandbox" ]]
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bats tests/evals/lib/runner.bats`
Expected: the 8 new tests FAIL — `$RUNNER` does not exist yet.

The reworked pre-flight test is the exception: it may pass for the wrong reason (`run-evals.sh` still probes `sdk-runner.py`, which is absent from `$fake_lib`, so it exits 1 on a missing file and the `sandbox` hint still matches). Its real evidence is Step 5, after the cutover. Do not read an accidental green here as coverage.

- [ ] **Step 3: Write the runner**

Create `tests/evals/lib/claude-runner.sh`:

```bash
#!/usr/bin/env bash
# CLI-based eval runner for gitlore.
#
# Drives a Claude Code session with the eval repo's .claude/settings.json hooks
# loaded (--setting-sources project), so the gitlore PostToolUse hook fires and
# its additionalContext injects.
#
# Each turn is its own `claude --print` process; turn 2 replays the session by id
# via --resume. The Agent SDK's query() worked the same way (stateless, one
# subprocess per call), which is why this suite carries no Python dependency.
# See README for the measured cost/latency comparison.
#
# Two-turn flow:
#   Turn 1 — agent edits memory, runs the precommit command, hook injects
#            additionalContext, agent summarises pending changes and stops.
#   Turn 2 — eval sends the approval message; agent writes the commit-msg file.
#
# Usage:
#   claude-runner.sh --cwd <path> --prompt <text> --approval <text>
#   claude-runner.sh --probe --cwd <path>   # connectivity check only
set -euo pipefail

CWD=""
PROMPT=""
APPROVAL=""
PROBE=0
# Runaway guard, replacing the SDK's max_turns=20 (no CLI equivalent exists).
MAX_BUDGET_USD="${EVAL_MAX_BUDGET_USD:-2.00}"

die() { printf '%s\n' "$1" >&2; exit "${2:-1}"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --cwd)      CWD="${2:-}";      shift 2 ;;
    --prompt)   PROMPT="${2:-}";   shift 2 ;;
    --approval) APPROVAL="${2:-}"; shift 2 ;;
    --probe)    PROBE=1;           shift ;;
    *)          die "usage: $(basename "$0") --cwd <path> [--prompt <text> --approval <text>] [--probe]" 2 ;;
  esac
done

[ -n "$CWD" ] || die "--cwd is required" 2

# Runs one turn; echoes the JSON result. $2, when set, is a session id to resume.
run_turn() {
  local prompt="$1" session="${2:-}"
  local args=(-p "$prompt"
              --output-format json
              --setting-sources project
              --permission-mode bypassPermissions
              --max-budget-usd "$MAX_BUDGET_USD")
  [ -z "$session" ] || args+=(--resume "$session")
  (cd "$CWD" && claude "${args[@]}")
}

# Echoes the result's session id; fails with a diagnostic when the turn did not
# end in `subtype: success`.
check_turn() {
  local label="$1" json="$2" subtype
  subtype=$(printf '%s' "$json" | jq -r '.subtype // "none"')
  [ "$subtype" = "success" ] || \
    die "eval: $label failed subtype=$subtype: $(printf '%s' "$json" | jq -r '.result // "no result"')"
  printf '%s' "$json" | jq -r '.session_id // empty'
}

if [ "$PROBE" -eq 1 ]; then
  json=$(run_turn "reply with the single word ok") || die "probe: no response from Claude Code CLI"
  subtype=$(printf '%s' "$json" | jq -r '.subtype // "none"')
  [ "$subtype" = "success" ] || die "probe: API error (subtype=$subtype)"
  exit 0
fi

[ -n "$PROMPT" ] && [ -n "$APPROVAL" ] || die "--prompt and --approval are required unless --probe is set" 2

# Turn 1: agent edits memory, triggers the flow, summarises, stops for approval.
t1=$(run_turn "$PROMPT") || die "eval: turn 1 yielded no result"
session_id=$(check_turn "turn 1" "$t1")
[ -n "$session_id" ] || die "eval: turn 1 returned no session id"

# Turn 2: user approves; agent writes the commit-msg file.
t2=$(run_turn "$APPROVAL" "$session_id") || die "eval: turn 2 yielded no result"
check_turn "turn 2" "$t2" >/dev/null
```

Make it executable — the suite has shipped a non-executable hook past its own tests before, and `run-evals.sh` invokes this by path, not through `bash`:

```bash
chmod +x tests/evals/lib/claude-runner.sh
```

- [ ] **Step 4: Cut `run-evals.sh` over and delete the SDK runner**

Replace `run-evals.sh:5-10` (the `uv` dependency check and the false SDK rationale):

```bash
set -e

# The runner drives the `claude` CLI in --print mode: hooks fire and
# additionalContext injects, with no Python/uv dependency.
command -v claude >/dev/null 2>&1 || { echo "error: claude not found (required for the eval runner)" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "error: jq not found (required for the eval runner)" >&2; exit 1; }
```

Replace the probe at `:22`:

```bash
if ! "$LIB_DIR/claude-runner.sh" --probe --cwd "$_probe_tmp" 2>/dev/null; then
```

Replace the invocation at `:75-77`:

```bash
    "$LIB_DIR/claude-runner.sh" \
      --cwd "$EVAL_REPO" --prompt "$prompt" --approval "$approval" \
      2>/dev/null || fail_reason="eval runner failed"
```

In the comment block at `:68-74`, change the opening line `# SDK runner (two turns):` to `# Eval runner (two turns):`.

Then drop the Python:

```bash
git rm tests/evals/lib/sdk-runner.py
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `bats tests/evals/lib/ && shellcheck tests/evals/lib/claude-runner.sh tests/evals/run-evals.sh`
Expected: all tests PASS — the 8 new ones plus the pre-flight test, now green because `run-evals.sh` probes the fake `claude-runner.sh` it was given. shellcheck silent.

- [ ] **Step 6: Fix the comments and docs the SDK left behind**

In `tests/evals/lib/setup.sh`, replace the comment at lines 44-46:

```bash
  # Wire the CC PostToolUse hook directly into settings.json.
  # This bypasses the plugin marketplace (which requires a cached install) and
  # works in both interactive and eval runs.  The eval runner passes
  # `--setting-sources project`, so claude loads hooks from <cwd>/.claude/settings.json.
```

In `tests/evals/README.md`, replace the title sentence (line 3) and the whole "Why the Agent SDK" section (lines 5-18) with:

```markdown
End-to-end evaluation suite for the gitlore memory-commit flow. Runs real CC sessions via the `claude` CLI and grades both pipeline compliance and commit-message quality.

## The harness

`lib/claude-runner.sh` drives one `claude --print` process per turn; turn 2 replays the session by id via `--resume`. Hooks fire and `hookSpecificOutput.additionalContext` injects under `--print` (verified on 2.1.212), which is all these evals need from a harness.

This suite used the Claude Agent SDK until 2026-07-17. The SDK bought nothing: its `query()` is one-shot and stateless by design ("each query is independent, no conversation state"), spawning a subprocess per call and resuming by id — the same shape as `--print --resume`. Both re-prime the project context every turn. Measured on this repo (2026-07-17, trivial two-turn probe, warm cache, per two-turn trial):

| harness | cost | wall |
|---|---|---|
| SDK (`query()` ×2) | $0.379 | 14.4s |
| `claude --print --resume` | $0.425 | 24.3s |

The gap was ~5s of process startup per turn plus ~7k of context, the latter because the CLI loaded user settings while the runner passed `setting_sources=["project"]` — closed here by `--setting-sources project`. Across the 2-scenario × 5-trial matrix the remainder is roughly $0.5 and 2 minutes per run: fixed overhead that does not grow with turn length, and not worth a `uv` + Python + `claude-agent-sdk` dependency in a bash/bats suite. (`ClaudeSDKClient` is the SDK's stateful API and would give genuine process persistence; it also keeps the dependency.)
```

Under "## Requirements", replace the `uv` bullet:

```markdown
- `claude` in `$PATH` (2.1.212+, for `--setting-sources` and `--max-budget-usd`)
- `ANTHROPIC_API_KEY` set
- `jq` installed
```

Under "## What it tests", replace "SDK runner" with "eval runner" in items 2 and 3.

- [ ] **Step 7: Verify nothing still references the SDK, and that the tests actually ran**

Run: `grep -rniE "sdk-runner|agent sdk|claude-agent-sdk|\buv\b" tests/evals/ Makefile`
Expected: the only hits are the README's deliberate history paragraph (`Claude Agent SDK`, `ClaudeSDKClient`, `SDK (query() ×2)`) and `claude-runner.sh`'s explanatory header. No hit names `sdk-runner.py` or requires `uv`.

Run: `make test`
Expected: the full bats suite green. Confirm `tests/evals/lib/runner.bats` is actually listed in the run and its test count went up — this suite has orphaned test files from `make test` before, and a green count means nothing until you know what ran.

- [ ] **Step 8: Commit**

```bash
git add -A tests/evals
git commit -m "refactor: drop the Agent SDK for a claude --print eval runner"
```

---

### Task 2: Dogfood — run the real evals

The unit tests all speak to a mocked `claude`. Nothing so far proves the runner drives a live session, and the eval flow is exactly the kind of thing fixtures miss. Separate task because this one needs a live, unsandboxed environment and its outcome may send you back into Task 1's code.

**Files:** `docs/design.md` (one row); the runner only if a defect surfaces.

- [ ] **Step 1: Run the suite for real**

This needs network and an unsandboxed environment — the Claude Code sandbox blocks the API, and `dangerouslyDisableSandbox` is unavailable under strict mode, so this may have to run from David's own shell via `!`.

```bash
make evals
```

Expected: `=== Results: 2/2 scenarios passed ===`, 5/5 trials each.

- [ ] **Step 2: Compare against the SDK baseline**

The suite passed 2/2 on the SDK runner. If a scenario now fails, the harness swap is the prime suspect and the diagnosis is a live one — check that turn 1's `--resume` id reaches turn 2, that the PostToolUse hook fired (project settings loaded), and that no trial hit `--max-budget-usd`. Do not adjust the assertions to fit a failure.

- [ ] **Step 3: Record the outcome in the design log**

Add one row to `docs/design.md`'s Decision Log, dated `2026-07-17`, stating: the eval harness dropped the Agent SDK for `claude --print --resume`; the SDK's stated rationale (in-process context reuse) was false about its own code since `query()` is stateless; the measured edge was ~$0.05 / ~10s per two-turn trial, of which the ~7k context half is closed by `--setting-sources project`; `--max-turns` has no CLI equivalent, so the runaway guard is `--max-budget-usd`; the runner gained 8 unit tests against a mocked `claude`, where `sdk-runner.py` had none. Include the live `make evals` result.

- [ ] **Step 4: Commit**

```bash
git add docs/design.md
git commit -m "docs: record the eval harness cutover to the claude CLI"
```
