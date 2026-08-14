#!/usr/bin/env bash
set -euo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-}"
# shellcheck disable=SC1091
source "$PLUGIN_ROOT/scripts/lib/util.sh"
# shellcheck disable=SC1091
source "$PLUGIN_ROOT/scripts/lib/index-sync.sh"

# PostToolBatch, not PostToolUse: it fires once per batch carrying every call in
# .tool_calls[], so a batch with three Edits to the index syncs — and reports —
# once, instead of repeating itself per edit. A batch is one assistant message's
# calls, not a user turn: one turn fires this as many times as it takes batches.
#
# The batch's own calls are not inspected. What matters is whether the index
# CHANGED, and a tool call is a poor proxy for that in both directions: an Edit
# can rewrite a line to itself, and a `sed -i` under Bash never names its target
# at all. The pre-hook's stash answers the question directly — its presence says
# a watched call ran this batch, and comparing it to the file on disk says
# whether that call moved anything.
payload=$(cat)
session=$(jq -r '.session_id // ""' <<<"$payload")

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
refused=""  # newline-joined bullets for news lines whose hook carries a
            # markdown link — a welded-bullet artifact, refused rather than
            # propagated. See the guard in the loop.
refused_paths="" # the same lines, comma-joined, for the user's channel. A
            # refusal needs action, so — like a failed write and unlike the
            # routine sync — it names its files on the terse channel too.
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

  # A hook holding a markdown link is a welded-bullet artifact, not a hook: the
  # pair extractor splits on the FIRST ") — ", so two bullets joined onto one
  # physical line yield one syntactically valid pair whose "hook" contains the
  # whole second bullet. Propagating it is faithful to the input and exactly
  # wrong — it moves the corruption from the index, where a compose check and a
  # human both look, into a `description:` where neither does. The entry
  # already links its own file, so no legitimate hook needs a link. Refuse and
  # report; the fix is the index line, which the glued-bullet compose rule
  # names.
  case "$hook" in
    *']('*)
      refused="$refused
  • $path: \"$hook\""
      if [ -z "$refused_paths" ]; then refused_paths="$path"; else refused_paths="$refused_paths, $path"; fi
      continue
      ;;
  esac

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
nudge_file=$(gitlore_index_budget_nudge_file "$mempath" "$session")
if [ -n "$pct" ] && [ "$pct" -ge "$GITLORE_INDEX_BUDGET_WARN_PCT" ] && [ ! -f "$nudge_file" ]; then
  budget=1
  touch "$nudge_file"
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

if [ -n "$refused" ]; then
  n=$(printf '%s' "$refused" | grep -c '•')
  if [ "$n" -eq 1 ]; then unit="line"; else unit="lines"; fi
  if [ -n "$sysmsg" ]; then sysmsg="$sysmsg
"; fi
  sysmsg="${sysmsg}gitlore: refused to propagate $n welded MEMORY.md $unit — fix the index line for: $refused_paths"
  if [ -n "$ctx" ]; then ctx="$ctx

"; fi
  ctx="${ctx}These MEMORY.md hooks carry a markdown link, which means two pointer bullets are welded onto one physical line: everything after the first \`) — \` is a second entry, not hook text. Nothing was written to their frontmatter. The second path is invisible to every parse of the index, so the next composition reads it as a deletion and drops it — split the line in the INDEX before doing anything else. An \`Edit\` whose old_string begins with a newline and whose new_string is empty is what welds them.$refused"
fi

if [ -n "$budget" ]; then
  if [ -n "$sysmsg" ]; then sysmsg="$sysmsg
"; fi
  sysmsg="${sysmsg}gitlore: MEMORY.md is at ${pct}% of the ${GITLORE_INDEX_BUDGET_BYTES}-byte always-loaded budget"
  if [ -n "$ctx" ]; then ctx="$ctx

"; fi
  ctx="${ctx}MEMORY.md is at ${pct}% of the ${GITLORE_INDEX_BUDGET_BYTES}-byte budget. Past 24.4KB, Claude Code's own loader silently truncates the tail of this file — entries beyond the cutoff never reach a session."
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
