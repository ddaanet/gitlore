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

failed=""   # plain string accumulator (no arrays — dodges the bash-3.2/nounset
            # empty-array expansion trap); comma-joined list of failed paths
while IFS=$'\t' read -r path hook; do
  [ -n "$path" ] || continue
  prehook=$(awk -F'\t' -v p="$path" '$1==p{sub(/^[^\t]*\t/,""); print; exit}' <<<"$pre_pairs")
  [ "$hook" = "$prehook" ] && continue        # unchanged this edit → skip
  target="$mempath/$path"
  [ -f "$target" ] || continue                # orphan line → skip
  if ! gitlore_set_frontmatter_description "$target" "$hook"; then
    # A single failing target must not abort the loop — the rest still sync.
    printf 'gitlore: failed to update frontmatter description for %s\n' "$path" >&2
    if [ -z "$failed" ]; then failed="$path"; else failed="$failed, $path"; fi
  fi
done <<<"$post_pairs"

# Unconditional, even when a propagation above failed: a surviving stale
# pre-image is dangerous — a later post-hook run would diff a fresh index
# against this ancient baseline and propagate wrong hooks.
rm -f "$stashfile"

if [ -n "$failed" ]; then
  # Never exit 1/2 here: PostToolUse cannot block/undo (the tool already ran),
  # and stdout JSON is only parsed on exit 0 (D14) — systemMessage + exit 0 is
  # the only channel proven user-visible. stderr above is a debug-log echo.
  jq -n --arg list "$failed" \
    '{systemMessage: ("gitlore: index→frontmatter sync failed for: " + $list + " — check file/directory permissions; the description may now be stale")}'
fi
exit 0
