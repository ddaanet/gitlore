#!/usr/bin/env bash
set -euo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-}"
# shellcheck disable=SC1091
source "$PLUGIN_ROOT/scripts/lib/util.sh"
# shellcheck disable=SC1091
source "$PLUGIN_ROOT/scripts/lib/index-sync.sh"

# PostToolBatch, not PostToolUse: it fires once per turn carrying every call in
# .tool_calls[], so a turn with three Edits to the index syncs — and reports —
# once, instead of repeating itself per edit.
payload=$(cat)
files=$(jq -r '
  .tool_calls[]? | select(.tool_name == "Write" or .tool_name == "Edit")
  | .tool_input.file_path // empty' <<<"$payload")
[ -n "$files" ] || exit 0   # read-only batch

gitlore_has_submodule || exit 0
mempath=$(gitlore_memory_path)
index="$mempath/MEMORY.md"
[ -e "$index" ] || exit 0

stashfile=$(gitlore_index_preimage_file "$mempath")   # absolute

# Did any call in this batch write the index? Identity via -ef, as in the pre-hook.
touched=""
while IFS= read -r f; do
  [ -n "$f" ] || continue
  if [ -e "$f" ] && [ "$f" -ef "$index" ]; then touched=1; break; fi
done <<<"$files"

if [ -z "$touched" ]; then
  # The index survived this batch untouched, so there is nothing to propagate.
  # Still drop any stash: one stranded by an interrupted batch would otherwise
  # become the baseline for a later, unrelated edit and over-propagate. This
  # bounds a stale pre-image to a single batch.
  rm -f "$stashfile"
  exit 0
fi

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
  case "$path" in
    ..|../*|*/../*|*/..) continue ;;          # reject any ".." path component
  esac
  target="$mempath/$path"
  if [ "$target" -ef "$index" ]; then continue; fi   # never rewrite the index itself
  [ -f "$target" ] || continue                # orphan line → skip
  # Read the outgoing text BEFORE the rewrite. `|| true` is legitimate here
  # despite the plan's ban on it for fallible commands: rc 1 is the ordinary
  # "no description: line yet" case, and this read feeds both the added-line
  # fill-if-empty decision and the *report*. Should it fail for a real reason,
  # the same awk drives the setter below, whose failure IS checked and surfaced;
  # the worst outcome here is a bullet that says "(unset)".
  old=$(gitlore_get_frontmatter_description "$target" 2>/dev/null) || true
  # Key the sync on what happened to this index line (D17):
  #   • line present in the pre-image → propagate ONLY when its hook changed;
  #   • line ADDED this batch (absent from the pre-image) → fill the frontmatter
  #     ONLY when it is empty, so a description authored alongside the new index
  #     line is never clobbered by the terser one-liner that first referenced it.
  if awk -F'\t' -v p="$path" '$1==p{f=1; exit} END{exit !f}' <<<"$pre_pairs"; then
    prehook=$(awk -F'\t' -v p="$path" '$1==p{sub(/^[^\t]*\t/,""); print; exit}' <<<"$pre_pairs")
    [ "$hook" = "$prehook" ] && continue      # existing line, unchanged → skip
  else
    [ -n "$old" ] && continue                 # added line with authored prose → keep it
  fi
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
#
# The two channels are deliberately asymmetric. The user gets one line — the
# sync is routine, and the before/after detail is noise they did not ask for.
# The agent gets the full replacement list: at the explicitness needed for
# compliance, every clause there earns its place.
sysmsg=""
ctx=""
if [ -n "$replaced" ]; then
  n=$(printf '%s' "$replaced" | grep -c '•')
  if [ "$n" -eq 1 ]; then unit="file"; else unit="files"; fi
  sysmsg="gitlore: reset frontmatter to match MEMORY.md ($n $unit)"
  # Model-only channel: without it the agent re-reads the files to work out
  # what the hook did.
  ctx="The gitlore index→frontmatter sync already rewrote the description: line of these memory files to match the index hook, which is canonical. This is expected and complete — do not re-read or re-edit them to verify. If a replaced description carried meaning the index hook loses, fix the index line, not the file.$replaced"
fi
if [ -n "$failed" ]; then
  # Never exit 1/2 here: the batch already ran, so a non-zero exit cannot undo
  # it — it would only discard this JSON, since stdout is parsed on exit 0 only
  # (D14). A failure names its file: unlike the routine sync, it needs action.
  if [ -n "$sysmsg" ]; then sysmsg="$sysmsg
"; fi
  sysmsg="${sysmsg}gitlore: index→frontmatter sync failed for: $failed — check file/directory permissions; the description may now be stale"
fi

if [ -n "$sysmsg" ]; then
  # suppressOutput hides the raw stdout from the transcript; systemMessage is
  # the user's channel, additionalContext the model's.
  jq -n --arg s "$sysmsg" --arg c "$ctx" \
    '{systemMessage: $s, suppressOutput: true}
     + (if $c == "" then {} else
         {hookSpecificOutput: {hookEventName: "PostToolBatch", additionalContext: $c}}
       end)'
fi
exit 0
