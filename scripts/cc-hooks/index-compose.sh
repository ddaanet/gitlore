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

# PostToolBatch, like the index→frontmatter sync: it fires once per turn with
# every call in .tool_calls[], so a turn holding several index edits composes —
# and reports — once instead of per edit.
payload=$(cat)
files=$(jq -r '
  .tool_calls[]? | select(.tool_name == "Write" or .tool_name == "Edit")
  | .tool_input.file_path // empty' <<<"$payload")
[ -n "$files" ] || exit 0

gitlore_cd_project_root || exit 0   # the launch repo, never the session cwd (see util.sh)
gitlore_has_submodule || exit 0
mempath=$(gitlore_memory_path)
index="$mempath/MEMORY.md"
manifest="$mempath/.gitlore-tiers"
[ -e "$index" ] || exit 0

# Did this batch write the root index or the activation manifest? Tracked
# separately: the triage nudge below fires on a manifest change specifically
# (the active-tier set may have changed), not on every memory-writing recompose.
# Identity via -ef, as in the sync hooks: the payload carries absolute paths
# and $mempath is relative to the repo root.
index_touched=""
manifest_touched=""
while IFS= read -r f; do
  [ -n "$f" ] || continue
  [ -e "$f" ] || continue
  if [ "$f" -ef "$index" ]; then index_touched=1; fi
  if [ -e "$manifest" ] && [ "$f" -ef "$manifest" ]; then manifest_touched=1; fi
done <<<"$files"
[ -n "$index_touched$manifest_touched" ] || exit 0

gitlore_compose_and_report "$mempath" "$manifest_touched"

if [ -n "$GITLORE_COMPOSE_SYSMSG" ]; then
  jq -n --arg s "$GITLORE_COMPOSE_SYSMSG" --arg c "$GITLORE_COMPOSE_CTX" \
    '{systemMessage: $s, suppressOutput: true,
      hookSpecificOutput: {hookEventName: "PostToolBatch", additionalContext: $c}}'
fi
exit 0
