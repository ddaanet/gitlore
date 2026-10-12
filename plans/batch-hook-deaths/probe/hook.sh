#!/usr/bin/env bash
cat >/dev/null
code=$(cat /tmp/claude/probe-ptb/code)
if [ "$code" = ctx ]; then
  printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PostToolBatch","additionalContext":"probe note: ibis-55"}}'
  exit 0
fi
echo "PROBE-STDERR-ONE zebra-17" >&2
echo "PROBE-STDERR-TWO quokka-42" >&2
echo "PROBE-STDOUT heron-93"
exit "$code"
