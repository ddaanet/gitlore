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

gitlore_has_submodule || exit 0
mempath=$(gitlore_memory_path)
index="$mempath/MEMORY.md"

# Only the project index; identity via -ef (portable, no realpath).
[ -e "$index" ] || exit 0
[ "$file" -ef "$index" ] || exit 0

stash=$(gitlore_index_preimage_file "$mempath")   # absolute; parent dir exists
cp "$index" "$stash" || exit 0   # stash failed → no baseline; never block the Write
exit 0
