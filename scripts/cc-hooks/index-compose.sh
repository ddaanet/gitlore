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
cat >/dev/null   # drain the payload; the stamp, not its contents, is the signal

gitlore_cd_project_root || exit 0   # the launch repo, never the session cwd (see util.sh)
gitlore_has_submodule || exit 0
mempath=$(gitlore_memory_path)
index="$mempath/MEMORY.md"
manifest="$mempath/.gitlore-tiers"
[ -e "$index" ] || exit 0

stamp=$(gitlore_compose_stamp_file "$mempath")
[ -f "$stamp" ] || exit 0   # no baseline → no watched call this batch

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

if [ -n "$GITLORE_COMPOSE_SYSMSG" ]; then
  jq -n --arg s "$GITLORE_COMPOSE_SYSMSG" --arg c "$GITLORE_COMPOSE_CTX" \
    '{systemMessage: $s, suppressOutput: true,
      hookSpecificOutput: {hookEventName: "PostToolBatch", additionalContext: $c}}'
fi
exit 0
