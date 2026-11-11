#!/usr/bin/env bash
# Merge-state file IO and the sub-agent directive: write and complete the
# marker a preparation records before it runs, and emit the structured
# directive that dispatches gitlore:memory-merger.
# Part of lib/resolve.sh; source that, not this file.
#
# Where that state lives and whether a store holds one — the gitdir paths, their
# remover, and the mid-merge predicates — is util-merge-state.sh instead, so a
# caller that never sources resolve.sh can still order its work behind a merge.

# Write the merge-state file a preparation records BEFORE it starts, so no
# window inside gitlore_prepare_merge can leave a merge no gate can see. It
# carries what is known before the merge runs — which store, which flavor, which
# two sides, which continuation — and none of the briefing, which only exists
# once the merge has staged a tree. gitlore_write_merge_state overwrites it with
# the full file on success; gitlore_complete_merge_state fills it in afterwards
# when an interruption fell in between.
#
# `changed_files` is the discriminator between the two, because it is the first
# field the merger sub-agent reads and the one no marker can carry.
# Args: $1=store path  $2=flavor  $3=source_ref  $4=target_ref  $5=continuation.
gitlore_write_merge_marker() {
  local store="$1" flavor="$2" source="$3" target="$4" cont="$5"
  local statefile store_abs
  statefile=$(gitlore_merge_state_file "$store")
  store_abs=$(CDPATH='' cd -- "$store" && pwd)
  # Same jq-built, temp-file-then-rename shape as the full state file: a path
  # holding a `"` or a `\` must not produce JSON the first reader cannot parse,
  # and a half-written file would block every later commit in this store.
  jq -n \
    --arg flavor "$flavor" \
    --arg store "$store_abs" \
    --arg source "$source" \
    --arg target "$target" \
    --arg cont "$cont" \
    --arg publish "${GITLORE_MERGE_NO_PUBLISH:+no}" \
    '{flavor: $flavor, store: $store, source_ref: $source, target_ref: $target,
      continuation: $cont, publish: $publish}' \
    > "$statefile.tmp" || { rm -f "$statefile.tmp"; return 1; }
  mv "$statefile.tmp" "$statefile" || { rm -f "$statefile.tmp"; return 1; }
}

# Fill in a marker left by an interrupted preparation, from the merge the store
# already holds. A no-op on a complete state file, so it is safe to call
# wherever one is about to be handed to the merger sub-agent.
#
# The base is recomputed rather than recorded, because a marker is written
# before gitlore_prepare_merge computes one — same merge-base of the same two
# sides, unless the target ref moved while the preparation was interrupted, in
# which case the briefing describes the authority the merge was NOT built on.
# That is the trade the whole path already makes for a merge whose authority
# moved while it waited: it lands against the side it was built on, and the
# continuation's own refused push re-prepares it.
# Args: $1 = store. Returns 1 if the file cannot be completed.
gitlore_complete_merge_state() {
  local store="$1" statefile flavor source target cont base
  statefile=$(gitlore_merge_state_file "$store")
  [ -f "$statefile" ] || return 1
  if jq -e 'has("changed_files")' "$statefile" >/dev/null 2>&1; then
    return 0
  fi
  flavor=$(jq -r '.flavor // ""' "$statefile")
  source=$(jq -r '.source_ref // ""' "$statefile")
  target=$(jq -r '.target_ref // ""' "$statefile")
  cont=$(jq -r '.continuation // "continue-after-merge"' "$statefile")
  [ -n "$source" ] && [ -n "$target" ] || return 1
  base=$(git -C "$store" merge-base "$source" "$target") || return 1
  gitlore_write_merge_state "$store" "$flavor" "$base" "$source" "$target" "$cont"
}

# Write a JSON merge-state file. All args required.
#
# `store` records WHICH store the merge belongs to, absolutely. Memory and every
# tier share one merge policy and one state-file name, each resolved inside its
# own gitdir — so the file alone cannot say which repository it describes, and
# both readers need to know: the continuation commits there, and the merger
# sub-agent resolves `changed_files` against it. Absolute, so neither depends on
# the CWD it happens to be invoked with.
# Args: $1=store path (memory or tier worktree)  $2=flavor  $3=base_sha
#       $4=source_ref  $5=target_ref  $6=continuation_subcommand
gitlore_write_merge_state() {
  local mempath="$1" flavor="$2" base="$3" source="$4" target="$5" cont="$6"
  local statefile store_abs
  statefile=$(gitlore_merge_state_file "$mempath")
  store_abs=$(CDPATH='' cd -- "$mempath" && pwd)
  local changed conflicted
  # Union of files changed on either side of the merge — target_ref (HEAD post-checkout)
  # AND source_ref (the incoming branch). diff base...HEAD alone misses source-side files.
  # The `||` sits OUTSIDE the substitution so the fallback REPLACES the capture.
  # Inside it, a producer that fails after jq already printed `[]` — which
  # `pipefail` propagates through the whole pipeline — appends a second array and
  # hands jq's --argjson two JSON documents.
  # -c core.quotePath=false: git octal-escapes any non-ASCII byte (or a `"`/`\`)
  # in a bare --name-only path, independent of -z, so a tier is a store owned by
  # another repo — ASCII-only paths are a convention there, not an invariant.
  changed=$({ git -c core.quotePath=false -C "$mempath" diff --name-only "$base...$target"; \
              git -c core.quotePath=false -C "$mempath" diff --name-only "$base...$source"; } \
    | sort -u | jq -R . | jq -s .) || changed='[]'
  # Git's unmerged entries, plus any index file the entry-wise re-merge left
  # with markers. The second set is not in the first: an index conflict git
  # never saw is precisely what the entry-wise pass exists to surface, and it
  # resolves the file in the worktree without staging it.
  conflicted=$({ git -c core.quotePath=false -C "$mempath" diff --name-only --diff-filter=U; \
                 gitlore_conflicted_indexes "$mempath"; } \
    | sort -u | jq -R . | jq -s .) || conflicted='[]'
  [ -n "$changed" ] || changed='[]'
  [ -n "$conflicted" ] || conflicted='[]'

  # The briefing: what each side DID, and what the store holds. Reading the
  # merged worktree shows the outcome but not the intent — which side introduced
  # a line, and which merely carried it — and that is the judgement the merge
  # asks for. Written as files rather than inlined: they are unbounded, and the
  # state file is parsed by jq on every later gate.
  local minef theirsf treef
  minef=$(gitlore_merge_artifact_file "$mempath" mine.diff)
  theirsf=$(gitlore_merge_artifact_file "$mempath" theirs.diff)
  treef=$(gitlore_merge_artifact_file "$mempath" tree)
  git -C "$mempath" diff "$base" "$target" > "$minef" || : > "$minef"
  git -C "$mempath" diff "$base" "$source" > "$theirsf" || : > "$theirsf"
  git -c core.quotePath=false -C "$mempath" ls-files | sort -u > "$treef" || : > "$treef"
  # `publish` records whether landing this merge should also push the result. It
  # is empty for every gate — a merge prepared because a push was refused exists
  # to let that push succeed — and "no" only when /gitlore:merge asked to
  # reconcile without publishing. Carried in the state file rather than inferred
  # at continuation time: by then the entry point that had the intent is gone.
  #
  # jq builds the JSON rather than a heredoc interpolating into it: $store_abs is
  # a filesystem path, and one containing a `"` or a `\` produces a file that the
  # first reader — `jq -r .flavor` in the stale-state guard — cannot parse, which
  # surfaces as a blocked commit with a jq syntax error instead of a merge.
  # Written through a temp file so a jq failure cannot leave a truncated state
  # file behind: a half-written one blocks every later commit in this store.
  jq -n \
    --arg flavor "$flavor" \
    --arg store "$store_abs" \
    --arg base "$base" \
    --arg source "$source" \
    --arg target "$target" \
    --arg cont "$cont" \
    --arg mine "$minef" \
    --arg theirs_diff "$theirsf" \
    --arg tree "$treef" \
    --argjson changed "$changed" \
    --argjson conflicted "$conflicted" \
    --arg publish "${GITLORE_MERGE_NO_PUBLISH:+no}" \
    '{flavor: $flavor, store: $store, base: $base, source_ref: $source,
      target_ref: $target, changed_files: $changed,
      conflicted_files: $conflicted, mine_diff: $mine,
      theirs_diff: $theirs_diff, tree: $tree, continuation: $cont,
      publish: $publish}' \
    > "$statefile.tmp" || { rm -f "$statefile.tmp"; return 1; }
  mv "$statefile.tmp" "$statefile" || { rm -f "$statefile.tmp"; return 1; }
}

# Emit the structured directive on stderr.
# Args: $1=statefile_path  $2=flavor  $3=continuation_subcommand
# The banner keeps the literal "gitlore: memory merge prepared" prefix that
# `skills/resolve/SKILL.md` triggers on, and names the store after it — a tier
# merge and a memory merge are otherwise indistinguishable in the output.
# Emits absolute paths for both the parent repo root (cd target — needed because
# the continuation invokes git plumbing that reads .gitmodules from CWD) and
# the plugin's resolve.sh. Sub-agent runs the command verbatim; no env vars or
# CWD assumptions required.
#
# The directive AUTHORIZES the dispatch rather than offering it. Its reader is
# the agent, and the harness above it carries a blanket "do not call the
# AgentTool unless the user requested it" that no repo-level configuration can
# qualify. Text that merely names the sub-agent reads as one option among
# several, so the agent reports the blocker and stops — a round trip that once
# stalled a release mid-push. The licence is stated, not assumed: the git
# operation that triggered this merge is itself the request for the dispatch,
# which keeps the authorization scoped to this dispatch instead of reading as
# permission to skip a gate in general. The agent name stays plugin-qualified;
# a bare `memory-merger` fails discovery with `Agent type not found`.
# This is the shape for every gitlore directive that names a sub-agent.
#
# `index_problems` rides along whenever the state file carries it. The merged
# index gate prints its lines to whoever ran the continuation, and that reader
# may be gone by the time the merge is met again — a `/clear`, a compaction, a
# fresh session. The directive is the whole briefing the next sub-agent gets,
# so the lines it must clear travel with it rather than with the session that
# first saw them.
gitlore_emit_merge_directive() {
  local statefile="$1" flavor="$2" cont="$3"
  local root="${PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-}}"
  local repo store problems
  repo=$(git rev-parse --show-toplevel)
  store=$(jq -r '.store // "?"' "$statefile")
  problems=$(jq -r '(.index_problems // [])[]' "$statefile") || problems=""
  cat >&2 <<EOF
gitlore: memory merge prepared (flavor=$flavor) in store:
gitlore:   $store
gitlore: dispatch sub-agent gitlore:memory-merger with state file:
gitlore:   $statefile
EOF
  if [ -n "$problems" ]; then
    cat >&2 <<EOF
gitlore: the synthesis this merge holds fails the merged-index check. Brief the
gitlore: sub-agent to clear these lines, each in the file it names:
EOF
    printf '%s\n' "$problems" | sed 's/^/gitlore:   /' >&2
  fi
  cat >&2 <<EOF
gitlore: that dispatch is a required step of the git operation that triggered
gitlore: this merge, not an option: the request for that operation is the
gitlore: request for this dispatch, so make it now without asking first. Review
gitlore: the synthesis it returns yourself — both sides of this merge already
gitlore: passed an approval gate, so do not prompt the user (D49).
gitlore: on approval of its synthesis, the sub-agent must run:
gitlore:   cd "$repo" && bash "$root/scripts/resolve.sh" $cont
EOF
}

# Record what the merged-index check last said about the store's prepared merge,
# so every later directive can emit it. Called with the check's whole output on
# every run of the gate, empty output included: the field describes the
# synthesis the gate just read, and a merge kept prepared for some other reason
# — a refused commit, a message that would not build — must not brief the next
# sub-agent to fix text nobody objects to.
#
# Edited into the existing file rather than folded into gitlore_write_merge_state:
# the gate runs long after the preparation, and rewriting the state file there
# would recompute a briefing from a store the merger has since rewritten.
# Written through a temp file, as every other write of this file is: a truncated
# state file blocks every later commit in the store.
# Args: $1 = store worktree path, $2 = the check's problem lines (may be empty).
# Returns 1 if the file could not be updated.
gitlore_record_merge_index_problems() {
  local store="$1" problems="$2" statefile json
  statefile=$(gitlore_merge_state_file "$store")
  [ -f "$statefile" ] || return 1
  if [ -n "$problems" ]; then
    # One JSON string per line, so a line holding a space, a quote or a leading
    # `-` reaches the emitter as the bytes the check printed. `jq -R` reads its
    # lines from stdin, where nothing is an option.
    json=$(printf '%s\n' "$problems" | jq -R . | jq -s .) || return 1
  else
    json='[]'
  fi
  jq --argjson problems "$json" '.index_problems = $problems' "$statefile" \
    > "$statefile.tmp" || { rm -f "$statefile.tmp"; return 1; }
  mv "$statefile.tmp" "$statefile" || { rm -f "$statefile.tmp"; return 1; }
}
