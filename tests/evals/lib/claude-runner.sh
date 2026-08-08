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
# --approval is optional: a scenario with no approval gate (add-tier, recall) is
# one turn, and inventing a second "ok" message for it would put the agent's
# reply to a message the flow never sends into the transcript the assertions read.
#
# --out-dir captures each turn's final assistant text as turn<N>.txt, plus the
# session id. An assertion that has to see what the agent SAID — that an injected
# memory body actually reached context, say — has no other window onto it.
#
# Usage:
#   claude-runner.sh --cwd <path> --prompt <text> [--approval <text>] [--out-dir <path>]
#   claude-runner.sh --probe --cwd <path>   # connectivity check only
set -euo pipefail

CWD=""
PROMPT=""
APPROVAL=""
OUT_DIR=""
PROBE=0
# Runaway guard, replacing the SDK's max_turns=20 (no CLI equivalent exists).
MAX_BUDGET_USD="${EVAL_MAX_BUDGET_USD:-2.00}"

die() { printf '%s\n' "$1" >&2; exit "${2:-1}"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --cwd)      CWD="${2:-}";      shift 2 ;;
    --prompt)   PROMPT="${2:-}";   shift 2 ;;
    --approval) APPROVAL="${2:-}"; shift 2 ;;
    --out-dir)  OUT_DIR="${2:-}";  shift 2 ;;
    --probe)    PROBE=1;           shift ;;
    *)          die "usage: $(basename "$0") --cwd <path> [--prompt <text>] [--approval <text>] [--out-dir <path>] [--probe]" 2 ;;
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
  # `< /dev/null`: claude -p waits 3s for piped stdin that never comes.
  (cd "$CWD" && claude "${args[@]}" < /dev/null)
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

[ -n "$PROMPT" ] || die "--prompt is required unless --probe is set" 2

# Save a turn's final assistant text for the assertions. No-op without --out-dir.
save_turn() {
  [ -n "$OUT_DIR" ] || return 0
  mkdir -p "$OUT_DIR"
  printf '%s' "$2" | jq -r '.result // ""' > "$OUT_DIR/turn$1.txt"
}

# Copy the session transcript out, so an assertion can see which TOOLS ran and
# not just what the agent said. Some contracts are only visible there: active
# recall is meant to fire on a trigger that surfaced mid-task, and CC's own
# prompt-time recall produces an identical answer and an identical repo — only
# the order of the tool calls separates them.
#
# Found by session id rather than by deriving the project directory name — that
# encoding is a mangling of cwd and reverse-engineering it here would be a second
# place to get it wrong. Session ids are uuids, so the name alone is unambiguous.
save_transcript() {
  [ -n "$OUT_DIR" ] || return 0
  local root="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects" found
  [ -d "$root" ] || return 0
  found=$(find "$root" -name "$1.jsonl" -type f -print -quit)
  [ -n "$found" ] || return 0
  cp "$found" "$OUT_DIR/transcript.jsonl"
}

# Turn 1: agent edits memory, triggers the flow, summarises, stops for approval.
t1=$(run_turn "$PROMPT") || die "eval: turn 1 yielded no result"
session_id=$(check_turn "turn 1" "$t1")
[ -n "$session_id" ] || die "eval: turn 1 returned no session id"
save_turn 1 "$t1"
[ -z "$OUT_DIR" ] || printf '%s\n' "$session_id" > "$OUT_DIR/session-id"

# Turn 2: user approves; agent writes the commit-msg file. Scenarios with no
# approval gate stop here.
if [ -z "$APPROVAL" ]; then
  save_transcript "$session_id"
  exit 0
fi
t2=$(run_turn "$APPROVAL" "$session_id") || die "eval: turn 2 yielded no result"
check_turn "turn 2" "$t2" >/dev/null
save_turn 2 "$t2"
save_transcript "$session_id"
