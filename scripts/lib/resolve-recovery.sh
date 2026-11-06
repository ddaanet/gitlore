#!/usr/bin/env bash
# Classify a stale merge-state file whose MERGE_HEAD is gone, from what a lost
# MERGE_HEAD or a checkout-cleared merge left behind: landed, staged-but-unpointed,
# or dead. The repair for each outcome is in resolve-recovery-repair.sh. Also the
# deliberate abort of a prepared merge (`resolve.sh abort-merge`), which drops a
# preparation the same way a dead merge's is dropped.
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

# `resolve.sh abort-merge`: put store $1 back where a prepared merge found it.
# Reads the pending commit first, since dropping the preparation deletes the
# pin that names it; `git merge --abort` runs only while a MERGE_HEAD exists, so
# a preparation interrupted after its checkout aborts the same way. The checkout
# is forced: a checkout that unlinked MERGE_HEAD left the index as the merge
# staged it, and with it whatever a merger staged or edited, which a plain
# checkout would carry onto the pending commit as if the user had made it.
# Dropped either way, as `merge --abort` drops it. An untracked file a merger
# wrote is named and left in place: it is the merger's work, and nothing here
# can tell it from the user's. Returns 1 after saying why on stderr when the
# store was not restored.
# Args: $1 = store worktree path.
gitlore_abort_prepared_merge() {
  local store="$1" statefile pending err untracked abs
  statefile=$(gitlore_merge_state_file "$store")
  abs=$(git -C "$store" rev-parse --show-toplevel) || abs="$store"
  if [ ! -f "$statefile" ]; then
    echo "gitlore: $abs holds no merge gitlore prepared; nothing was aborted." >&2
    return 1
  fi
  pending=$(gitlore_pending_commit "$store" "$statefile")
  if [ -z "$pending" ]; then
    echo "gitlore: the prepared merge in $abs names no pending commit still in the store, so HEAD has nowhere to go back to; nothing was aborted. Read $statefile." >&2
    return 1
  fi
  untracked=$(git -c core.quotePath=false -C "$store" ls-files --others --exclude-standard)
  if git -C "$store" rev-parse -q --verify MERGE_HEAD >/dev/null; then
    if ! err=$(gitlore_git -C "$store" merge --abort 2>&1); then
      printf 'gitlore: git merge --abort failed in %s, so the merge stays prepared. git said:\n%s\n' "$abs" "$err" >&2
      return 1
    fi
  fi
  if ! err=$(gitlore_git -C "$store" checkout -q -f --detach "$pending" 2>&1); then
    printf 'gitlore: the merge in %s is aborted, but HEAD could not be put back on its pending commit %s. git said:\n%s\n' "$abs" "$pending" "$err" >&2
    return 1
  fi
  gitlore_drop_merge_preparation "$store"
  echo "gitlore: the prepared merge in $abs is aborted; HEAD is back on $(git -C "$store" rev-parse --short "$pending")." >&2
  if [ -n "$untracked" ]; then
    printf 'gitlore: these untracked files were left in place; delete any the merger wrote:\n%s\n' \
      "$(printf '%s\n' "$untracked" | sed 's/^/  /')" >&2
  fi
}
