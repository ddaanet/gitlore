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

if [ -z "$PROMPT" ] || [ -z "$APPROVAL" ]; then
  die "--prompt and --approval are required unless --probe is set" 2
fi

# Turn 1: agent edits memory, triggers the flow, summarises, stops for approval.
t1=$(run_turn "$PROMPT") || die "eval: turn 1 yielded no result"
session_id=$(check_turn "turn 1" "$t1")
[ -n "$session_id" ] || die "eval: turn 1 returned no session id"

# Turn 2: user approves; agent writes the commit-msg file.
t2=$(run_turn "$APPROVAL" "$session_id") || die "eval: turn 2 yielded no result"
check_turn "turn 2" "$t2" >/dev/null
