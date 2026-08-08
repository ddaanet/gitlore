#!/usr/bin/env bash
set -euo pipefail

# SessionStart + PreCompact: drop the once-per-episode nudge markers (index byte
# budget, mid-session plugin upgrade).
#
# A marker says "this session has already been told". That claim is only valid
# for as long as the context that holds the telling, and two events end it:
#
#  - SessionStart. A fresh context. `--resume` keeps the session id but not the
#    context, so keying on the id alone is not enough — the reset must be
#    explicit.
#  - PreCompact. What survives a compaction is a summary, not the tool results,
#    and re-injection after /compact is guaranteed only for the project-root
#    CLAUDE.md. A notice the summarizer dropped would otherwise never be
#    repeated, so the markers are re-armed wholesale: repeating a notice the
#    session still holds costs a line, while withholding one it has lost is
#    silent.
#
# Never fatal. A nudge marker that fails to clear must not break a session.

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-}"
# shellcheck disable=SC1091
source "$PLUGIN_ROOT/scripts/lib/util.sh"
# shellcheck disable=SC1091
source "$PLUGIN_ROOT/scripts/lib/index-sync.sh"

payload=$(cat)
gitlore_cd_project_root || exit 0   # the launch repo, never the session cwd (see util.sh)

gitlore_has_submodule || exit 0
mempath=$(gitlore_memory_path)
[ -e "$mempath/.git" ] || exit 0

session=$(jq -r '.session_id // ""' <<<"$payload")
gitlore_index_budget_nudge_reset "$mempath" "$session"
gitlore_upgrade_nudge_reset "$mempath" "$session"
exit 0
