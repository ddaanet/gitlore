#!/usr/bin/env bash
set -euo pipefail

# SessionStart + PreCompact: drop the recall ledger.
#
# The ledger answers "is this memory body already in context?", so it is only
# valid for as long as the context is. Two events end that:
#
#  - SessionStart. A fresh context. `--resume` keeps the session id but not the
#    context, so keying on the id alone is not enough — the reset must be
#    explicit.
#  - PreCompact. What survives a compaction is a summary, not the tool results,
#    and re-injection after /compact is guaranteed only for the project-root
#    CLAUDE.md — nothing covers memory bodies. Which reads the summarizer kept
#    is unknowable, so the whole ledger goes: re-fetching a body that is still
#    present wastes tokens, while assuming presence that is gone withholds a
#    fact the agent believes it holds. Only the first error is recoverable.
#
# Never fatal. A recall ledger that fails to clear must not break a session.

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-}"
# shellcheck disable=SC1091
source "$PLUGIN_ROOT/scripts/lib/util.sh"
# shellcheck disable=SC1091
source "$PLUGIN_ROOT/scripts/lib/recall.sh"

payload=$(cat)
cd "${CLAUDE_PROJECT_DIR:-$PWD}"

gitlore_has_submodule || exit 0
mempath=$(gitlore_memory_path)
[ -e "$mempath/.git" ] || exit 0

session=$(jq -r '.session_id // ""' <<<"$payload")
gitlore_recall_reset "$mempath" "$session"
exit 0
