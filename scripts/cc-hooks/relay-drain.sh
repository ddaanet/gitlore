#!/usr/bin/env bash
set -euo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-}"
# shellcheck disable=SC1091
source "$PLUGIN_ROOT/scripts/lib/util.sh"
# shellcheck disable=SC1091
source "$PLUGIN_ROOT/scripts/lib/index-sync.sh"

# PostToolBatch, D51: the ONE drainer of the relay. It is its own hook rather
# than a branch inside index-sync-post.sh or index-compose.sh because every
# hook matching one event runs in parallel, and each of those two runs only
# when its own baseline fired:
#
#  - parallel, so a drain living in both would run twice on a batch that fires
#    both, each copy framing and emitting the same markers — every relayed
#    report doubled;
#  - baseline-gated, so a drain living in either would skip the batch whose
#    Agent call returned. That batch changed no index and so left no stash and
#    no stamp, and it is exactly the batch the subagent's report was staged
#    for; the report would wait for an unrelated index edit or a SessionStart.
#
# This hook takes no baseline of its own: it runs on every batch of the main
# thread, and the marker files alone decide whether it says anything.
payload=$(cat)
# Non-fatal, and the fallback is deliberately AWAY from draining — the reverse
# of the reporting hooks, which fall back to the unkeyed name and carry on. A
# drain is destructive: it removes every file it read. A run that cannot tell a
# subagent from the main thread, or cannot name its session, would relay those
# reports into a transcript no one else reads and delete them, while a drain
# that does not run is re-delivered by the next batch or by SessionStart.
# Exiting here also keeps a broken jq away from the store: the emit below is a
# jq too, and a failure between the drain and the emit takes the reports with
# it, so these parses are what establish that jq works at all.
session=$(jq -r '.session_id // ""' <<<"$payload") || exit 0
# `agent_id`, empty on the main thread and set inside a subagent. A subagent
# never drains: it only ever writes toward this hook's next parent-side run,
# so draining here would relay a report into the transcript that produced it.
agent_id=$(jq -r '.agent_id // empty' <<<"$payload") || exit 0
[ -z "$agent_id" ] || exit 0

gitlore_cd_project_root || exit 0   # the launch repo, never the session cwd (see util.sh)
gitlore_has_submodule || exit 0
mempath=$(gitlore_memory_path)

gitlore_relay_drain "$mempath" "$session"
if [ -n "$GITLORE_RELAY_SYSMSG" ]; then
  jq -n --arg s "$GITLORE_RELAY_SYSMSG" --arg c "$GITLORE_RELAY_CTX" \
    '{systemMessage: $s, suppressOutput: true,
      hookSpecificOutput: {hookEventName: "PostToolBatch", additionalContext: $c}}'
fi
exit 0
