#!/usr/bin/env bash
set -euo pipefail

# PostToolBatch: serve an active-recall request, and keep the ledger of what is
# already in context.
#
# Two jobs, one hook, because both need the same batch payload:
#
#  1. LEDGER. Every Read of a file under the memory store is recorded. This
#     catches CC's OWN recall too — "Recalled 1 memory" is a real Read tool
#     call issued on the agent's behalf, so it lands in .tool_calls[] like any
#     other. That is what stops active recall from re-injecting a body the
#     native classifier already pulled.
#
#  2. REQUEST. If the agent wrote the recall request file, resolve it and
#     inject the bodies as additionalContext. No hook output can force a Read
#     (verified: no injectToolCall/forceRead field exists), so the hook does the
#     reading itself — which is better than forcing a Read anyway: one round
#     trip instead of two, and the selection is auditable in a file.
#
# The ledger is updated BEFORE the request is served, so a file read earlier in
# the same batch counts as present.

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-}"
# shellcheck disable=SC1091
source "$PLUGIN_ROOT/scripts/lib/util.sh"
# shellcheck disable=SC1091
source "$PLUGIN_ROOT/scripts/lib/recall.sh"

payload=$(cat)

gitlore_has_submodule || exit 0
mempath=$(gitlore_memory_path)
[ -e "$mempath/.git" ] || exit 0          # session-less worktree: no memory

session=$(jq -r '.session_id // ""' <<<"$payload")
memabs=$(CDPATH='' cd -- "$mempath" && pwd)

# 1. Ledger: record every memory body this batch pulled into context.
while IFS= read -r f; do
  [ -n "$f" ] || continue
  [ -f "$f" ] || continue
  abs=$(CDPATH='' cd -- "$(dirname -- "$f")" && pwd)/$(basename -- "$f")
  case "$abs" in
    "$memabs"/*) gitlore_recall_record "$mempath" "$session" "${abs#"$memabs"/}" ;;
  esac
done < <(jq -r '.tool_calls[]? | select(.tool_name == "Read")
                | .tool_input.file_path // empty' <<<"$payload")

# 2. Request: the file IS the signal, so nothing else in the payload matters.
req=$(gitlore_recall_file "$mempath")
[ -f "$req" ] || exit 0

if body=$(gitlore_recall_resolve "$mempath" "$session"); then
  if [ "$body" = "no match" ]; then
    sysmsg="gitlore: recall checkpoint — no match."
    ctx="gitlore recall: you assessed the index and found nothing relevant. Proceed; no memory bodies were fetched."
  else
    n=$(printf '%s\n' "$body" | grep -c '^===== ' || true)
    sysmsg="gitlore: recalled $n memor$([ "$n" = 1 ] && printf 'y' || printf 'ies')."
    ctx="$body"
  fi
else
  sysmsg="gitlore: recall request rejected."
  ctx="gitlore recall REFUSED — nothing was read. $body"
fi

# Consume either way: a one-shot request. Keeping a rejected one would re-report
# the same problem on every later batch; the agent simply re-requests.
rm -f "$req"

jq -n --arg s "$sysmsg" --arg c "$ctx" \
  '{systemMessage: $s, suppressOutput: true,
    hookSpecificOutput: {hookEventName: "PostToolBatch", additionalContext: $c}}'
exit 0
