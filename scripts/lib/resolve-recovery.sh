#!/usr/bin/env bash
# Repair a stale merge-state file: classify what a lost MERGE_HEAD or a
# checkout-cleared merge left behind, and put the store back into a state the
# gates can act on — landed, staged-but-unpointed, or dead.
# Part of lib/resolve.sh; source that, not this file.

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

  # A marker with nothing landed and nothing staged is a preparation interrupted
  # before its merge ran — the checkout onto the authority had happened, nothing
  # else had. Same disposal as a dead merge below, with the message the store's
  # own history supports.
  if ! jq -e 'has("changed_files")' "$statefile" >/dev/null 2>&1; then
    if ! err=$(gitlore_git -C "$store" checkout -q --detach "$pending" 2>&1); then
      msg="gitlore: a merge preparation in $abs was interrupted before its merge ran, but HEAD could not be put back on its pending commit $pending, so its state was left alone. git said:
$err
gitlore: clear the working tree, then re-run the operation."
      gitlore_say_for_agent_or_user "$msg" "$msg" >&2
      return 1
    fi
    gitlore_drop_merge_preparation "$store"
    msg="gitlore: a merge preparation in $abs was interrupted before its merge ran, so nothing of it survived; HEAD is back on the pending commit $(git -C "$store" rev-parse --short "$pending") and the merge is prepared again if the divergence is still there."
    gitlore_say_for_agent_or_user "$msg" "$msg" >&2
    return 0
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
    gitlore_adopt_recovered_merge "$store" "$abs"
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
  gitlore_adopt_recovered_merge "$store" "$abs"
  msg="gitlore: the merge in $abs landed as $landed before a checkout or reset moved HEAD off it; HEAD is restored to it and the leftover merge state cleared, so none of that merge is lost."
  gitlore_say_for_agent_or_user "$msg" "$msg" >&2
  return 0
}

# Adopt the merge gitlore_recover_landed_merge just restored: project the tier's
# carrier UP into the root index, then stage the pair. A tier commit that landed
# outside /gitlore:merge's continuation skips the tail every advancing path
# shares (D43's staging-as-last-act), so the recovery owes it.
#
# The up projection is not bookkeeping alongside the staging, it is what makes
# the staging safe. Staging alone puts the enclosing store's index back in
# agreement with the tier's HEAD — exactly the disagreement
# gitlore_compose_check_pins refuses on — so the next pass composes, and its
# down projection writes root's older text over a carrier holding the merged-in
# facts root has never seen. The refusal exists to stop that, and staging alone
# turns it into a silent overwrite. gitlore_adopt_tier_into_root is the
# precedent and the only shape in which a tier ahead of its pin may be adopted:
# compose up first, then stage MEMORY.md and the tier together.
#
# So a failed up projection stages nothing. Leaving the gitlink where it is
# keeps the pin guard's refusal, which is the right answer for a store whose
# root index could not take the carrier.
#
# Fires only when the recovered store is a tier. `--show-superproject-working-tree`
# alone does not decide that: the memory root is itself a real submodule of the
# user's project, so it answers non-empty for the memory root too. Two more
# clauses narrow it:
#   1. the superproject carries a root MEMORY.md, the same test every other
#      memory-store predicate makes — unpinned by any case and kept as defence
#      in depth: the state it would exclude, a store enclosed by a non-memory
#      project, is unreachable through gitlore_guard_stale_merge_state's
#      callers, which walk gitlore_memory_stores alone;
#   2. the store's path relative to the superproject is NOT the superproject's
#      own submodule.${GITLORE_SUBMODULE_NAME}.path — this is the clause that
#      does the work, keeping the memory root's own recovery from writing and
#      staging in the user's project index outside any approval gate. Read via
#      `git config --file`, not gitlore_memory_path, which reads the CURRENT
#      DIRECTORY's .gitmodules while this guard runs from an arbitrary cwd.
# No membership test against gitlore_tier_paths "$super": a store has a
# superproject only where that repo registers it, so the test would restate what
# --show-superproject-working-tree already settled.
#
# Short-circuits when the enclosing index already records the tier's current
# HEAD — a continuation killed right after its own bookkeeping commit, then
# re-run.
#
# Best-effort, like gitlore_adopt_tier_into_root's own staging: a failure here
# must not turn a landed recovery into a failed one. The named pair only, never
# `add -A` — an over-broad stage would sweep unapproved worktree edits into the
# enclosing store's index for the next approved commit to carry. And no
# bookkeeping commit: this runs inside a gate, where a staged pair riding the
# next approved memory commit is D43's own degraded case rather than a fault.
# Args: $1 = recovered store worktree, $2 = its abs path (show-toplevel).
gitlore_adopt_recovered_merge() {
  local store="$1" abs="$2"
  local super rel own_path composed rc=0
  super=$(git -C "$store" rev-parse --show-superproject-working-tree) || super=""
  [ -n "$super" ] || return 0
  [ -f "$super/MEMORY.md" ] || return 0
  rel="${abs#"$super"/}"
  own_path=$(git config --file "$super/.gitmodules" \
    "submodule.${GITLORE_SUBMODULE_NAME}.path") || own_path=""
  [ "$rel" != "$own_path" ] || return 0

  # Already adopted: the enclosing index's gitlink already names the tier's
  # current HEAD, which means a prior pass (or this same one, before a kill)
  # already composed the carrier up and staged the pair. Composing again would
  # project the carrier's text over any root-index edit made to that tier's
  # lines since — the pair was already adopted, and a second up projection is
  # not a repeat of that adoption, it is an overwrite of what happened after.
  local tier_head pinned
  tier_head=$(git -C "$store" rev-parse HEAD) || tier_head=""
  pinned=$(git -C "$super" rev-parse -q --verify ":$rel") || pinned=""
  [ -n "$tier_head" ] && [ "$tier_head" = "$pinned" ] && return 0

  composed=$(gitlore_compose_up "$super" "$rel") || rc=$?
  if [ "$rc" -ne 0 ]; then
    printf 'gitlore: the root index could not take %s'\''s lines, so the merge was left unrecorded rather than composed over — the next gate refuses the tier instead:\n' "$rel" >&2
    printf '%s\n' "$composed" | sed 's/^/gitlore:   /' >&2
    return 0
  fi
  if [ -n "$composed" ]; then
    printf '%s\n' "$composed" | sed 's/^/gitlore: /' >&2
  fi
  # shellcheck disable=SC2016  # backticks are markdown for the reader, not a command sub
  gitlore_git -C "$super" add -- MEMORY.md "$rel" \
    || printf 'gitlore: %s could not be staged in %s. Run `git -C "%s" add -- MEMORY.md "%s"` before the next session, or the pointer will be reset to its previous commit and the root index will be left describing facts the tier no longer holds.\n' \
      "$rel" "$super" "$super" "$rel" >&2
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
  # The staged merge may belong to a preparation interrupted before its briefing
  # was written; with the pointers back, the store holds everything that
  # briefing is computed from.
  if ! gitlore_complete_merge_state "$store"; then
    msg="gitlore: the merge pointers were restored in $abs, but its merge state file could not be completed, so no sub-agent can be briefed on it. Read $statefile, then inspect the store."
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
