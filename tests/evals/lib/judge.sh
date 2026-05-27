#!/usr/bin/env bash
# LLM judge for commit message quality.
# Usage: judge.sh "<rubric>" "<diff>" "<commit_msg>"
# Exits 0 on pass, 1 on fail. Explanation goes to stderr.
set -euo pipefail

RUBRIC="$1"
DIFF="$2"
COMMIT_MSG="$3"

PROMPT="You are a strict evaluator. Given the DIFF and COMMIT_MESSAGE below, decide whether the commit message satisfies the RUBRIC. Reply with exactly one word: pass or fail. Then on the next line, one sentence explaining why.

RUBRIC: ${RUBRIC}

DIFF:
${DIFF}

COMMIT_MESSAGE:
${COMMIT_MSG}"

result=$(claude --print "$PROMPT" 2>/dev/null)
first_word=$(printf '%s\n' "$result" | head -1 | tr '[:upper:]' '[:lower:]' | awk '{print $1}')

case "$first_word" in
  pass) exit 0 ;;
  *)    printf '%s\n' "$result" >&2; exit 1 ;;
esac
