#!/usr/bin/env bash
# Shared fixtures for the tests/index_sync*.bats suites: the library under
# test, the two hook scripts, and the stdin-feeding/payload-building helpers
# more than one of those suites calls.

# shellcheck disable=SC2034   # used by callers' setup() and by index_sync.bats itself
SRC="$PLUGIN_ROOT/scripts/lib/index-sync.sh"
PRE="$PLUGIN_ROOT/scripts/cc-hooks/index-sync-pre.sh"
POST="$PLUGIN_ROOT/scripts/cc-hooks/index-sync-post.sh"

pre_stdin() { printf '%s' "$1" | bash "$PRE"; }
post_stdin() { printf '%s' "$1" | bash "$POST"; }

# PostToolBatch payload: every call of the turn under .tool_calls[], so the
# sync runs once per batch however many Edits it contains. $1.. = file paths.
# TEST_AGENT_ID mirrors TEST_SESSION_ID: unset/empty omits the field entirely
# (a main-thread batch), non-empty adds it (a subagent batch) — same
# absent/empty-vs-non-empty contract as the helpers in scripts/lib/index-sync.sh.
# TEST_AGENT_TYPE is the decoy field: a real main-thread payload from inside an
# `--agent` session carries `agent_type` but never `agent_id`, so a hook that
# falls back to `agent_type` must not key on it.
batch_payload() {
  local f json='[]'
  for f in "$@"; do
    json=$(jq -c --arg f "$f" '. + [{tool_name:"Edit",tool_input:{file_path:$f}}]' <<<"$json")
  done
  jq -n --argjson c "$json" --arg s "${TEST_SESSION_ID:-test-session}" \
    --arg a "${TEST_AGENT_ID:-}" --arg t "${TEST_AGENT_TYPE:-}" \
    '{hook_event_name:"PostToolBatch", session_id:$s, tool_calls:$c, tool_results:[]}
     + (if $a == "" then {} else {agent_id:$a} end)
     + (if $t == "" then {} else {agent_type:$t} end)'
}
