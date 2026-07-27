#!/usr/bin/env bash
# LLM judge for commit message quality.
# Usage: judge.sh "<rubric>" "<diff>" "<commit_msg>"
# Exits 0 on pass, 1 on fail, 2 if the judge could not be invoked or its
# verdict could not be parsed. Explanation goes to stderr in all cases.
set -uo pipefail

RUBRIC="$1"
DIFF="$2"
COMMIT_MSG="$3"

PROMPT="You are a strict evaluator. Given the DIFF and COMMIT_MESSAGE below, decide whether the commit message satisfies the RUBRIC. Reply with exactly one word on the first line: pass or fail. Then on the next line, one sentence explaining why.

RUBRIC: ${RUBRIC}

DIFF:
${DIFF}

COMMIT_MESSAGE:
${COMMIT_MSG}"

result=$(claude --print "$PROMPT" 2>&1)
claude_exit=$?
if [ "$claude_exit" -ne 0 ]; then
  printf 'judge invocation failed (exit %s): %s\n' "$claude_exit" "$result" >&2
  exit 2
fi

first_line=$(printf '%s\n' "$result" | head -1)
first_word=$(printf '%s\n' "$first_line" | tr '[:upper:]' '[:lower:]' | awk '{print $1}')

case "$first_word" in
  pass) exit 0 ;;
  fail) printf '%s\n' "$result" >&2; exit 1 ;;
  *)    printf 'judge verdict unparseable (first line: %s): %s\n' "$first_line" "$result" >&2; exit 2 ;;
esac
