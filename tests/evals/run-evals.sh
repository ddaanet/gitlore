#!/usr/bin/env bash
# Gitlore eval runner — memory commit flow.
# Requires: claude and jq in PATH, Claude Code API access (Claude Max or ANTHROPIC_API_KEY).
# Must run in an unsandboxed environment: the API is reachable from inside the
# Claude Code sandbox, but ~/.claude/projects/ (where session transcripts live)
# is read-only there, so turn 1 never persists and turn 2's --resume finds no
# conversation. The pre-flight probe below is a single turn and does NOT catch
# this — it passes sandboxed.
set -e

# The runner drives the `claude` CLI in --print mode: hooks fire and
# additionalContext injects, with no Python/uv dependency.
command -v claude >/dev/null 2>&1 || { echo "error: claude not found (required for the eval runner)" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "error: jq not found (required for the eval runner)" >&2; exit 1; }

unset CDPATH   # else `cd` may echo its target into the $(cd … && pwd) capture below
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Allow overrides for testing.
SCENARIOS_DIR="${SCENARIOS_DIR:-$SCRIPT_DIR/scenarios}"
LIB_DIR="${LIB_DIR:-$SCRIPT_DIR/lib}"
ASSERTS_DIR="${ASSERTS_DIR:-$SCRIPT_DIR/asserts}"
SETUPS_DIR="${SETUPS_DIR:-$SCRIPT_DIR/setups}"

# Pre-flight: verify the Claude Code API answers before loading helpers.
# One turn only — it does not exercise --resume, so it cannot detect the
# sandboxed-transcript failure described above.
_probe_tmp=$(mktemp -d)
if ! "$LIB_DIR/claude-runner.sh" --probe --cwd "$_probe_tmp" 2>/dev/null; then
  rm -rf "$_probe_tmp"
  echo "error: Claude Code API is not accessible."
  echo "       Evals must run in an unsandboxed environment."
  echo "       If running inside Claude Code, disable sandbox mode first."
  exit 1
fi
rm -rf "$_probe_tmp"

EVAL_LIB_DIR="$LIB_DIR"
export EVAL_LIB_DIR

# shellcheck disable=SC1091
source "$LIB_DIR/setup.sh"

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

# Trials per scenario (pass^k). Override for a quick smoke run: EVAL_K=1.
K="${EVAL_K:-5}"
total=0
passed=0
failed=0

for scenario_file in "$SCENARIOS_DIR"/*.json; do
  [ -f "$scenario_file" ] || continue

  total=$((total + 1))
  name=$(jq -r '.name' "$scenario_file")
  initial_memory=$(jq -r '.initial_memory' "$scenario_file")
  prompt=$(jq -r '.prompt' "$scenario_file")
  # Optional: a scenario with no approval gate is a single turn.
  approval=$(jq -r '.approval_message // ""' "$scenario_file")
  rubric=$(jq -r '.rubric // ""' "$scenario_file")
  # ptu: agent wrote commit-msg and stopped; commit-msg must exist before eval's git commit.
  # precommit_failure: agent may have retried and consumed commit-msg; accept either state.
  trigger=$(jq -r '.trigger // "ptu"' "$scenario_file")
  # Which flow this scenario grades. The memory-commit chain is one flow among
  # several now (tiers, recall, add-tier), each with its own end state, so the
  # assertions live per-flow in asserts/ rather than inline here.
  assert=$(jq -r '.assert // "memory-commit"' "$scenario_file")
  # Optional fixture extension, run after setup_eval_repo with cwd = $EVAL_REPO:
  # mounting a tier, seeding a remote, planting a memory body to recall.
  scenario_setup=$(jq -r '.setup // ""' "$scenario_file")

  printf '📝 Scenario: %s\n\n' "$name"

  # A scenario naming an assertion that is missing or not executable is a broken
  # scenario, not a passing one. Fail it loudly rather than skip it — an eval
  # that quietly grades nothing is worse than one that is red.
  assert_script="$ASSERTS_DIR/$assert.sh"
  if [ ! -x "$assert_script" ]; then
    printf "  ${RED}✗ Scenario FAILED${NC} (no executable assertion at %s)\n\n" "$assert_script"
    failed=$((failed + 1))
    continue
  fi

  trial_passes=0
  trial_fails=0

  for trial in $(seq 1 "$K"); do
    fail_reason=""
    setup_eval_repo "$initial_memory"

    # Per-turn transcripts, for assertions that must see what the agent said.
    EVAL_OUT_DIR=$(mktemp -d "${TMPDIR:-/tmp}/gitlore-eval-out.XXXXXX")

    # Scenario fixture extension, before the agent runs. A non-zero exit here is
    # a broken fixture, not a graded failure — report it as its own reason so it
    # is never mistaken for the agent getting the flow wrong.
    if [ -n "$scenario_setup" ]; then
      setup_out=$( (cd "$EVAL_REPO" && bash "$SETUPS_DIR/$scenario_setup.sh") 2>&1 ) || \
        fail_reason="scenario setup '$scenario_setup' failed — ${setup_out//$'\n'/ }"
    fi

    # Where the memory store stood before the agent touched anything. An
    # assertion of the form "nothing committed inside memory" cannot count
    # commits: install, setup_eval_repo and the scenario fixture each make their
    # own, and that baseline differs per scenario.
    if [ -z "$fail_reason" ]; then
      git -C "$EVAL_REPO/memory" rev-parse HEAD > "$EVAL_OUT_DIR/memory-baseline"
    fi

    # Eval runner. Two turns when the scenario carries an approval message
    # (the memory-commit gate), one when it does not (add-tier, recall).
    #
    # {{EVAL_REPO}} in a prompt expands to the throwaway repo's path. A scenario
    # that has to name something the fixture created — a tier remote's URL — can
    # only learn its path at trial time, and telling the agent to go find it
    # would grade a search instead of the flow under test.
    if [ -z "$fail_reason" ]; then
      prompt_expanded="${prompt//\{\{EVAL_REPO\}\}/$EVAL_REPO}"
      runner_args=(--cwd "$EVAL_REPO" --prompt "$prompt_expanded" --out-dir "$EVAL_OUT_DIR")
      [ -z "$approval" ] || runner_args+=(--approval "$approval")
      runner_err=$("$LIB_DIR/claude-runner.sh" "${runner_args[@]}" 2>&1 1>/dev/null) || \
        fail_reason="eval runner failed — ${runner_err//$'\n'/ }"
    fi

    # Grade the flow. The assertion script owns everything after the turns —
    # including firing the parent commit, where the flow has one — and reports a
    # failure by exiting non-zero with the reason on stdout/stderr.
    if [ -z "$fail_reason" ]; then
      assert_out=$(
        EVAL_REPO="$EVAL_REPO" EVAL_OUT_DIR="$EVAL_OUT_DIR" \
        EVAL_RUBRIC="$rubric" EVAL_TRIGGER="$trigger" \
        PLUGIN_ROOT="$PLUGIN_ROOT" LIB_DIR="$LIB_DIR" \
        bash "$assert_script" 2>&1
      ) || fail_reason="${assert_out//$'\n'/ }"
    fi

    rm -rf "$EVAL_OUT_DIR"
    teardown_eval_repo

    if [ -z "$fail_reason" ]; then
      printf "  ${GREEN}✓${NC} Run %d: PASS\n" "$trial"
      trial_passes=$((trial_passes + 1))
    else
      printf "  ${RED}✗${NC} Run %d: FAIL (%s)\n" "$trial" "$fail_reason"
      trial_fails=$((trial_fails + 1))
    fi
  done

  printf '\n'
  if [ "$trial_fails" -eq 0 ]; then
    printf "  ${GREEN}✓ Scenario PASSED${NC} (%d/%d)\n\n" "$K" "$K"
    passed=$((passed + 1))
  else
    printf "  ${RED}✗ Scenario FAILED${NC} (%d/%d)\n\n" "$trial_passes" "$K"
    failed=$((failed + 1))
  fi
done

printf '=== Results: %d/%d scenarios passed ===\n' "$passed" "$total"
[ "$failed" -eq 0 ]
