#!/usr/bin/env bash
set -euo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-}"
# shellcheck disable=SC1091
source "$PLUGIN_ROOT/scripts/lib/util.sh"

payload=$(cat)
tool=$(jq -r '.tool_name // empty' <<<"$payload")
[ "$tool" = "Bash" ] || exit 0

cmd=$(jq -r '.tool_input.command // empty' <<<"$payload")
[ -n "$cmd" ] || exit 0

exit_code=$(jq -r '.tool_response.exit_code // 0' <<<"$payload")
[ "$exit_code" = "0" ] || exit 0

[ -f .claude/settings.json ] || exit 0
prefix=$(jq -r '.gitlore.precommitCommand // empty' .claude/settings.json 2>/dev/null || true)
[ -n "$prefix" ] || exit 0
case "$cmd" in "$prefix"*) ;; *) exit 0 ;; esac

gitlore_has_submodule || exit 0
mempath=$(gitlore_memory_path)

[ "$(gitlore_memory_dirty "$mempath")" = "1" ] || exit 0
[ "$(gitlore_commit_msg_freshness "$mempath")" != "yes" ] || exit 0

msgfile=$(gitlore_commit_msg_file "$mempath")

cat <<EOF
{
  "additionalContext": "gitlore: memory ($mempath) has uncommitted changes. Summarize pending memory changes in prose, present the summary to the user, await explicit confirmation, then write the approved summary to $msgfile. On rejection, discuss and retry."
}
EOF
