#!/usr/bin/env bash
# Shared setup for the tests/cc_hook_index_compose*.bats suites: the hook
# paths, the two-step trigger drivers (pre/feed/sync_feed/drain_feed), and the
# fixture that seeds a root index line and its file together.
#
# feed()'s agent id is optional and most calls below omit it (a main-thread
# call), which is what SC2119/SC2120 flag as suspicious at the bare
# `feed >/dev/null` sites in the suites that load this file — the argument is
# genuinely optional. Each such suite disables SC2119/SC2120 for itself since
# SC2119 fires at the call sites, not here.

HOOK="$PLUGIN_ROOT/scripts/cc-hooks/index-compose.sh"
PRE="$PLUGIN_ROOT/scripts/cc-hooks/index-sync-pre.sh"
POST="$PLUGIN_ROOT/scripts/cc-hooks/index-sync-post.sh"
DRAIN="$PLUGIN_ROOT/scripts/cc-hooks/relay-drain.sh"

setup() {
  setup_tmp_repo
  export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
  make_parent_with_memory
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
}
teardown() { teardown_tmp_repo; }

# The trigger is a two-step protocol, so the tests drive both halves: the
# PreToolUse hook stamps the watched files before the call, the batch's writes
# land, and the PostToolBatch hook composes if that stamp moved. Naming a file
# is no longer enough — the file has to change.
#
# $1 = the file an Edit announced, or the literal `Bash` for a call that
# announces nothing. $2 = agent id, optional — absent/empty omits `agent_id`
# entirely (a main-thread call); non-empty adds it, the same
# absent-vs-non-empty contract scripts/lib/index-sync.sh's own helpers use.
# Every call also carries `agent_type`, the shape a real `--agent`-session
# payload has whether or not it carries `agent_id` too — the decoy a hook
# that falls back to `agent_type` would key on by mistake.
pre() {
  local agent="${2:-}"
  if [ "$1" = Bash ]; then
    jq -n --arg a "$agent" \
      '{tool_name:"Bash",tool_input:{command:"true"},agent_type:"general-purpose"}
       + (if $a == "" then {} else {agent_id:$a} end)' | bash "$PRE"
  else
    jq -n --arg f "$1" --arg a "$agent" \
      '{tool_name:"Edit",tool_input:{file_path:$f},agent_type:"general-purpose"}
       + (if $a == "" then {} else {agent_id:$a} end)' | bash "$PRE"
  fi
}

# $1 = agent id, optional — same absent-vs-non-empty contract as pre()'s
# second argument, and the same agent_type decoy. The payload's CONTENTS are
# still drained rather than acted on for composition itself; only the agent
# id is meant to steer which baseline this run consumes. `session_id` fixed
# to the same "test-session" sync_feed() carries, so a fixture that gives
# BOTH hooks a real report in one keyed batch (the concurrency case) relays
# under one session rather than two.
feed() {
  local agent="${1:-}"
  jq -n --arg a "$agent" --arg s test-session \
    '{agent_type:"general-purpose", session_id:$s} + (if $a == "" then {} else {agent_id:$a} end)' \
    | bash "$HOOK"
}

# Drives index-sync-post.sh the same way feed() drives index-compose.sh: $1 =
# agent id, optional, same absent-vs-non-empty contract. The hook's own
# pre-hook stash drives propagation, and it reads `session_id` only to key the
# relay and the byte-budget nudge, so a minimal PostToolBatch envelope
# carrying the session is enough. The concurrency case is the one that needs
# the sync hook, alongside the compose hook, in the same batch.
sync_feed() {
  local agent="${1:-}"
  jq -n --arg a "$agent" --arg s test-session \
    '{hook_event_name:"PostToolBatch", session_id:$s, tool_calls:[], tool_results:[],
      agent_type:"general-purpose"} + (if $a == "" then {} else {agent_id:$a} end)' \
    | bash "$POST"
}

# Drives relay-drain.sh the same way feed()/sync_feed() drive the other two
# PostToolBatch hooks. $1 = agent id, optional, same absent-vs-non-empty
# contract. $2 = session id, default "test-session" — the same fixed value
# feed()/sync_feed() carry, so a marker either of them staged is found by an
# unkeyed drain run with no override.
drain_feed() {
  local agent="${1:-}" session="${2:-test-session}"
  jq -n --arg a "$agent" --arg s "$session" \
    '{hook_event_name:"PostToolBatch", session_id:$s, tool_calls:[], tool_results:[],
      agent_type:"general-purpose"} + (if $a == "" then {} else {agent_id:$a} end)' \
    | bash "$DRAIN"
}

# A root index line AND the file it names, so the edit is a real fact rather
# than a dangling pointer the compose would report on.
seed_root_fact() {
  seed_root_bullet "$1" "$2"
  printf -- '---\nname: %s\ndescription: ""\n---\n\nbody\n' "$(basename "${1%.md}")" > "memory/$1"
}
