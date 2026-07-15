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
replaced="" # newline-joined "  • path: <old> → <new>" bullets, one per
            # description this run actually changed. The agent authors a
            # considered `description:` and the canonical index hook then
            # overwrites it, so reporting the replaced *text* — not just the
            # filename — is the point: a silent clobber is the failure mode.
while IFS=$'\t' read -r path hook; do
  [ -n "$path" ] || continue
  prehook=$(awk -F'\t' -v p="$path" '$1==p{sub(/^[^\t]*\t/,""); print; exit}' <<<"$pre_pairs")
  [ "$hook" = "$prehook" ] && continue        # unchanged this edit → skip
  case "$path" in
    ..|../*|*/../*|*/..) continue ;;          # reject any ".." path component
  esac
  target="$mempath/$path"
  if [ "$target" -ef "$index" ]; then continue; fi   # never rewrite the index itself
  [ -f "$target" ] || continue                # orphan line → skip
  # Read the outgoing text BEFORE the rewrite. `|| true` is legitimate here
  # despite the plan's ban on it for fallible commands: rc 1 is the ordinary
  # "no description: line yet" case, and this read feeds the *report* only —
  # never the sync. Should it fail for a real reason, the same awk drives the
  # setter one line down, whose failure IS checked and surfaced; the worst
  # outcome here is a bullet that says "(unset)".
  old=$(gitlore_get_frontmatter_description "$target" 2>/dev/null) || true
  if ! gitlore_set_frontmatter_description "$target" "$hook"; then
    # A single failing target must not abort the loop — the rest still sync.
    printf 'gitlore: failed to update frontmatter description for %s\n' "$path" >&2
    if [ -z "$failed" ]; then failed="$path"; else failed="$failed, $path"; fi
  elif [ "$old" != "$hook" ]; then
    # Only an actual change is news; a file already carrying the hook stays
    # quiet. An unseeded file reports "(unset)" — nothing was lost there.
    if [ -z "$old" ]; then shown="(unset)"; else shown="\"$old\""; fi
    replaced="$replaced
  • $path: $shown → \"$hook\""
  fi
done <<<"$post_pairs"

# Unconditional, even when a propagation above failed: a surviving stale
# pre-image is dangerous — a later post-hook run would diff a fresh index
# against this ancient baseline and propagate wrong hooks.
rm -f "$stashfile"

# Both halves land in ONE object: two jq calls would print two concatenated
# objects, which CC does not parse. Build the strings here, encode once below.
sysmsg=""
ctx=""
if [ -n "$replaced" ]; then
  sysmsg="gitlore: synced description: to the MEMORY.md index line (canonical) —$replaced"
  # Model-only channel: without it the agent re-reads the files to work out
  # what the hook did. Does NOT inject under --print (tested via systemMessage).
  ctx="The gitlore index→frontmatter sync already rewrote the description: line of these memory files to match the index hook, which is canonical. This is expected and complete — do not re-read or re-edit them to verify. If a replaced description carried meaning the index hook loses, fix the index line, not the file.$replaced"
fi
if [ -n "$failed" ]; then
  # Never exit 1/2 here: PostToolUse cannot block/undo (the tool already ran),
  # and stdout JSON is only parsed on exit 0 (D14) — systemMessage + exit 0 is
  # the only channel proven user-visible. stderr above is a debug-log echo.
  if [ -n "$sysmsg" ]; then sysmsg="$sysmsg
"; fi
  sysmsg="${sysmsg}gitlore: index→frontmatter sync failed for: $failed — check file/directory permissions; the description may now be stale"
fi

if [ -n "$sysmsg" ]; then
  jq -n --arg s "$sysmsg" --arg c "$ctx" \
    '{systemMessage: $s}
     + (if $c == "" then {} else
         {hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $c}}
       end)'
fi
exit 0
