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
[ -e "$index" ] || exit 0
[ "$file" -ef "$index" ] || exit 0

stashfile=$(gitlore_index_preimage_file "$mempath")   # absolute
[ -f "$stashfile" ] || exit 0   # no baseline → nothing to diff

pre_pairs=$(gitlore_index_pairs "$stashfile")
post_pairs=$(gitlore_index_pairs "$index")

while IFS=$'\t' read -r path hook; do
  [ -n "$path" ] || continue
  prehook=$(awk -F'\t' -v p="$path" '$1==p{sub(/^[^\t]*\t/,""); print; exit}' <<<"$pre_pairs")
  [ "$hook" = "$prehook" ] && continue        # unchanged this edit → skip
  target="$mempath/$path"
  [ -f "$target" ] || continue                # orphan line → skip
  gitlore_set_frontmatter_description "$target" "$hook"
done <<<"$post_pairs"

rm -f "$stashfile"
exit 0
