#!/usr/bin/env bash
# Shared functions for memory divergence detection, state-file IO, and
# directive emission. Source; do not exec.
#
# Preparing a merge re-merges the index files, so this library pulls its own
# index dependencies in rather than making all five callers (both git hooks,
# session-start, commit-memory, resolve) declare a transitive need. Both are
# function-only and safe to source twice; util.sh is NOT (it declares a
# `readonly`), so it stays the caller's job, as does log.sh.
# shellcheck disable=SC1091
source "${BASH_SOURCE[0]%/*}/index-compose.sh"
# shellcheck disable=SC1091
source "${BASH_SOURCE[0]%/*}/index-merge.sh"

# Print every store under this memory tree — memory itself, then each mounted
# tier — in the order the gates visit them. One merge policy applies at every
# level, so callers that walk stores (divergence detection, the stale-state
# guard, the continuation's search for a prepared merge) all walk this list.
# Args: $1 = memory worktree path.
gitlore_memory_stores() {
  local mempath="$1" tier
  printf '%s\n' "$mempath"
  while IFS= read -r tier; do
    [ -n "$tier" ] || continue
    # `git -C` into an unchecked-out submodule escapes to the enclosing repo, so
    # an unmounted tier must never reach a caller.
    [ -e "$mempath/$tier/.git" ] || continue
    printf '%s/%s\n' "$mempath" "$tier"
  done < <(gitlore_tier_paths "$mempath")
}

# Print every store that currently holds a merge-state file. Normally none or
# one: a gate yields on the first divergence it meets and stops, so a second
# store's merge is not prepared until the first is landed.
# Args: $1 = memory worktree path.
gitlore_stores_with_merge_state() {
  local mempath="$1" store
  while IFS= read -r store; do
    [ -n "$store" ] || continue
    [ -f "$(gitlore_merge_state_file "$store")" ] || continue
    printf '%s\n' "$store"
  done < <(gitlore_memory_stores "$mempath")
}

# Detect whether a stale merge-state file, or an orphaned MERGE_HEAD with no
# state file at all, exists.
# Stdout: "clean" | "stale-with-merge-head" | "stale-no-merge-head" |
#         "orphaned-merge-head".
gitlore_detect_stale_merge_state() {
  local mempath="$1"
  local statefile gitdir
  statefile=$(gitlore_merge_state_file "$mempath")
  gitdir=$(git -C "$mempath" rev-parse --git-dir)
  if [ ! -f "$statefile" ]; then
    # A real MERGE_HEAD with no state file means gitlore_prepare_merge staged
    # a merge and the caller died before gitlore_write_merge_state recorded
    # it — the window an interrupted `push-memory.sh` run left open, with real
    # content staged and nothing pointing at it.
    if [ -f "$gitdir/MERGE_HEAD" ]; then
      printf 'orphaned-merge-head\n'
    else
      printf 'clean\n'
    fi
    return 0
  fi
  if [ -f "$gitdir/MERGE_HEAD" ]; then
    printf 'stale-with-merge-head\n'
  else
    printf 'stale-no-merge-head\n'
  fi
}

# Guard against a stale merge-state file before committing or pushing memory:
# never operate on top of a half-finished merge. On a clean state, return 0
# silently. Otherwise emit the appropriate directive/message on stderr and
# return 1, so callers can `|| return 1` / `|| exit 1`.
#   stale-with-merge-head → emit the merge directive again, so the prepared
#                            merge is continued
#   stale-no-merge-head    → classify and repair (gitlore_recover_stale_no_merge_head),
#                            which returns 0 when the caller may carry on
# Args: $1 = memory worktree path.
gitlore_guard_stale_merge_state() {
  local mempath="$1"
  local state_status statefile flavor
  state_status=$(gitlore_detect_stale_merge_state "$mempath")
  case "$state_status" in
    stale-with-merge-head)
      # A prepared merge is always continued. The store sits exactly where
      # gitlore_prepare_merge leaves one, so the sub-agent can pick it up
      # unchanged — and by the time a gate meets it again the merger may already
      # have synthesized and staged an answer, which discarding the merge would
      # throw away. A merge whose authority moved meanwhile lands against the
      # old one and is re-prepared by the continuation's own refused push, which
      # costs one cycle; re-preparing every stale merge costs a synthesis.
      statefile=$(gitlore_merge_state_file "$mempath")
      flavor=$(jq -r .flavor "$statefile")
      gitlore_emit_merge_directive "$statefile" "$flavor" "continue-after-merge"
      return 1
      ;;
    stale-no-merge-head)
      gitlore_recover_stale_no_merge_head "$mempath" || return 1
      ;;
    orphaned-merge-head)
      local mh
      mh=$(git -C "$mempath" rev-parse -q --verify MERGE_HEAD)
      echo "gitlore: MERGE_HEAD ($mh) is set in $mempath with no merge state file — manual intervention required. An earlier merge was interrupted before its state was recorded; $mh is the pending commit that needs re-merging." >&2
      return 1
      ;;
  esac
  return 0
}

# Repair — rather than report — a merge state file whose MERGE_HEAD is gone.
# Two things produce it, and they leave different remains. A plain
# `git merge --abort`, run in the store by a user or an agent asked to undo the
# merge, drops the pointers AND resets the index: nothing of the merge survives
# but gitlore's own files. `git checkout` — including the no-op re-checkout that
# `submodule update` runs — calls remove_branch_state(), which unlinks
# MERGE_HEAD and MERGE_MSG silently and on success, while leaving the staged
# result in the index; a clean auto-merge stages no unmerged entries, so
# checkout has nothing to refuse over. Either way the state file outlives the
# very pointer the guard discriminates on.
#
# Every question below is mechanical (D7), so the state has an outcome instead
# of a dead end (FR13). They are asked in the order in which each answer decides
# the next:
#
#   1. Did a merge land? A merge commit taking the pinned pending commit as a
#      parent other than its first IS that merge, wherever HEAD sits now.
#   2. Is a merge result still staged? The index survives the checkout that took
#      the pointers, and what it holds may be a synthesis already approved.
#   3. Neither: the merge is dead, and every artifact a preparation wrote is
#      recomputed by the next one.
#
# Returns 0 when the store is fit for the caller's gate to carry on — which
# re-prepares the merge if the divergence is still there — and 1 after emitting
# when the merge needs its sub-agent again, or cannot be classified.
# Args: $1 = store worktree path.
gitlore_recover_stale_no_merge_head() {
  local store="$1"
  local statefile abs head pending landed msg err
  statefile=$(gitlore_merge_state_file "$store")
  # `--show-toplevel` rather than a subshell `cd`: every path below is printed
  # for a human to paste, and CDPATH glues a directory listing onto the front of
  # a `$(cd … && pwd)` capture.
  abs=$(git -C "$store" rev-parse --show-toplevel) || abs="$store"
  head=$(git -C "$store" rev-parse HEAD)

  pending=$(gitlore_pending_commit "$store" "$statefile")
  if [ -z "$pending" ]; then
    msg="gitlore: $abs holds a merge state file with no MERGE_HEAD, and neither $GITLORE_PENDING_REF nor the file's own source_ref names a commit still in the store — nothing can say whether that merge landed, so manual intervention required. Read $statefile, then find the merge with:
gitlore:   git -C \"$abs\" log --oneline --graph --all --reflog -n 20
gitlore: delete $statefile once you have landed or abandoned it; the next commit or push prepares the merge again."
    gitlore_say_for_agent_or_user "$msg" "$msg" >&2
    return 1
  fi

  if ! landed=$(gitlore_landed_merge_commit "$store" "$pending"); then
    msg="gitlore: $abs holds a merge state file with no MERGE_HEAD, and its history could not be scanned for the merge (git's own error is above), so manual intervention required. Repair the store, then re-run the operation."
    gitlore_say_for_agent_or_user "$msg" "$msg" >&2
    return 1
  fi
  if [ -n "$landed" ]; then
    gitlore_recover_landed_merge "$store" "$abs" "$head" "$landed" || return 1
    return 0
  fi

  # Nothing landed. An index that differs from HEAD holds the merge result the
  # checkout could not take with it, which may be a synthesis the user already
  # approved — restored, never discarded. Emits either way; the caller yields.
  if ! git -C "$store" diff-index --quiet --cached HEAD --; then
    gitlore_restore_staged_merge "$store" "$abs" "$head" "$pending" "$statefile"
    return 1
  fi

  # Nothing landed and nothing staged: the merge is dead. HEAD goes back onto
  # the pending commit BEFORE the pin is dropped — after a preparation the pin
  # is the only reference to the divergent side, so clearing it while HEAD sits
  # on the authority would orphan the very commit the merge existed to land, and
  # the gate that follows would find a store with nothing to merge.
  if ! err=$(gitlore_git -C "$store" checkout -q --detach "$pending" 2>&1); then
    msg="gitlore: the prepared merge in $abs is dead (no MERGE_HEAD, nothing staged, nothing landed), but HEAD could not be put back on its pending commit $pending, so the merge state was left alone. git said:
$err
gitlore: clear the working tree, then re-run the operation."
    gitlore_say_for_agent_or_user "$msg" "$msg" >&2
    return 1
  fi
  gitlore_drop_merge_preparation "$store"
  msg="gitlore: the prepared merge in $abs was cleared out from under gitlore — a 'git merge --abort' or a checkout in the store — leaving no MERGE_HEAD, nothing staged and nothing landed. Its leftover state is discarded and HEAD is back on the pending commit $(git -C "$store" rev-parse --short "$pending"); the merge is prepared again if the divergence is still there."
  gitlore_say_for_agent_or_user "$msg" "$msg" >&2
  return 0
}

# The merge landed and a later checkout or reset moved HEAD off it. Restore HEAD onto the
# merge commit where that can lose nothing, and name the exact commands
# otherwise. Returns 0 when the store is fit to carry on, 1 after emitting when
# it is not.
# Args: $1 = store, $2 = abs store path, $3 = HEAD sha, $4 = landed merge sha.
gitlore_recover_landed_merge() {
  local store="$1" abs="$2" head="$3" landed="$4"
  local msg err
  if git -C "$store" merge-base --is-ancestor "$landed" "$head"; then
    # HEAD already carries the merge; only the bookkeeping outlived it. This is
    # also where a by-hand recovery lands after putting HEAD back, which is why
    # the report below has to name no cleanup of its own.
    gitlore_drop_merge_preparation "$store"
    msg="gitlore: the merge in $abs already landed as $landed and HEAD carries it, so only its leftover merge state was cleared."
    gitlore_say_for_agent_or_user "$msg" "$msg" >&2
    return 0
  fi
  # Moving HEAD is safe only when the merge contains everything HEAD has and the
  # tree holds nothing uncommitted: the checkout can then lose nothing, which is
  # what makes automating it a repair rather than a guess.
  if [ "$(gitlore_memory_dirty "$store")" = "1" ] \
     || ! git -C "$store" merge-base --is-ancestor "$head" "$landed"; then
    msg="gitlore: the merge in $abs landed as $landed, and a later checkout or reset moved HEAD off it onto $head. Nothing was changed here — the store has uncommitted work, or holds commits that merge does not. Read what is there, then put HEAD back:
gitlore:   git -C \"$abs\" status --short
gitlore:   git -C \"$abs\" log --oneline --left-right $landed...$head
gitlore:   git -C \"$abs\" checkout --detach $landed
gitlore: then re-run the git operation: with HEAD on the merge, the leftover merge state is cleared for you and the operation carries on."
    gitlore_say_for_agent_or_user "$msg" "$msg" >&2
    return 1
  fi
  if ! err=$(gitlore_git -C "$store" checkout -q --detach "$landed" 2>&1); then
    msg="gitlore: the merge in $abs landed as $landed, a later checkout or reset moved HEAD off it, and HEAD could not be put back. git said:
$err
gitlore: restore it with: git -C \"$abs\" checkout --detach $landed, then re-run the operation."
    gitlore_say_for_agent_or_user "$msg" "$msg" >&2
    return 1
  fi
  gitlore_drop_merge_preparation "$store"
  msg="gitlore: the merge in $abs landed as $landed before a checkout or reset moved HEAD off it; HEAD is restored to it and the leftover merge state cleared, so none of that merge is lost."
  gitlore_say_for_agent_or_user "$msg" "$msg" >&2
  return 0
}

# A merge result is staged and its pointers are gone. Restore MERGE_HEAD and
# MERGE_MSG so the store sits exactly where gitlore_prepare_merge leaves one,
# then emit the merge directive: the staged tree may be a synthesis the user
# already approved, and discarding the merge would throw it away along with the
# worktree it was written into. Restoring is refused when HEAD is not the
# authority the state file names — that commit is what the merge was built on,
# and re-attaching a second parent to some other HEAD invents a merge nobody
# prepared. Emits in every case; the caller yields either way.
# Args: $1 = store, $2 = abs store path, $3 = HEAD sha, $4 = pending sha,
#       $5 = state file path.
gitlore_restore_staged_merge() {
  local store="$1" abs="$2" head="$3" pending="$4" statefile="$5"
  local target authority flavor gitdir msg
  target=$(jq -r '.target_ref // ""' "$statefile")
  authority=""
  if [ -n "$target" ]; then
    # `-q --verify` is silent on the expected miss: an authority ref a later
    # fetch or prune removed.
    authority=$(git -C "$store" rev-parse -q --verify "$target^{commit}") || authority=""
  fi
  if [ -z "$authority" ] || [ "$head" != "$authority" ]; then
    msg="gitlore: $abs holds a staged merge whose MERGE_HEAD a checkout cleared, but HEAD is at $head while the authority it was built on ('$target') is at ${authority:-no commit this store can resolve}. Restoring the merge onto this HEAD would record a merge nobody prepared, so nothing was changed. Read the staged tree with:
gitlore:   git -C \"$abs\" diff --cached
gitlore: then either commit it deliberately or reset the store to a commit you trust, and re-run the operation."
    gitlore_say_for_agent_or_user "$msg" "$msg" >&2
    return 0
  fi
  gitdir=$(git -C "$store" rev-parse --absolute-git-dir)
  # git's own wording for `merge <sha>` on a detached HEAD, so what the
  # continuation commits reads as the merge it is.
  if ! { printf '%s\n' "$pending" > "$gitdir/MERGE_HEAD" \
         && printf "Merge commit '%s' into HEAD\n" "$pending" > "$gitdir/MERGE_MSG"; }; then
    rm -f "$gitdir/MERGE_HEAD" "$gitdir/MERGE_MSG"
    msg="gitlore: $abs holds a staged merge whose MERGE_HEAD a checkout cleared, and the pointers could not be written back into $gitdir. Restore them by hand, then re-run the operation:
gitlore:   printf '%s\\n' $pending > \"$gitdir/MERGE_HEAD\"
gitlore:   printf \"Merge commit '%s' into HEAD\\n\" $pending > \"$gitdir/MERGE_MSG\""
    gitlore_say_for_agent_or_user "$msg" "$msg" >&2
    return 0
  fi
  flavor=$(jq -r .flavor "$statefile")
  msg="gitlore: a checkout had cleared MERGE_HEAD in $abs but left the merge staged, so the merge pointers are restored and the staged result is intact."
  gitlore_say_for_agent_or_user "$msg" "$msg" >&2
  gitlore_emit_merge_directive "$statefile" "$flavor" "continue-after-merge"
}

# Print the pending (divergent) commit a prepared merge was landing, or nothing.
# The pin is authoritative — gitlore_prepare_merge writes it before HEAD moves —
# and the state file's `source_ref` records the same sha a moment later, so
# either answers on its own. Both are verified to still name a commit: a state
# file written by hand, or one whose pin was deleted and whose commit was then
# pruned, names something no classification can be built on.
# Args: $1 = store, $2 = state file path.
gitlore_pending_commit() {
  local store="$1" statefile="$2" sha
  if sha=$(git -C "$store" rev-parse -q --verify "$GITLORE_PENDING_REF^{commit}"); then
    printf '%s\n' "$sha"
    return 0
  fi
  sha=$(jq -r '.source_ref // ""' "$statefile") || return 0
  [ -n "$sha" ] || return 0
  git -C "$store" rev-parse -q --verify "$sha^{commit}" || return 0
}

# Print the sha of a merge commit that took $2 as a parent other than its first,
# or nothing. Returns 1 if the history could not be scanned at all.
#
# Every ref AND every reflog: a merge that landed and was then checked out away
# from is reachable from no ref, while HEAD's reflog still names it — and since
# the reflogs are among `git fsck`'s roots, "is there an unreachable commit" is
# silent on exactly the case this exists to catch.
#
# The scan is captured before it is parsed rather than piped into awk: under
# `pipefail` an awk that stops at the first match leaves rev-list writing into a
# closed pipe, which turns a found merge into a failed scan. `rev-list --parents`
# emits fixed-width hex and nothing else, so splitting it on whitespace carries
# none of the usual hazard. Args: $1 = store, $2 = pending commit.
gitlore_landed_merge_commit() {
  local store="$1" pending="$2" scan
  scan=$(git -C "$store" rev-list --all --reflog --merges --parents) || return 1
  printf '%s\n' "$scan" \
    | awk -v p="$pending" '!found { for (i = 3; i <= NF; i++) if ($i == p) { print $1; found = 1 } }'
}

# Drop everything a preparation wrote: the state file and its briefing artifacts
# (gitlore_clear_merge_state owns that list, so it cannot drift from
# gitlore_write_merge_state), then the pending pin. Deleted rather than moved
# aside — each one is recomputed from the two sides by the next preparation, so
# a copy would only be a stale duplicate of a file about to be rewritten.
# Args: $1 = store worktree path.
gitlore_drop_merge_preparation() {
  local store="$1"
  gitlore_clear_merge_state "$store"
  # Guarded rather than unconditional: a state file written before the pin
  # existed, or one left by an interrupted preparation, has no ref to delete.
  if git -C "$store" rev-parse -q --verify "$GITLORE_PENDING_REF" >/dev/null; then
    gitlore_git -C "$store" update-ref -d "$GITLORE_PENDING_REF"
  fi
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
  changed=$({ git -C "$mempath" diff --name-only "$base...$target"; \
              git -C "$mempath" diff --name-only "$base...$source"; } \
    | sort -u | jq -R . | jq -s .) || changed='[]'
  # Git's unmerged entries, plus any index file the entry-wise re-merge left
  # with markers. The second set is not in the first: an index conflict git
  # never saw is precisely what the entry-wise pass exists to surface, and it
  # resolves the file in the worktree without staging it.
  conflicted=$({ git -C "$mempath" diff --name-only --diff-filter=U; \
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
  git -C "$mempath" ls-files | sort -u > "$treef" || : > "$treef"
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
gitlore_emit_merge_directive() {
  local statefile="$1" flavor="$2" cont="$3"
  local root="${PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-}}"
  local repo store
  repo=$(git rev-parse --show-toplevel)
  store=$(jq -r '.store // "?"' "$statefile")
  cat >&2 <<EOF
gitlore: memory merge prepared (flavor=$flavor) in store:
gitlore:   $store
gitlore: dispatch sub-agent gitlore:memory-merger with state file:
gitlore:   $statefile
gitlore: that dispatch is a required step of the git operation that triggered
gitlore: this merge, not an option: the request for that operation is the
gitlore: request for this dispatch, so make it now without asking first. What
gitlore: still needs approval is the merge the sub-agent proposes, not the
gitlore: dispatch itself.
gitlore: on approval of its synthesis, the sub-agent must run:
gitlore:   cd "$repo" && bash "$root/scripts/resolve.sh" $cont
EOF
}

# Prepare a merge of the pending commit into the more authoritative side. One
# shape serves both flavors (D17 unified branch model): memory is detached at
# `live`, so the authority is reached with `checkout --detach` — no named branch
# is ever checked out, so the one-checkout-per-branch contention that used to
# make this fail (D3) cannot arise, and there is no branch to return to.
# The authority becomes the merge's FIRST parent (D6); the pending commit is
# merged in as the second. The pending commit is pinned at
# `$GITLORE_PENDING_REF` before HEAD moves — nothing else references it once
# `merge --abort` drops MERGE_HEAD.
# The pending ref is taken from the caller rather than assumed to be HEAD: an
# earlier interrupted run can leave HEAD sitting ON the authority (the checkout
# below already ran; the caller died before recording state), and a raw
# `rev-parse HEAD` would then re-diagnose real, still-unmerged divergence as
# nothing to merge. Callers pass whichever ref their own flavor treats as the
# pending side — `HEAD` for head-vs-live (this call is inherently about HEAD
# vs the `live` branch), `live` for head-vs-remote (HEAD can be displaced by a
# prior interruption; the local `live` branch is untouched by a checkout onto
# some other authority).
# Args: $1 = memory worktree path, $2 = authority ref (`live` or `origin/live`),
#       $3 = pending ref (`HEAD` or `live`).
# Stdout: `<base_sha>:<pending_sha>`.
gitlore_prepare_merge() {
  local mempath="$1" authority="$2" pending_ref="$3"
  local pending base merge_err restore_err
  pending=$(git -C "$mempath" rev-parse "$pending_ref")
  # Nothing to merge: the authority already contains the pending commit, so the
  # merge below would report "Already up to date." and leave no MERGE_HEAD.
  # Tested BEFORE the checkout, because that checkout is a side effect — a
  # failed diagnosis that moves HEAD onto the authority is what silently
  # un-adopts a store, by making the next `/gitlore:merge` take its
  # "already holds everything" early return and skip the adopt step. Callers
  # classify by ancestry and do not reach here in this state; this is the lock
  # on the mutating path itself.
  if git -C "$mempath" merge-base --is-ancestor "$pending" "$authority"; then
    printf 'gitlore: %s already contains HEAD, so there is no merge to prepare.\n' "$authority" >&2
    return 1
  fi
  base=$(git -C "$mempath" merge-base "$pending" "$authority")
  gitlore_git -C "$mempath" update-ref "$GITLORE_PENDING_REF" "$pending"
  gitlore_git -C "$mempath" checkout -q --detach "$authority"
  # A conflicting merge is the EXPECTED outcome here — the conflicted worktree is
  # exactly what the merger sub-agent resolves — so a non-zero exit is not a
  # failure and the conflict listing is noise the state file already carries in
  # `conflicted_files`. Captured rather than discarded, because a merge that
  # failed for some other reason (an unmergeable ref, an index left unmerged by
  # something else) leaves no MERGE_HEAD, and the directive would then announce a
  # merge nobody prepared. MERGE_HEAD is the discriminator; git's own words are
  # what the user gets when it is absent.
  #
  # `merge.conflictStyle=diff3` is set per invocation rather than in the store's
  # config: this merge is gitlore's, and a store's config is also the user's.
  # The base section is what makes a memory conflict resolvable — with only two
  # versions, "one side added this sentence" and "the other side deleted it" are
  # the same picture, and the resolver has to guess which.
  merge_err=$(gitlore_git -C "$mempath" -c merge.conflictStyle=diff3 \
    merge --no-commit --no-ff "$pending" 2>&1) || true
  if ! git -C "$mempath" rev-parse -q --verify MERGE_HEAD >/dev/null; then
    printf '%s\n' "$merge_err" >&2
    # Put HEAD back where it was. The checkout above was preparation for a merge
    # that did not happen, and handing the caller a moved HEAD makes a failed
    # diagnosis indistinguishable from a landed one. No --force: the stores
    # reaching here are clean, and a checkout refused by real content is a
    # message worth having rather than a tree worth discarding.
    if ! restore_err=$(gitlore_git -C "$mempath" checkout -q --detach "$pending" 2>&1); then
      printf 'gitlore: HEAD in %s is still at %s after a merge that could not be prepared. Restore it with: git -C "%s" checkout --detach %s\ngit said: %s\n' \
        "$mempath" "$authority" "$mempath" "$pending" "$restore_err" >&2
    fi
    return 1
  fi
  # Redo every index file entry-wise, over git's line-wise result. Unconditional:
  # the failure this catches — both sides adding the same pointer path at
  # different offsets, which merges CLEANLY into a duplicate — leaves no
  # conflict for a conditional to test.
  gitlore_merge_indexes "$mempath" "$base" "$authority" "$pending" >/dev/null || \
    echo "gitlore: the entry-wise index merge could not run in $mempath; git's line-wise result stands." >&2
  printf '%s:%s\n' "$base" "$pending"
}

# Prepare the merge, record its state file, and emit the sub-agent directive.
# The caller yields (return/exit 1) immediately afterwards. Returns 1 without
# emitting if the merge could not be prepared at all.
# Args: $1 = memory worktree path, $2 = authority ref, $3 = flavor label,
#       $4 = pending ref (see gitlore_prepare_merge).
gitlore_yield_merge() {
  local mempath="$1" authority="$2" flavor="$3" pending_ref="$4"
  local prep base pending statefile
  if ! prep=$(gitlore_prepare_merge "$mempath" "$authority" "$pending_ref"); then
    gitlore_say_for_agent_or_user \
      "gitlore: could not prepare the memory merge against '$authority'. Inspect the memory worktree at $mempath." \
      "gitlore: could not prepare the memory merge against '$authority'. Inspect the memory worktree at $mempath." >&2
    return 1
  fi
  base="${prep%%:*}"
  pending="${prep#*:}"
  if ! gitlore_write_merge_state "$mempath" "$flavor" "$base" "$pending" "$authority" "continue-after-merge"; then
    gitlore_say_for_agent_or_user \
      "gitlore: the merge was prepared in $mempath but its state file could not be written, so no continuation can run. Inspect the memory worktree." \
      "gitlore: the merge was prepared in $mempath but its state file could not be written, so no continuation can run. Inspect the memory worktree." >&2
    return 1
  fi
  statefile=$(gitlore_merge_state_file "$mempath")
  gitlore_emit_merge_directive "$statefile" "$flavor" "continue-after-merge"
  return 0
}

# Why a push was refused, decided by ancestry rather than by git's wording.
#
# git rejects a merely BEHIND ref with the same "(fetch first)" /
# "(non-fast-forward)" it gives a genuinely DIVERGED one — both are
# non-fast-forward pushes — and only divergence has a merge to prepare. A behind
# store has nothing of its own to publish at all, so routing it into the merge
# flow ends in a preparation that finds nothing and a diagnostic naming a
# worktree that is clean. The parenthesized reason still separates "the ref
# could not fast-forward" from a policy or credential refusal; this separates
# the two ancestries hiding behind that one reason.
#
# `ahead` is the pushed ref already containing the target, which means the
# refusal was not about ancestry: the remote moved during the push, or the fetch
# that precedes it failed and the target ref is stale.
# Args: $1 = store, $2 = pushed ref, $3 = target ref.
# Stdout: behind | diverged | ahead | unknown.
gitlore_classify_refusal() {
  local store="$1" pushed="$2" target="$3" p t
  # `-q --verify` on both: a ref that cannot be read is not a classification,
  # and answering "diverged" for one would start a merge on a guess.
  p=$(git -C "$store" rev-parse -q --verify "$pushed") || { printf 'unknown\n'; return 0; }
  t=$(git -C "$store" rev-parse -q --verify "$target") || { printf 'unknown\n'; return 0; }
  if git -C "$store" merge-base --is-ancestor "$p" "$t"; then
    printf 'behind\n'
  elif git -C "$store" merge-base --is-ancestor "$t" "$p"; then
    printf 'ahead\n'
  else
    printf 'diverged\n'
  fi
}

# Refuse to publish a store whose HEAD and local `live` name different commits.
#
# A store is checked out DETACHED AT `live` (D17), so the two agree in every
# state the tooling produces. They are read by different halves of the publish,
# though: the push sends `live`, while a merge preparation — and the gitlink the
# enclosing commit records — reason from HEAD. Once they disagree, a push can
# succeed while the recorded pointer never reaches the remote (lockstep broken
# silently), or be refused on a ref the merge preparation never looks at, which
# is how a rejection gets diagnosed against a HEAD that has nothing to say.
#
# Reported, never repaired: which ref is the intended one is not recoverable
# from the refs themselves, and the drift means some earlier step left the store
# in a state no normal path produces.
# Args: $1 = store, $2 = label. Returns 1 after emitting when they disagree.
gitlore_check_head_live_agree() {
  local store="$1" label="$2" head live abs remedy
  head=$(git -C "$store" rev-parse -q --verify HEAD) || return 0
  # No local `live` yet (a tier never fetched) — nothing to disagree with.
  live=$(git -C "$store" rev-parse -q --verify live) || return 0
  [ "$head" != "$live" ] || return 0
  # `--show-toplevel` rather than a subshell `cd`: the remedy below is printed
  # for a human to paste, so the path has to be absolute, and CDPATH turns
  # `$(cd … && pwd)` into a path with a directory listing glued to the front.
  abs=$(git -C "$store" rev-parse --show-toplevel) || abs="$store"
  if git -C "$store" merge-base --is-ancestor "$head" "$live"; then
    remedy="Put HEAD back on 'live': git -C \"$abs\" checkout --detach live"
  elif git -C "$store" merge-base --is-ancestor "$live" "$head"; then
    remedy="Advance 'live' to HEAD: git -C \"$abs\" push . HEAD:live"
  else
    remedy="HEAD and 'live' have each moved since they last agreed; run /gitlore:resolve to reconcile them."
  fi
  gitlore_say_for_agent_or_user \
    "gitlore: $label's HEAD is not at its local 'live' (HEAD $(git -C "$store" rev-parse --short "$head"), live $(git -C "$store" rev-parse --short "$live")), so nothing was published. $remedy" \
    "gitlore: $label's HEAD is not at its local 'live' (HEAD $(git -C "$store" rev-parse --short "$head"), live $(git -C "$store" rev-parse --short "$live")), so nothing was published. $remedy" >&2
  return 1
}

# Commit every dirty tier and fast-forward each one's local `live`, reusing the
# episode's single approved summary as the commit message (D17 lockstep).
#
# One approval per episode, not per store: the user approves a set of writes,
# not a set of repositories, so the same summary lands in every store the
# episode touched. The approval prompt is what groups those writes by
# destination — a line bound for a shared tier is more public than one bound for
# project memory, and that is the part the user needs to see.
#
# Runs BEFORE memory's own `git add -A`, so the moved tier gitlink is part of
# the memory commit — the same before-and-alongside staircase the parent applies
# to memory, one level deeper.
#
# Scope is every MOUNTED tier, not only the active ones: the activation manifest
# governs routing and composition, and silently dropping a dormant tier's writes
# would be data loss rather than dormancy.
#
# Recursion is driver-side by design; the memory store gets no recursing
# pre-commit. The parent already drives memory exactly this way, and a
# hook-side version would have to re-litigate the full local-env-var unset and
# the GIT_INDEX_FILE capture/restore at a level that needs neither, while
# forcing the FR11 gate to share a hook with the driver.
#
# Returns 1 after emitting a message if a tier commits but its local `live`
# cannot be advanced. Args: $1 = memory worktree path, $2 = approved msg file.
gitlore_sync_tiers_to_live() {
  local mempath="$1" msgfile="$2" tier tierpath push_err
  while IFS= read -r tier; do
    [ -n "$tier" ] || continue
    tierpath="$mempath/$tier"
    # Guard submodule escape: `git -C` into an unchecked-out submodule path walks
    # up to the enclosing repo, so without this a fresh clone would commit the
    # MEMORY store under the tier's name.
    [ -e "$tierpath/.git" ] || continue
    # Same precheck memory gets: never commit on top of a half-finished merge.
    gitlore_guard_stale_merge_state "$tierpath" || return 1
    [ "$(gitlore_memory_dirty "$tierpath")" = "1" ] || continue
    gitlore_git -C "$tierpath" add -A
    # Blessed commit: the same sentinel that admits a memory commit past the FR11
    # gate, which emit-memory-gate.sh installs in each tier too.
    GITLORE_MEMORY_COMMIT=1 gitlore_git -C "$tierpath" commit -q -F "$msgfile"
    # `live` exists once SessionStart has fetched it; a tier that has never been
    # fetched has no local `live` to advance, and `-q --verify` is silent on that
    # expected miss.
    if git -C "$tierpath" rev-parse -q --verify live >/dev/null; then
      if ! push_err=$(gitlore_git -C "$tierpath" push -q . HEAD:live 2>&1); then
        # Same discriminator memory uses: only git's parenthesized reason means
        # divergence, and only divergence is something a merge can fix.
        case "$push_err" in
          *"(fetch first)"*|*"(non-fast-forward)"*) ;;
          *)
            gitlore_say_for_agent_or_user \
              "gitlore: tier '$tier' was committed but its local 'live' could not be advanced, and not because of divergence. git said:
$push_err" \
              "gitlore: tier '$tier' was committed but its local 'live' could not be advanced. git said:
$push_err" >&2
            return 1
            ;;
        esac
        # Same two ancestries behind the one reason: `live` already containing
        # HEAD is drift, not divergence, and has no merge to prepare.
        if [ "$(gitlore_classify_refusal "$tierpath" HEAD live)" = "diverged" ]; then
          # Diverged from its own local `live` — the same gate memory has here,
          # and the same resolution. The merge lands in the tier's gitdir.
          gitlore_yield_merge "$tierpath" live head-vs-live HEAD || return 1
        elif gitlore_check_head_live_agree "$tierpath" "tier '$tier'"; then
          # Refused with the two refs in agreement and no divergence: neither
          # diagnosis applies, so git's own words are all there is to go on.
          gitlore_say_for_agent_or_user \
            "gitlore: tier '$tier' was committed but its local 'live' could not be advanced, though HEAD and 'live' agree and neither has diverged. git said:
$push_err" \
            "gitlore: tier '$tier' was committed but its local 'live' could not be advanced. git said:
$push_err" >&2
        fi
        return 1
      fi
    fi
  done < <(gitlore_tier_paths "$mempath")
  return 0
}

# Commit dirty memory with the blessed sentinel and fast-forward local `live`.
# Assumes the memory worktree exists (caller guards `[ -e "$mempath/.git" ]`).
# Returns 0 on success or no-op. Returns 1 after emitting a directive when:
#   a stale merge state is present, memory is dirty without a fresh approved
#   commit-msg file, or the `HEAD:live` fast-forward fails (the pending commit
#   diverged from `live`). Source the util/log/resolve libs before calling.
# Args: $1 = memory worktree path.
gitlore_sync_memory_to_live() {
  local mempath="$1"

  # Stale merge-state precheck: never commit on top of a half-finished merge.
  gitlore_guard_stale_merge_state "$mempath" || return 1

  local msgfile dirty live_sha head_sha
  msgfile=$(gitlore_commit_msg_file "$mempath")
  dirty=$(gitlore_memory_dirty "$mempath")
  # `-q --verify` is silent when `live` does not exist (the expected miss), so no
  # redirect is needed and a real rev-parse failure is no longer swallowed.
  live_sha=$(git -C "$mempath" rev-parse -q --verify live || echo "")
  head_sha=$(git -C "$mempath" rev-parse HEAD)

  if [ "$dirty" = "0" ] && [ "$head_sha" = "$live_sha" ]; then
    return 0
  fi

  if [ "$dirty" = "1" ]; then
    local fresh
    fresh=$(gitlore_commit_msg_freshness "$mempath")
    if [ "$fresh" != "yes" ]; then
      # The clause is a multi-line block, so it goes last rather than mid-sentence.
      gitlore_say_for_agent_or_user \
        "$(printf '%s\n\n%s\n' \
          "gitlore: memory is dirty and has no approved commit summary. Prepare a summary and present it to the user as a markdown blockquote (\`> …\`), not a code fence, for confirmation; treat only a clear, un-negated affirmative as approval (a hedge, a question, or any negation is a rejection). Only once approved, write it to $msgfile, then retry." \
          "$(gitlore_memory_approval_clause)")" \
        "gitlore: memory has uncommitted changes with no approved commit summary. Open this project in Claude Code and ask it to commit memory, then retry." >&2
      return 1
    fi
    # Tiers first: a tier commit moves its gitlink, and the `add -A` below is what
    # records that move in the memory commit. Reversing the order would pin the
    # pre-commit tier SHA — the same one-behind lag the parent's gitlink staging
    # exists to prevent.
    gitlore_sync_tiers_to_live "$mempath" "$msgfile" || return 1
    gitlore_git -C "$mempath" add -A
    # Blessed commit: carry the sentinel so the submodule gate (memory-pre-commit)
    # admits it. A naked commit never sets this and is blocked (FR11/D12).
    GITLORE_MEMORY_COMMIT=1 gitlore_git -C "$mempath" commit -q -F "$msgfile"
    rm -f "$msgfile"
    # The dirty episode is over: clear the once-per-episode nudge marker so the
    # next round of uncommitted memory can be surfaced again (post-tool-use.sh).
    rm -f "$(gitlore_commit_notified_file "$mempath")"
  fi

  if [ -n "$live_sha" ]; then
    # Capture, don't discard: this push is to the local repo (`.`), where a
    # non-fast-forward genuinely does mean HEAD-vs-live divergence — but a
    # failure for any OTHER reason (a ref lock, a corrupt object) would have been
    # read as divergence too, sending the user into a merge that cannot help.
    local push_err=""
    if ! push_err=$(gitlore_git -C "$mempath" push -q . HEAD:live 2>&1); then
      case "$push_err" in
        *"(fetch first)"*|*"(non-fast-forward)"*) ;;
        *)
          if [ -n "$push_err" ]; then
            gitlore_say_for_agent_or_user \
              "gitlore: updating the local 'live' ref failed, and not because of divergence. git said:
$push_err" \
              "gitlore: updating the local 'live' ref failed, and not because of divergence. git said:
$push_err" >&2
            return 1
          fi
          ;;
      esac
      # ff-push failed. Divergence is one of the two ancestries git reports that
      # way; the other is `live` already containing HEAD, where there is nothing
      # to fast-forward and nothing to merge.
      if [ "$(gitlore_classify_refusal "$mempath" HEAD live)" = "diverged" ]; then
        gitlore_yield_merge "$mempath" live head-vs-live HEAD || return 1
      elif gitlore_check_head_live_agree "$mempath" "memory"; then
        # Refused with the two refs in agreement and no divergence: neither
        # diagnosis applies, so git's own words are all there is to go on.
        gitlore_say_for_agent_or_user \
          "gitlore: updating the local 'live' ref failed, though HEAD and 'live' agree and neither has diverged. git said:
$push_err" \
          "gitlore: updating the local 'live' ref failed. git said:
$push_err" >&2
      fi
      return 1
    fi
  fi

  return 0
}

# Publish every store to its own remote: each tier's `live` first, then memory's.
# Assumes the memory worktree exists (caller guards `[ -e "$mempath/.git" ]`).
# Returns 0 when everything is published (already-up-to-date included, and a
# memory store that has no remote of its own once its tiers are out). Returns 1
# after emitting a message when a tier has no remote, a stale merge state is
# present, a push is refused, or the remote is unreachable; a refusal that git
# attributes to divergence yields a prepared merge for `/gitlore:resolve`.
#
# Shared by `pre-push` (publishing alongside the parent) and `push-memory.sh`
# (publishing on its own, with no parent push — D20). One implementation, so the
# ordering guarantee below cannot drift between the two entry points.
# Args: $1 = memory worktree path.
gitlore_push_stores() {
  local mempath="$1" remote_url tier tierpath tier_err push_err

  # Never publish on top of a half-finished merge, at any level.
  gitlore_guard_stale_merge_state "$mempath" || return 1

  # Resolved here but acted on AFTER the tiers: memory having no remote says
  # nothing about theirs. A repo whose memory is deliberately local can still
  # mount a shared tier, and that tier is the part other repositories read.
  remote_url=$(git -C "$mempath" config --get remote.origin.url || true)
  # A `git submodule sync` on a local-only install copies the placeholder out of
  # `.gitmodules` into origin, where it names no repository. Same state as an
  # unset remote, and diagnosing it as an unreachable host would send the user
  # after a network problem they do not have.
  if gitlore_is_placeholder_url "$remote_url"; then
    remote_url=""
  fi

  # Tier push lockstep (D17). Each tier is an independent repo with its own remote,
  # and the memory commit about to be published records its gitlink — so every tier
  # commit must reach its remote BEFORE that pointer goes out, or a colleague
  # fetches memory and cannot resolve the tier. Driver-side, like memory's own
  # push: the memory store gets no recursing pre-push.
  # Failure here is fatal. A tier that silently stops publishing is indistinguish-
  # able from one with nothing to say, which is exactly how shared memory rots.
  while IFS= read -r tier; do
    [ -n "$tier" ] || continue
    tierpath="$mempath/$tier"
    # Unchecked-out tier: `git -C` escapes to the enclosing repo, which would push
    # MEMORY's live to memory's origin under the tier's name.
    [ -e "$tierpath/.git" ] || continue
    # `-q --verify` is silent on the expected miss: a tier never fetched has no
    # local `live` and so has nothing of its own to publish.
    git -C "$tierpath" rev-parse -q --verify live >/dev/null || continue
    if [ -z "$(git -C "$tierpath" config --get remote.origin.url || true)" ]; then
      gitlore_say_for_agent_or_user \
        "gitlore: tier '$tier' has no remote configured, so nothing written there is being shared. Mount it against a remote or unmount it." \
        "gitlore: tier '$tier' has no remote configured, so nothing written there is being shared." >&2
      return 1
    fi
    # Never push on top of a half-finished merge, at any level.
    gitlore_guard_stale_merge_state "$tierpath" || return 1
    # Before anything is published: what goes out is `live`, what the memory
    # commit records is HEAD. A store whose refs disagree publishes something
    # other than the commit its pointer names.
    gitlore_check_head_live_agree "$tierpath" "tier '$tier'" || return 1
    # `origin/live` has to be current before it can serve as the merge authority.
    # Non-fatal, exactly as memory's is: the push below is what decides.
    git -C "$tierpath" fetch -q origin live || true
    if ! tier_err=$(gitlore_git -C "$tierpath" push -q origin live 2>&1); then
      # Same discriminator as memory's push below: git's parenthesized reason
      # separates divergence from policy/credential/quota refusals, and ancestry
      # then separates the two states that share the divergence reason.
      case "$tier_err" in
        *"(fetch first)"*|*"(non-fast-forward)"*)
          case "$(gitlore_classify_refusal "$tierpath" live origin/live)" in
            behind)
              # Nothing of ours to publish, which is `/gitlore:merge`'s business
              # rather than a failure: the tier commit this memory push records
              # is already contained in the remote, so the lockstep this loop
              # exists to guarantee holds. Carry on to the next tier.
              gitlore_say_for_agent_or_user \
                "gitlore: tier '$tier' has nothing to publish — its remote 'live' is ahead of the local one. Run /gitlore:merge to take those facts." \
                "gitlore: tier '$tier' has nothing to publish — its remote 'live' is ahead of the local one. Run /gitlore:merge to take those facts." >&2
              continue
              ;;
            diverged)
              # One merge policy at every level: prepare against the tier's own
              # `origin/live` and yield, exactly as memory does below.
              gitlore_yield_merge "$tierpath" origin/live head-vs-remote live || return 1
              return 1
              ;;
            *)
              # Refused as non-fast-forward while `live` already contains
              # origin/live, or with a ref that could not be read. Nothing here
              # is a merge: preparing one against a stale authority would send
              # out a merge missing the work that caused the refusal.
              gitlore_say_for_agent_or_user \
                "gitlore: pushing tier '$tier' was refused as a non-fast-forward, but its local 'live' already contains the remote's. The remote moved during the push, or the fetch before it failed. git said:
$tier_err" \
                "gitlore: pushing tier '$tier' was refused as a non-fast-forward, but its local 'live' already contains the remote's. The remote moved during the push, or the fetch before it failed. git said:
$tier_err" >&2
              return 1
              ;;
          esac
          ;;
        *)
          gitlore_say_for_agent_or_user \
            "gitlore: pushing tier '$tier' failed, and not because of divergence. git said:
$tier_err" \
            "gitlore: pushing tier '$tier' failed, and not because of divergence. git said:
$tier_err" >&2
          ;;
      esac
      return 1
    fi
  done < <(gitlore_tier_paths "$mempath")

  # A memory store with no remote of its own is a supported end state, not a
  # broken install: `/gitlore:install` keeps the placeholder when no provider is
  # available, and a repo can share its tiers while keeping its project facts
  # local. Say so and stop, having published what there was to publish. Failing
  # instead would make memory's local-only-ness withhold the tiers — the one part
  # other repositories actually read.
  if [ -z "$remote_url" ]; then
    gitlore_say_for_agent_or_user \
      "gitlore: memory has no remote of its own, so it stays local; every mounted tier was published. Run /gitlore:resolve to give memory a remote if it is meant to be shared." \
      "gitlore: memory has no remote of its own, so it stays local; every mounted tier was published." >&2
    return 0
  fi

  # The same pre-publish invariant the tiers get: `live` is what goes out, HEAD
  # is what the parent's gitlink records.
  gitlore_check_head_live_agree "$mempath" "memory" || return 1

  # No redirect: `-q` already silences progress, so anything fetch writes here is a
  # real problem. Non-fatal (`|| true`) — the push below is the operation that counts.
  git -C "$mempath" fetch -q origin live || true

  # Capture rather than discard the push error: the two branches below diagnose
  # only "unreachable" and "divergence", and a push can fail for neither reason
  # (protected branch, pre-receive rejection, bad credentials on a reachable host,
  # quota). Those used to land in the divergence branch and start a bogus merge
  # resolution with git's actual explanation thrown away. Keeping the text lets the
  # fall-through report the real cause.
  push_err=""
  if push_err=$(gitlore_git -C "$mempath" push -q origin live 2>&1); then
    return 0
  fi

  # Push failed. Distinguish unreachable from divergence. Provoking the error IS
  # the mechanism here — the question is only whether the remote answers at all —
  # so the redirect is the point rather than a swallowed message.
  if ! git -C "$mempath" ls-remote origin >/dev/null 2>&1; then
    gitlore_say_for_agent_or_user \
      "gitlore: memory remote unreachable. Check network or 'gh auth status'." \
      "gitlore: memory remote unreachable. Check network or 'gh auth status'." >&2
    return 1
  fi

  # Reachable, and the push was refused. Divergence is the only cause a merge can
  # fix; anything else (policy hook, protected branch, quota, credentials) is not,
  # and used to be misdiagnosed as divergence with git's explanation discarded.
  # The discriminator is git's parenthesized reason, verified against real output:
  #   divergence → " ! [rejected]        HEAD -> live (fetch first)"
  #                (or "(non-fast-forward)")
  #   policy     → " ! [remote rejected] HEAD -> live (pre-receive hook declined)"
  case "$push_err" in
    *"(fetch first)"*|*"(non-fast-forward)"*) ;;
    *)
      if [ -n "$push_err" ]; then
        gitlore_say_for_agent_or_user \
          "gitlore: pushing memory to its remote failed, and not because of divergence. git said:
$push_err" \
          "gitlore: pushing memory to its remote failed, and not because of divergence. git said:
$push_err" >&2
        return 1
      fi
      ;;
  esac

  # Reachable, and refused for an ancestry reason. Which one decides everything:
  # only divergence has a merge to prepare.
  case "$(gitlore_classify_refusal "$mempath" live origin/live)" in
    behind)
      # Every tier is published and memory has nothing of its own to send. Taking
      # the remote's facts is `/gitlore:merge`'s job, and reporting this as a
      # failed push would send the user after a merge that has nothing to merge.
      gitlore_say_for_agent_or_user \
        "gitlore: memory has nothing to publish — its remote 'live' is ahead of the local one. Run /gitlore:merge to take those facts." \
        "gitlore: memory has nothing to publish — its remote 'live' is ahead of the local one. Run /gitlore:merge to take those facts." >&2
      return 0
      ;;
    diverged) ;;
    *)
      gitlore_say_for_agent_or_user \
        "gitlore: pushing memory was refused as a non-fast-forward, but its local 'live' already contains the remote's. The remote moved during the push, or the fetch before it failed. git said:
$push_err" \
        "gitlore: pushing memory was refused as a non-fast-forward, but its local 'live' already contains the remote's. The remote moved during the push, or the fetch before it failed. git said:
$push_err" >&2
      return 1
      ;;
  esac

  # HEAD-vs-remote divergence. Prepare and yield.
  gitlore_yield_merge "$mempath" origin/live head-vs-remote live || return 1
  return 1
}

# Take whatever each store's remote is holding, without publishing anything:
# every tier first, then memory. The counterpart of gitlore_push_stores, and the
# only path by which a pinned tier advances (D17) — SessionStart names an
# upstream-ahead tier, this is what acts on it.
#
# Three outcomes per store, decided by ancestry against the fetched `origin/live`:
#
#   - the remote is already contained in HEAD → nothing to take. Local commits
#     awaiting publication are /gitlore:push's business, not this one's.
#   - HEAD is an ancestor of the remote → take it by fast-forward, then ADOPT:
#     for a tier, its merged carrier becomes root's block for it. No sub-agent —
#     nothing is in dispute, and spending a synthesis on a fast-forward would
#     make taking upstream facts expensive enough to skip.
#   - neither contains the other → prepare a merge and yield, exactly as a
#     refused push does, but marked not-to-publish.
#
# A dirty store is refused rather than checked out over: the working tree may
# hold this session's uncommitted facts, and a fast-forward would either fail
# mid-way or carry them onto a commit nobody approved them against.
#
# Returns 0 when every store is reconciled (nothing-to-take included), 1 after
# emitting a message otherwise — including the prepared-merge directive.
# Args: $1 = memory worktree path.
gitlore_merge_stores() {
  local mempath="$1" tier tierpath

  gitlore_guard_stale_merge_state "$mempath" || return 1

  while IFS= read -r tier; do
    [ -n "$tier" ] || continue
    tierpath="$mempath/$tier"
    # `git -C` into an unchecked-out submodule walks up to the enclosing repo.
    [ -e "$tierpath/.git" ] || continue
    gitlore_guard_stale_merge_state "$tierpath" || return 1
    gitlore_merge_one_store "$mempath" "$tierpath" "$tier" || return 1
  done < <(gitlore_tier_paths "$mempath")

  gitlore_merge_one_store "$mempath" "$mempath" "" || return 1
  return 0
}

# One store's reconcile. Args: $1 = memory worktree, $2 = store worktree,
# $3 = tier name ("" when the store IS the memory root, which adopts nothing —
# its own MEMORY.md moves with the fast-forward).
gitlore_merge_one_store() {
  local mempath="$1" store="$2" tier="$3"
  local label remote_url remote head fetch_err

  if [ -n "$tier" ]; then label="tier '$tier'"; else label="memory"; fi

  remote_url=$(git -C "$store" config --get remote.origin.url || true)
  if [ -z "$remote_url" ] || gitlore_is_placeholder_url "$remote_url"; then
    # A tier exists to be shared, so one with no remote is a misconfiguration
    # worth stopping on. The memory root is not: a local-only install is a
    # supported end state (D20), and there is genuinely nothing to take.
    if [ -z "$tier" ]; then
      printf 'gitlore: memory has no remote of its own; nothing to take.\n'
      return 0
    fi
    gitlore_say_for_agent_or_user \
      "gitlore: $label has no remote configured, so there is nothing to take. Mount it against a remote or unmount it." \
      "gitlore: $label has no remote configured, so there is nothing to take." >&2
    return 1
  fi
  if ! fetch_err=$(git -C "$store" fetch -q origin live 2>&1); then
    gitlore_say_for_agent_or_user \
      "gitlore: could not fetch $label from its remote. git said:
$fetch_err" \
      "gitlore: could not fetch $label from its remote. git said:
$fetch_err" >&2
    return 1
  fi
  # `-q --verify` is silent on the expected miss: a remote with no `live` yet.
  remote=$(git -C "$store" rev-parse -q --verify refs/remotes/origin/live) || {
    printf 'gitlore: %s — its remote has no '\''live'\'' branch yet; nothing to take.\n' "$label"
    return 0
  }
  head=$(git -C "$store" rev-parse HEAD) || return 1

  if git -C "$store" merge-base --is-ancestor "$remote" "$head"; then
    printf 'gitlore: %s — already holds everything its remote does.\n' "$label"
    return 0
  fi

  if [ "$(gitlore_memory_dirty "$store")" = "1" ]; then
    gitlore_say_for_agent_or_user \
      "gitlore: $label has uncommitted changes, so its remote was left untouched. Commit them (approved summary, then a memory commit) and run /gitlore:merge again." \
      "gitlore: $label has uncommitted changes, so its remote was left untouched. Commit them and merge again." >&2
    return 1
  fi

  if ! git -C "$store" merge-base --is-ancestor "$head" "$remote"; then
    # Diverged. Same preparation a refused push yields, marked not-to-publish so
    # the continuation stops after the local `HEAD:live` fast-forward.
    GITLORE_MERGE_NO_PUBLISH=1 gitlore_yield_merge "$store" origin/live head-vs-remote HEAD || return 1
    return 1
  fi

  # Fast-forward: advance the local `live` (created here when the store never had
  # one), then move the working tree onto it. `push .` is ff-checked, so a race
  # that advanced `live` underneath us is refused rather than overwritten.
  local ff_err
  if ! ff_err=$(gitlore_git -C "$store" push -q . "$remote:refs/heads/live" 2>&1); then
    gitlore_say_for_agent_or_user \
      "gitlore: could not advance $label's local 'live'. git said:
$ff_err" \
      "gitlore: could not advance $label's local 'live'. git said:
$ff_err" >&2
    return 1
  fi
  if ! ff_err=$(gitlore_git -C "$store" checkout -q --detach live 2>&1); then
    gitlore_say_for_agent_or_user \
      "gitlore: $label's 'live' advanced but its working tree could not follow. git said:
$ff_err" \
      "gitlore: $label's 'live' advanced but its working tree could not follow. git said:
$ff_err" >&2
    return 1
  fi
  printf 'gitlore: %s — fast-forwarded to %s\n' "$label" "$(git -C "$store" rev-parse --short HEAD)"

  # Adopt: the carrier that just arrived becomes root's block for this tier. The
  # memory root adopts nothing — its own index is one of the files that moved.
  if [ -n "$tier" ]; then
    local composed rc=0
    composed=$(gitlore_compose_up "$mempath" "$tier") || rc=$?
    if [ "$rc" -eq 0 ]; then
      [ -n "$composed" ] && printf '%s\n' "$composed" | sed 's/^/gitlore: /'
    else
      printf 'gitlore: the root index could not take %s'\''s lines, so they are not recallable yet. Fix the store, then edit MEMORY.md to retrigger composition:\n' "$label" >&2
      printf '%s\n' "$composed" | sed 's/^/gitlore:   /' >&2
    fi
    # Stage the pair the fast-forward just produced. `submodule update` reads the
    # gitlink from the superproject's INDEX, so an unstaged one is walked back to
    # the pre-merge commit by the next SessionStart tier pass — and the composed
    # root index, being an ordinary working-tree write, survives to describe
    # facts the tier no longer holds. Staged, the unconditional pin is idempotent
    # rather than destructive. Both still ride the next FR11 memory commit; this
    # commits nothing. Staging is best-effort: a failure here must not turn a
    # landed fast-forward into a failed merge.
    # shellcheck disable=SC2016  # backticks are markdown for the reader, not a command sub
    gitlore_git -C "$mempath" add -- MEMORY.md "$tier" \
      || printf 'gitlore: %s advanced, but its pointer could not be staged in the memory store. Run `git -C %s add -- MEMORY.md %s` before the next session, or the pointer will be reset to its previous commit.\n' "$label" "$mempath" "$tier" >&2
  fi
  return 0
}
