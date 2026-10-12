#!/usr/bin/env bash
# usage: run.sh <exit-code|ctx>   — run UNSANDBOXED; drives the real claude (costs a few cents)
# Copies the hook to a scratch dir, runs one tool batch under it, then asks the
# resumed session which canary tokens it can see, and prints the transcript's
# PostToolBatch attachments.
src=$(cd "$(dirname "$0")" && pwd)
P=/tmp/claude/probe-ptb
mkdir -p "$P/work" && cp "$src/hook.sh" "$src/settings.json" "$P/" && chmod +x "$P/hook.sh" || exit 1
# shellcheck disable=SC1091
source "$src/../../../tests/evals/lib/real-claude.sh"
code=$1
echo "$code" > "$P/code"
cd "$P/work" || exit 1
# The backticks are prompt text, not a substitution.
# shellcheck disable=SC2016
eval_claude -p 'Run the Bash command `echo hi` exactly once, then reply with the single word DONE.' \
  --model sonnet --settings "$P/settings.json" --allowedTools 'Bash(echo:*)' \
  --output-format json > "$P/t1-$code.json" 2> "$P/t1-$code.err"
echo "turn1 rc=$?"
sid=$(jq -r '.session_id' "$P/t1-$code.json")
echo "sid=$sid result=$(jq -r '.result' "$P/t1-$code.json")"
echo 0 > "$P/code"
eval_claude -p 'Do not run any tool. Earlier in this conversation, before this message, did any text contain an animal name joined to a number by a hyphen? List each such token exactly, with one line on where it appeared, or reply NONE.' \
  --model sonnet --settings "$P/settings.json" --resume "$sid" \
  --output-format json > "$P/t2-$code.json" 2> "$P/t2-$code.err"
echo "turn2 rc=$?"
jq -r '.result' "$P/t2-$code.json"
echo "--- transcript attachments"
tf=$(find "$HOME/.claude/projects" -name "$sid.jsonl" -print -quit)
echo "transcript=$tf"
jq -c 'select(.type=="attachment") | .attachment | select(.hookEvent=="PostToolBatch") | del(.command)' "$tf"
jq -c 'select(.type=="system" and .subtype!="stop_hook_summary") | {subtype, content, level}' "$tf" | head -20
