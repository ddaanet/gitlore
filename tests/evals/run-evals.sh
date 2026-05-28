#!/usr/bin/env bash
# Gitlore eval runner — memory commit flow.
# Requires: uv in PATH, Claude Code API access (Claude Max or ANTHROPIC_API_KEY).
# Must run in an unsandboxed environment — Claude Code sandbox blocks API calls.
set -e

# sdk-runner.py uses the Claude Agent SDK (via uv) so PostToolUse hooks fire
# and additionalContext injects correctly — unlike `claude --print` which
# suppresses all hooks.
command -v uv >/dev/null 2>&1 || { echo "error: uv not found (required for eval SDK runner)" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Allow overrides for testing.
SCENARIOS_DIR="${SCENARIOS_DIR:-$SCRIPT_DIR/scenarios}"
LIB_DIR="${LIB_DIR:-$SCRIPT_DIR/lib}"

# Pre-flight: verify Claude Code API is accessible before loading helpers.
# Evals spawn real Claude sessions; this fails when running inside a Claude Code
# sandbox (network to the API is blocked).
_probe_tmp=$(mktemp -d)
if ! "$LIB_DIR/sdk-runner.py" --probe --cwd "$_probe_tmp" 2>/dev/null; then
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

K=5
total=0
passed=0
failed=0

for scenario_file in "$SCENARIOS_DIR"/*.json; do
  [ -f "$scenario_file" ] || continue

  total=$((total + 1))
  name=$(jq -r '.name' "$scenario_file")
  initial_memory=$(jq -r '.initial_memory' "$scenario_file")
  prompt=$(jq -r '.prompt' "$scenario_file")
  approval=$(jq -r '.approval_message' "$scenario_file")
  rubric=$(jq -r '.rubric' "$scenario_file")

  printf '📝 Scenario: %s\n\n' "$name"

  trial_passes=0
  trial_fails=0

  for trial in $(seq 1 "$K"); do
    fail_reason=""
    setup_eval_repo "$initial_memory"

    # SDK runner (two turns):
    #   Turn 1 — agent edits memory, runs `true`, PostToolUse hook injects
    #             additionalContext, agent summarises and stops.
    #   Turn 2 — eval sends approval; agent writes commit-msg file.
    "$LIB_DIR/sdk-runner.py" \
      --cwd "$EVAL_REPO" --prompt "$prompt" --approval "$approval" \
      2>/dev/null || fail_reason="sdk runner failed"

    # Assertion 0: commit-msg file must exist (agent received additionalContext and wrote it).
    if [ -z "$fail_reason" ]; then
      msgfile_pre=$(git -C "$EVAL_REPO/memory" rev-parse --git-path gitlore-commit-msg 2>/dev/null || true)
      [ -n "$msgfile_pre" ] && [ -f "$msgfile_pre" ] || \
        fail_reason="no commit-msg file (agent did not write it after receiving additionalContext)"
    fi

    if [ -z "$fail_reason" ]; then
      # Parent commit fires the gitlore pre-commit hook, which commits memory
      # and ff-pushes to live.
      (cd "$EVAL_REPO" && git commit --allow-empty -m "chore: trigger eval flow") 2>/dev/null || \
        fail_reason="parent git commit failed"
    fi

    # Assertion 1: memory has ≥2 commits (initial + the new one).
    if [ -z "$fail_reason" ]; then
      count=$(git -C "$EVAL_REPO/memory" log --oneline | wc -l | tr -d ' ')
      [ "$count" -ge 2 ] || fail_reason="memory not committed (found $count commit(s))"
    fi

    # Assertion 2: live is ff-pushed (HEAD == live).
    if [ -z "$fail_reason" ]; then
      head=$(git -C "$EVAL_REPO/memory" rev-parse HEAD)
      live=$(git -C "$EVAL_REPO/memory" rev-parse live)
      [ "$head" = "$live" ] || fail_reason="live not ff-pushed (HEAD=$head live=$live)"
    fi

    # Assertion 3: commit-msg temp file was consumed and deleted.
    if [ -z "$fail_reason" ]; then
      msgfile=$(git -C "$EVAL_REPO/memory" rev-parse --git-path gitlore-commit-msg 2>/dev/null || true)
      [ -z "$msgfile" ] || [ ! -f "$msgfile" ] || fail_reason="commit-msg file still present at $msgfile"
    fi

    # LLM judge: commit message must match the rubric.
    if [ -z "$fail_reason" ]; then
      diff=$(git -C "$EVAL_REPO/memory" show HEAD 2>/dev/null || true)
      msg=$(git -C "$EVAL_REPO/memory" log -1 --format=%B 2>/dev/null || true)
      "$LIB_DIR/judge.sh" "$rubric" "$diff" "$msg" 2>/dev/null || \
        fail_reason="commit message failed judge rubric"
    fi

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
