#!/usr/bin/env bash
set -euo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-}"
# shellcheck disable=SC1091
source "$PLUGIN_ROOT/scripts/lib/util.sh"
# shellcheck disable=SC1091
source "$PLUGIN_ROOT/scripts/lib/index-compose.sh"
# gitlore_active_tier_scopes (util.sh) calls gitlore_get_frontmatter_description,
# defined here — needed for the post-mount triage nudge below.
# shellcheck disable=SC1091
source "$PLUGIN_ROOT/scripts/lib/index-sync.sh"

# PostToolBatch, like the index→frontmatter sync: it fires once per batch with
# every call in .tool_calls[], so a turn holding several index edits composes —
# and reports — once instead of per edit.
#
# Keyed on the pre-batch stamp rather than on the batch's calls, for the reason
# the sync hook gives: a Bash-applied edit names no file, and composition that
# only reacts to Write and Edit lets the root index and a carrier drift apart
# silently. The stamp is this hook's own copy — the sync hook consumes a
# different file, so neither has to run first.
payload=$(cat)   # the stamp is the trigger; the payload is read below for agent_id alone

gitlore_cd_project_root || exit 0   # the launch repo, never the session cwd (see util.sh)
gitlore_has_submodule || exit 0
mempath=$(gitlore_memory_path)
index="$mempath/MEMORY.md"
manifest="$mempath/.gitlore-tiers"
[ -e "$index" ] || exit 0

# agent_id, never agent_type: only the former is subagent-only, and the latter
# also appears on the main thread of an --agent session — a fallback there
# would key a parent batch's stamp under its own agent id and strand it. The
# contract index-sync-post.sh states at length; pinned here by the agent_type
# decoy every payload in tests/cc_hook_index_compose.bats carries.
#
# Non-fatal deliberately: the stamp is what drives this hook, so an unparseable
# payload must not be what stops it. A jq aborting under errexit would leave the
# stamp unconsumed, and index-sync-pre.sh's `if [ ! -f "$stamp" ]` then hands
# that stale baseline to this agent's next batch, which composes against an
# ancient index. Falling back to the unsuffixed name costs at most the keying —
# a main-thread compose — while jq's own diagnostic still reaches stderr.
agent_id=$(jq -r '.agent_id // empty' <<<"$payload") || agent_id=""
# Non-fatal for the same reason: the relay write below keys its marker on this
# session, but a jq failure must not be what stops the hook and strands the
# stamp. Falling back to an empty session costs that keying alone.
session=$(jq -r '.session_id // ""' <<<"$payload") || session=""
stamp=$(gitlore_compose_stamp_file "$mempath" "$agent_id")
[ -f "$stamp" ] || exit 0   # no baseline → no watched call this batch, for THIS agent

# Did this batch change the root index or the activation manifest? Tracked
# separately: the triage nudge below fires on a manifest change specifically
# (the active-tier set may have changed), not on every memory-writing recompose.
now=$(gitlore_compose_stamp "$index" "$manifest")
index_touched=""
manifest_touched=""
for key in index manifest; do
  was=$(gitlore_compose_stamp_get "$key" < "$stamp")
  is=$(gitlore_compose_stamp_get "$key" <<<"$now")
  [ "$was" = "$is" ] && continue
  case "$key" in
    index) index_touched=1 ;;
    manifest) manifest_touched=1 ;;
  esac
done
rm -f "$stamp"
[ -n "$index_touched$manifest_touched" ] || exit 0

gitlore_compose_and_report "$mempath" "$manifest_touched"

# Keyed: the report above is confined to this subagent's own transcript
# (D51, measured under CC 2.1.261), so stage it for relay-drain.sh — the ONE
# drainer — to fold into the next parent-side batch, in addition
# to, not instead of, the emission below: the subagent is the actor and gets
# its own copy too. Guarded on the same emptiness the emission guard below
# applies: an empty report is nothing to stage. Unkeyed (the main thread),
# this hook writes nothing toward the relay — it only ever emits its own
# report; relay-drain.sh and session-start.sh are the hooks that read a marker.
if [ -n "$agent_id" ] && [ -n "$GITLORE_COMPOSE_SYSMSG" ]; then
  # `if !`, not `|| true`: a failed relay write must cost only the relay,
  # never this subagent's own report — both suspend errexit over the call
  # the same way — but the loss must not also be silent to everyone. On
  # additionalContext, not systemMessage: a subagent's systemMessage reaches
  # only that subagent's own transcript, while additionalContext is what the
  # acting model narrates unprompted — the only path by which the fact can
  # reach the parent, since the actor has to carry it there itself.
  # Appended after the write, since the line describes the write's own
  # failure and must not be staged by it.
  if ! gitlore_relay_write "$mempath" "$session" "$agent_id" compose "$GITLORE_COMPOSE_SYSMSG" "$GITLORE_COMPOSE_CTX"; then
    GITLORE_COMPOSE_CTX="${GITLORE_COMPOSE_CTX:+$GITLORE_COMPOSE_CTX

}gitlore: the report above could not be staged for the parent session — the relay marker could not be written. A hook's output inside a subagent reaches no one else, so repeat it in your reply or it is lost."
  fi
fi

if [ -n "$GITLORE_COMPOSE_SYSMSG" ]; then
  # The context half only when there is one: an `additionalContext` present and
  # empty is a block injected with nothing in it.
  jq -n --arg s "$GITLORE_COMPOSE_SYSMSG" --arg c "$GITLORE_COMPOSE_CTX" \
    '{systemMessage: $s, suppressOutput: true}
     + (if $c == "" then {} else
         {hookSpecificOutput: {hookEventName: "PostToolBatch", additionalContext: $c}}
       end)'
fi
exit 0
