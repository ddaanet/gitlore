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
#
# The batch's own calls are not inspected. What matters is whether the index
# CHANGED, and a tool call is a poor proxy for that in both directions: an Edit
# can rewrite a line to itself, and a `sed -i` under Bash never names its target
# at all. The pre-hook's stash answers the question directly — its presence says
# a watched call ran this batch, and comparing it to the file on disk says
# whether that call moved anything.
cat >/dev/null   # drain the payload; the stash, not its contents, is the signal

gitlore_cd_project_root || exit 0   # the launch repo, never the session cwd (see util.sh)
gitlore_has_submodule || exit 0
mempath=$(gitlore_memory_path)
index="$mempath/MEMORY.md"
[ -e "$index" ] || exit 0

stashfile=$(gitlore_index_preimage_file "$mempath")   # absolute

[ -f "$stashfile" ] || exit 0   # no baseline → no watched call, nothing to diff

if cmp -s "$stashfile" "$index"; then
  # The index survived this batch byte-identical, so there is nothing to
  # propagate. Drop the stash regardless: one stranded by an interrupted batch
  # would otherwise become the baseline for a later, unrelated edit and
  # over-propagate. This bounds a stale pre-image to a single batch.
  rm -f "$stashfile"
  exit 0
fi

pre_pairs=$(gitlore_index_pairs "$stashfile")
post_pairs=$(gitlore_index_pairs "$index")

failed=""   # plain string accumulator (no arrays — dodges the bash-3.2/nounset
            # empty-array expansion trap); comma-joined list of failed paths
replaced="" # newline-joined "  • path: <old> → <new>" bullets, one per
            # description this run actually changed. The agent authors a
            # considered `description:` and the canonical index hook then
            # overwrites it, so reporting the replaced *text* — not just the
            # filename — is the point: a silent clobber is the failure mode.
weak=""     # newline-joined bullets for news lines that look like weak routing
            # keys. Advisory only — see the block below the loop.
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
  # No redirect: "$target" is the file this batch just edited, so it exists — the
  # reader is silent on the ordinary "no description: line" miss and only writes
  # to stderr when the read itself genuinely failed.
  old=$(gitlore_get_frontmatter_description "$target") || true
  # Key the sync on what happened to this index line (D17):
  #   • line present in the pre-image → propagate ONLY when its hook changed;
  #   • line ADDED this batch (absent from the pre-image) → fill the frontmatter
  #     ONLY when it is empty, so a description authored alongside the new index
  #     line is never clobbered by the terser one-liner that first referenced it.
  added=""
  if awk -F'\t' -v p="$path" '$1==p{f=1; exit} END{exit !f}' <<<"$pre_pairs"; then
    prehook=$(awk -F'\t' -v p="$path" '$1==p{sub(/^[^\t]*\t/,""); print; exit}' <<<"$pre_pairs")
    [ "$hook" = "$prehook" ] && continue      # existing line, unchanged → not news
  else
    added=1
  fi

  # Routing-key advisory, on every NEWS line — deliberately BEFORE the
  # fill-if-empty bail below, because a line whose frontmatter the sync
  # declines to touch is still the canonical routing key. Conditioned on the
  # memory's type: a `reference` fact is reached by an error string, a flag or
  # an identifier, while a `feedback` rule is reached by topic and is right to
  # be prose. Ungated, the check fires on a third of a real index and becomes
  # noise to scroll past.
  ftype=$(gitlore_frontmatter_type "$target") || ftype=""
  case "$ftype" in
    reference|project)
      if ! gitlore_index_has_literal "$hook"; then
        weak="$weak
  • $path: \"$hook\""
      fi
      ;;
  esac

  if [ -n "$added" ] && [ -n "$old" ]; then
    continue                                  # added line with authored prose → keep it
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

# --- byte budget ------------------------------------------------------------
# Bytes, not lines: the index blob is loaded verbatim into every session, so a
# handful of paragraph-length lines cost more than fifty terse ones and that is
# where curation pays. Computed on the post-edit index, so it needs no
# pre-image; it reports only past the threshold, and only in a batch that
# touched the index — an untouched index cannot have grown.
budget=""
pct=$(gitlore_index_budget_pct "$index") || pct=""
if [ -n "$pct" ] && [ "$pct" -ge "$GITLORE_INDEX_BUDGET_WARN_PCT" ]; then
  budget=$(gitlore_index_largest "$index" 5 | while IFS=$'\t' read -r b p; do
    printf '\n  • %s: %s bytes' "$p" "$b"
  done)
fi

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

# The two advisories REPORT and never refuse — the same asymmetry the dangling
# pointer pass settled on. A thin hook is a quality regression, not corruption,
# and PostToolBatch could not undo the write in any case.
if [ -n "$weak" ]; then
  n=$(printf '%s' "$weak" | grep -c '•')
  if [ "$n" -eq 1 ]; then unit="line looks"; else unit="lines look"; fi
  if [ -n "$sysmsg" ]; then sysmsg="$sysmsg
"; fi
  sysmsg="${sysmsg}gitlore: $n MEMORY.md $unit like a weak routing key (no trigger token)"
  if [ -n "$ctx" ]; then ctx="$ctx

"; fi
  ctx="${ctx}These reference-type MEMORY.md lines carry no trigger token — no path, flag, error string, identifier, filename or version of the kind a future query would actually contain. The index one-liner is what CC's recall classifier matches on, and the sync above copies it over the file's own description:, so a hook without one weakens both surfaces at once. If a concrete token belongs in the line, edit the INDEX line (never the file). Ignore this where the hook is already as specific as the fact allows — a behavioural rule is reached by topic, and prose is right there.$weak"
fi

if [ -n "$budget" ]; then
  if [ -n "$sysmsg" ]; then sysmsg="$sysmsg
"; fi
  sysmsg="${sysmsg}gitlore: MEMORY.md is at ${pct}% of the ${GITLORE_INDEX_BUDGET_BYTES}-byte always-loaded budget"
  if [ -n "$ctx" ]; then ctx="$ctx

"; fi
  ctx="${ctx}MEMORY.md is at ${pct}% of the ${GITLORE_INDEX_BUDGET_BYTES}-byte budget. The whole index is loaded verbatim into every session, so the cost is bytes rather than lines and trimming the longest entries is what pays — a terse behavioural line is a rounding error next to these. Largest lines:$budget"
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
