#!/usr/bin/env bash
set -euo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-}"
# shellcheck disable=SC1091
source "$PLUGIN_ROOT/scripts/lib/util.sh"
# shellcheck disable=SC1091
source "$PLUGIN_ROOT/scripts/lib/index-sync.sh"

payload=$(cat)
tool=$(jq -r '.tool_name // empty' <<<"$payload")
case "$tool" in Write|Edit) ;; *) exit 0 ;; esac

file=$(jq -r '.tool_input.file_path // empty' <<<"$payload")
[ -n "$file" ] || exit 0

gitlore_cd_project_root || exit 0   # the launch repo, never the session cwd (see util.sh)
gitlore_has_submodule || exit 0
mempath=$(gitlore_memory_path)
index="$mempath/MEMORY.md"

# Only the project index; identity via -ef (portable, no realpath).
[ -e "$index" ] || exit 0
[ "$file" -ef "$index" ] || exit 0

stash=$(gitlore_index_preimage_file "$mempath")   # absolute; parent dir exists

# First index edit of the batch establishes the baseline; later ones in the
# same batch must not overwrite it, or the batch-end sync would diff against a
# mid-batch state and miss everything the earlier edits changed. The post-hook
# removes the stash at batch end (even when the index went untouched), so an
# existing stash here always belongs to the batch in flight.
if [ -f "$stash" ]; then exit 0; fi

# Capture cp's reason rather than dropping it — "why" (no space, permissions,
# bad path) is exactly what makes this recoverable for the user.
if ! cp_err=$(cp "$index" "$stash" 2>&1); then
  # Never exit 2 (would block the Write) and never exit 1 (stdout JSON is
  # only parsed on exit 0 — D14). systemMessage + exit 0 is the only channel
  # proven user-visible regardless of exit code; stderr is a debug-log echo.
  printf 'gitlore: failed to stash the pre-edit MEMORY.md (%s): %s\n' "$stash" "$cp_err" >&2
  jq -n --arg stash "$stash" --arg err "$cp_err" \
    '{systemMessage: ("gitlore: failed to stash the pre-edit MEMORY.md (" + $stash + "): " + $err + "; index→frontmatter sync will be skipped for this edit")}'
fi
exit 0
