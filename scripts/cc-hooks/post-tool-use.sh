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

gitlore_cd_project_root || exit 0   # the launch repo, never the session cwd (see util.sh)

[ -f .claude/settings.json ] || exit 0
# No redirect: the `-f` guard above already covers the file-absent case, so a jq
# error here means malformed settings.json — which the user needs to hear about
# rather than have silently downgraded to "feature off".
prefix=$(jq -r '.gitlore.precommitCommand // empty' .claude/settings.json || true)
[ -n "$prefix" ] || exit 0
case "$cmd" in "$prefix"*) ;; *) exit 0 ;; esac

gitlore_has_submodule || exit 0
mempath=$(gitlore_memory_path)

[ "$(gitlore_memory_dirty "$mempath")" = "1" ] || exit 0
[ "$(gitlore_commit_msg_freshness "$mempath")" != "yes" ] || exit 0

# Nudge once per dirty episode: a second green pre-commit run while memory is
# still dirty and unapproved stays silent. The marker is cleared when memory is
# finally committed (gitlore_sync_memory_to_live), starting a fresh episode.
notifyfile=$(gitlore_commit_notified_file "$mempath")
if [ -f "$notifyfile" ]; then exit 0; fi
touch "$notifyfile"

msgfile=$(gitlore_commit_msg_file "$mempath")

cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PostToolUse",
    "additionalContext": "gitlore: memory ($mempath) has uncommitted changes. Summarize pending memory changes in prose, present the summary to the user as a markdown blockquote (\`> …\`) — not a code fence, which frames it as a verbatim artifact rather than an editable draft — and await confirmation. Treat only a clear, un-negated affirmative as approval; a hedge, a question, or any negation ('not yet', 'no', 'disapprove') is a rejection. Only once approved, write the summary to $msgfile. On rejection or anything unclear, discuss and ask again — do not write $msgfile."
  }
}
EOF
