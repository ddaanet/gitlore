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
      # A preparation interrupted between its merge and its briefing left a
      # marker; the merge itself is staged in the store, so the briefing is
      # written now and the merge continues like any other.
      if ! gitlore_complete_merge_state "$mempath"; then
        gitlore_say_for_agent_or_user \
          "gitlore: $mempath holds a prepared merge whose state file could not be completed, so no sub-agent can be briefed on it. Read $statefile, then inspect the store." \
          "gitlore: $mempath holds a prepared merge whose state file could not be completed, so no sub-agent can be briefed on it. Read $statefile, then inspect the store." >&2
        return 1
      fi
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
      # gitlore records its own preparations before they start, so this is a
      # merge something else began in the store — a hand-run `git merge`, or an
      # agent asked to merge by hand. Reported rather than touched: nothing here
      # says what it was for, and it may hold work in progress.
      local orph_msg
      orph_msg="gitlore: $mempath holds a merge gitlore did not prepare (MERGE_HEAD $mh, no merge state file), so nothing was changed. Finish it or undo it in the store, then re-run the operation:
gitlore:   git -C \"$mempath\" status --short
gitlore:   git -C \"$mempath\" merge --abort"
      gitlore_say_for_agent_or_user "$orph_msg" "$orph_msg" >&2
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
gitlore: request for this dispatch, so make it now without asking first. Review
gitlore: the synthesis it returns yourself — both sides of this merge already
gitlore: passed an approval gate, so do not prompt the user (D49).
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
  local prep base pending statefile pending_sha
  # The marker goes down BEFORE the preparation, so every window inside it
  # leaves a state file for the next gate to classify (D7): a merge that staged
  # is completed and continued, one that never ran is discarded and re-prepared.
  # Written even though the preparation may refuse outright — it is removed on
  # that path below, and the alternative is the window this exists to close.
  pending_sha=$(git -C "$mempath" rev-parse -q --verify "$pending_ref^{commit}") || pending_sha="$pending_ref"
  if ! gitlore_write_merge_marker "$mempath" "$flavor" "$pending_sha" "$authority" "continue-after-merge"; then
    gitlore_say_for_agent_or_user \
      "gitlore: no merge was started in $mempath because its merge state file could not be written, so nothing can record one. Inspect the memory worktree." \
      "gitlore: no merge was started in $mempath because its merge state file could not be written, so nothing can record one. Inspect the memory worktree." >&2
    return 1
  fi
  if ! prep=$(gitlore_prepare_merge "$mempath" "$authority" "$pending_ref"); then
    # No merge was started, so the marker describes nothing. Dropped with the
    # pin, which the preparation may have set before it failed.
    gitlore_drop_merge_preparation "$mempath"
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
#
# One direction IS recoverable, and is repaired before this runs rather than
# here: the publish preflights call gitlore_repair_stranded_live first, so a
# `live` merely left behind a HEAD containing it is already advanced by the time
# this reads the refs. Its arm below stays because the other call sites reach
# this only after their own `push . HEAD:live` was refused — there, `live`
# behind HEAD means the ref moved under the push, which is a race and not the
# lag the repair recognizes.
#
# The remedy differs by STORE KIND, because the authoritative ref does. For the
# memory root, `live` is what SessionStart checks out and the parent's gitlink is
# allowed to lag (D46), so a HEAD behind it is put back with a checkout. A tier
# is pinned at the gitlink the memory store records (D43): the same checkout
# takes it OFF that pin, and the next composition refuses — the two gates then
# assert different invariants about one ref and obeying this one breaks the
# store. A tier goes to the take, which moves HEAD, the root index and the
# recorded pointer together.
# Args: $1 = store, $2 = label, $3 = tier name ("" when the store is the memory
# root). Returns 1 after emitting when they disagree.
gitlore_check_head_live_agree() {
  local store="$1" label="$2" tier="${3-}" head live abs remedy
  head=$(git -C "$store" rev-parse -q --verify HEAD) || return 0
  # No local `live` yet (a tier never fetched) — nothing to disagree with.
  live=$(git -C "$store" rev-parse -q --verify live) || return 0
  [ "$head" != "$live" ] || return 0
  # `--show-toplevel` rather than a subshell `cd`: the remedy below is printed
  # for a human to paste, so the path has to be absolute, and CDPATH turns
  # `$(cd … && pwd)` into a path with a directory listing glued to the front.
  abs=$(git -C "$store" rev-parse --show-toplevel) || abs="$store"
  if git -C "$store" merge-base --is-ancestor "$head" "$live"; then
    if [ -n "$tier" ]; then
      remedy="'live' holds commits the memory store never recorded; run /gitlore:merge to adopt them. Do not check the tier out at 'live' — that moves it off the commit the store records, and composition refuses there."
    else
      remedy="Put HEAD back on 'live': git -C \"$abs\" checkout --detach live"
    fi
  elif git -C "$store" merge-base --is-ancestor "$live" "$head"; then
    remedy="Advance 'live' to HEAD: git -C \"$abs\" push . HEAD:live"
  else
    remedy="HEAD and 'live' have each moved since they last agreed; run /gitlore:resolve to reconcile them."
  fi
  # `$label — …` rather than `$label's …`: a tier label already carries quotes
  # around its name, and an apostrophe-s on top of them renders `'ddaanet''s`.
  gitlore_say_for_agent_or_user \
    "gitlore: $label — HEAD is not at its local 'live' (HEAD $(git -C "$store" rev-parse --short "$head"), live $(git -C "$store" rev-parse --short "$live")), so nothing was published. $remedy" \
    "gitlore: $label — HEAD is not at its local 'live' (HEAD $(git -C "$store" rev-parse --short "$head"), live $(git -C "$store" rev-parse --short "$live")), so nothing was published. $remedy" >&2
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
  local mempath="$1" msgfile="$2" tier tierpath push_err landing pre
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
    # Checked explicitly: this function is reached from the pre-commit hook's
    # `gitlore_sync_memory_to_live "$mempath" || exit $?`, which suspends
    # errexit transitively (SC2310) for everything called from here — an
    # unchecked failure would fall through to the push below, which is a no-op
    # success because HEAD never moved.
    # Every failure below that prepares no merge restamps $msgfile, for the
    # reason gitlore_sync_memory_to_live gives above its own tier loop.
    gitlore_git -C "$tierpath" add -A || { touch "$msgfile"; return 1; }
    # Written before the commit, so no interruption can leave the commit without
    # it, and dropped when the commit fails, so it never vouches for a commit
    # made later by other means: gitlore_stage_landed_tiers reads it on the
    # retry. A tier with no commit yet has no pin to compare, so records nothing.
    landing=$(gitlore_tier_landing_file "$tierpath") || { touch "$msgfile"; return 1; }
    if pre=$(git -C "$tierpath" rev-parse -q --verify HEAD); then
      printf '%s\n' "$pre" > "$landing" || { touch "$msgfile"; return 1; }
    fi
    # Blessed commit: the same sentinel that admits a memory commit past the FR11
    # gate, which emit-memory-gate.sh installs in each tier too.
    if ! GITLORE_MEMORY_COMMIT=1 gitlore_git -C "$tierpath" commit -q -F "$msgfile"; then
      rm -f "$landing"
      touch "$msgfile"
      return 1
    fi
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
            touch "$msgfile"
            return 1
            ;;
        esac
        # Same two ancestries behind the one reason: `live` already containing
        # HEAD is drift, not divergence, and has no merge to prepare.
        if [ "$(gitlore_classify_refusal "$tierpath" HEAD live)" = "diverged" ]; then
          # Diverged from its own local `live` — the same gate memory has here,
          # and the same resolution. The merge lands in the tier's gitdir.
          gitlore_yield_merge "$tierpath" live head-vs-live HEAD || return 1
          return 1
        fi
        if gitlore_check_head_live_agree "$tierpath" "tier '$tier'" "$tier"; then
          # Refused with the two refs in agreement and no divergence: neither
          # diagnosis applies, so git's own words are all there is to go on.
          gitlore_say_for_agent_or_user \
            "gitlore: tier '$tier' was committed but its local 'live' could not be advanced, though HEAD and 'live' agree and neither has diverged. git said:
$push_err" \
            "gitlore: tier '$tier' was committed but its local 'live' could not be advanced. git said:
$push_err" >&2
        fi
        # No merge was prepared on this arm, so it restamps.
        touch "$msgfile"
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
      # A tier holding a prepared merge makes memory dirty by construction — its
      # gitlink has moved — so that merge is answered first: asking for a
      # summary would put a merge in front of the user, which both of its sides
      # already approved (D49), and the retry would stop on the directive anyway.
      # The loop below still guards the fresh path; this one only decides which
      # refusal speaks.
      local stale_tier
      while IFS= read -r stale_tier; do
        [ -n "$stale_tier" ] || continue
        [ -e "$mempath/$stale_tier/.git" ] || continue
        gitlore_guard_stale_merge_state "$mempath/$stale_tier" || return 1
      done < <(gitlore_tier_paths "$mempath")
      # The clause is a multi-line block, so it goes last rather than mid-sentence.
      gitlore_say_for_agent_or_user \
        "$(printf '%s\n\n%s\n' \
          "gitlore: memory is dirty and has no approved commit summary. Prepare a summary and present it to the user as a markdown blockquote (\`> …\`), not a code fence, for confirmation; treat only a clear, un-negated affirmative as approval (a hedge, a question, or any negation is a rejection). Only once approved, write it to $msgfile, then retry." \
          "$(gitlore_memory_approval_clause)")" \
        "gitlore: memory has uncommitted changes with no approved commit summary. Open this project in Claude Code and ask it to commit memory, then retry." >&2
      return 1
    fi
    # Every tier gets memory's own stale-merge precheck here, ahead of the first
    # write into it. It runs over every mounted tier rather than the active
    # subset the compose below touches, because what it orders against is
    # gitlore_sync_tiers_to_live, which commits inside a mounted-but-unlisted
    # tier too — otherwise a run commits tier A and then aborts on tier B's
    # stale merge, under a message stating nothing was changed. The
    # guard inside that loop stays: it is that function's own precondition, and
    # a state this call passes is clean by the time it runs, so the second call
    # costs a rev-parse and a stat.
    #
    #
    # From here on a failure restamps $msgfile before returning, unless it
    # prepared a merge. What this run writes into the store — a recovered
    # merge's up projection in this loop, a composed carrier below — is a
    # projection of index lines the summary already approved, never new content,
    # yet it is newer than $msgfile, so gitlore_commit_msg_freshness would read
    # the approval stale on the retry and refuse it. Only commit-memory.sh
    # rewrites the file; the pre-commit path retries on it as it stands. A merge
    # preparation is the exception: it checks merged content out into the
    # worktree, which the summary never covered, so a stale approval is the
    # right answer after it — the merge yields inside gitlore_sync_tiers_to_live
    # return without one. The stale-merge guard in this loop returns without
    # one on every arm, because it does not tell its caller which arm failed,
    # and several prepare nothing: a merge gitlore did not prepare, a merge
    # state nothing can classify, a recovery whose checkout failed. When an
    # earlier tier's recovery has already composed up, the retry after one of
    # those reads the approval stale. Reaching here means $fresh was "yes", so
    # the file exists and a restamp cannot create an empty one, and the memory
    # commit that consumes it is the last step that can fail.
    local tier
    while IFS= read -r tier; do
      [ -n "$tier" ] || continue
      # `git -C` into an unmaterialized submodule walks up to the enclosing
      # repo, which would answer for memory's own state under the tier's name.
      [ -e "$mempath/$tier/.git" ] || continue
      gitlore_guard_stale_merge_state "$mempath/$tier" || return 1
    done < <(gitlore_tier_paths "$mempath")
    # A previous run that committed inside a tier and stopped before memory's
    # `add -A` recorded it left that tier ahead of its pin — the shape the pin
    # guard below refuses — so it is adopted first.
    gitlore_stage_landed_tiers "$mempath" || { touch "$msgfile"; return 1; }
    # A tier off its pin refuses composition itself (D31, D36), but leaving that
    # refusal to gitlore_compose's own rc-1 arm would let this function's `add -A`
    # below stage the moved gitlink anyway — adopting the move silently in the
    # very commit that reported it as a problem. Checked here, ahead of compose,
    # so an off-pin tier aborts instead.
    # The declaration stays on its own line: folded into `local pin_problems=$(…)`
    # the status read is `local`'s, always 0, and the refusal is swallowed.
    local pin_problems
    if ! pin_problems=$(gitlore_compose_check_pins "$mempath"); then
      local pin_header="gitlore: a tier was moved off the commit the memory store records for it, so the commit was aborted rather than adopt the move:
$pin_problems"
      # The agent arm names no remedy of its own. Every branch of
      # gitlore_compose_check_pins already printed the one its cause takes —
      # /gitlore:resolve mid-merge, the return-to-the-pin checkout sideways or
      # diverged, /gitlore:merge for a tier ahead of its pin, from the pin the
      # guard put it back on or once its commits reach its local `live` — and
      # $pin_problems can carry several tiers with different causes in one
      # abort, so no single remedy named here is right for all of them, and
      # choosing per tier would re-derive a cause that function already
      # decided.
      gitlore_say_for_agent_or_user \
        "$pin_header
gitlore: composing would have overwritten what that tier holds, and committing would have adopted the move silently. Follow the remedy on each line above, then retry the commit. Every remedy writes into the memory store, so the summary has to be approved again before the retry." \
        "$pin_header
gitlore: composing would have overwritten what that tier holds. Open this project in Claude Code and ask it to repair the memory store, then retry." >&2
      touch "$msgfile"
      return 1
    fi
    # Compose before the tier commit below: composition writes carrier files
    # inside the tiers, so it must land before gitlore_sync_tiers_to_live moves
    # their gitlinks, or the gitlink pins the pre-compose content — the same
    # one-behind lag the tier-first ordering already exists to prevent.
    local compose_result compose_rc=0
    compose_result=$(gitlore_compose "$mempath") || compose_rc=$?
    case "$compose_rc" in
      0) ;;
      1)
        # A refusal writes nothing (D31, D36): projecting root's older text over
        # an unadopted carrier would destroy approved upstream facts. The commit
        # aborts only on a problem it would publish: a rule 1, 4 or 6 problem —
        # the kinds that name their index file — in root's MEMORY.md or a tier
        # carrier, when that file has uncommitted changes. The same problems in
        # a file with none, a tier dirty only outside its carrier included, and
        # rules 2 and 3, which name no index file, report and let the commit go
        # ahead. The pin guard above aborts on any gitlore_compose_check_pins
        # refusal, so rc 1 reaches here only from gitlore_compose_check: no
        # rule 7 line needs attributing, and the advisory remedy has no pin
        # figure to call stale. The header is gitlore_compose_and_report's own,
        # held in one variable so the arms cannot drift apart.
        local refusal="gitlore: tier composition refused — the memory indexes were left untouched:
$compose_result"
        # A status read that fails aborts rather than reading as a clean index:
        # the pre-commit hook's `|| exit $?` suspends errexit here, so an
        # unchecked failure would publish the problem. Every changed file with
        # a problem is collected, so one abort names all of them.
        local abort_files="" index_status
        if printf '%s\n' "$compose_result" \
          | gitlore_compose_problems_in "$mempath/MEMORY.md" >/dev/null; then
          index_status=$(git -C "$mempath" status --porcelain -- MEMORY.md) \
            || { gitlore_say_unreadable_index_status "$mempath/MEMORY.md" "$refusal"
                 touch "$msgfile"; return 1; }
          [ -z "$index_status" ] || abort_files="$mempath/MEMORY.md"
        fi
        while IFS= read -r tier; do
          [ -n "$tier" ] || continue
          [ -e "$mempath/$tier/.git" ] || continue
          printf '%s\n' "$compose_result" \
            | gitlore_compose_problems_in "$mempath/$tier/MEMORY.md" >/dev/null \
            || continue
          index_status=$(git -C "$mempath/$tier" status --porcelain -- MEMORY.md) \
            || { gitlore_say_unreadable_index_status "$mempath/$tier/MEMORY.md" "$refusal"
                 touch "$msgfile"; return 1; }
          [ -z "$index_status" ] \
            || abort_files="${abort_files:+$abort_files
}$mempath/$tier/MEMORY.md"
        done < <(gitlore_tier_paths "$mempath")
        if [ -n "$abort_files" ]; then
          gitlore_say_for_agent_or_user \
            "$refusal
gitlore: the commit was aborted because a problem is in an index file this commit changes — committing would publish it. The changed index files with problems:
$abort_files
Fix them by editing the lines above that name those files, then retry; the summary needs approval again." \
            "$refusal
gitlore: the commit was aborted because a problem is in an index file this commit changes. Open this project in Claude Code and ask it to repair the memory store, then retry." >&2
          touch "$msgfile"
          return 1
        fi
        gitlore_say_for_agent_or_user \
          "$refusal
gitlore: the commit went ahead with the memory indexes as they stand. Fix the problems above by hand — composition runs again at the next memory commit. This commit also stages each tier at the commit its worktree is on now." \
          "$refusal
gitlore: the commit went ahead with the memory indexes as they stand. Open this project in Claude Code and ask it to repair the memory store." >&2
        ;;
      2)
        # A write failed partway, leaving a half-written carrier — that must not
        # be committed, so this aborts before gitlore_sync_tiers_to_live and
        # before anything consumes $msgfile.
        local partial="gitlore: tier composition could not write an index — the memory indexes are only partly composed:
$compose_result"
        gitlore_say_for_agent_or_user \
          "$partial
gitlore: the commit was aborted so the half-written carrier is not committed. Investigate that path (permissions, disk space, a read-only worktree), then retry the commit — the approved summary is still in place and the commit path composes again." \
          "$partial
gitlore: the commit was aborted so the half-written carrier is not committed. Open this project in Claude Code and ask it to repair the memory store, then retry." >&2
        # The restamp above the tier loop names why.
        touch "$msgfile"
        return 1
        ;;
      *)
        # Unreachable from gitlore_compose, which returns 0, 1 or 2 and nothing
        # else. Kept because a status this call site does not recognise says
        # nothing about what was written, and silently proceeding on a non-zero
        # status is the failure the case exists to remove — so an unknown one is
        # treated as the partial write it might be.
        local unknown="gitlore: tier composition exited with an unrecognised status ($compose_rc), so what it wrote is unknown:
$compose_result"
        gitlore_say_for_agent_or_user \
          "$unknown
gitlore: the commit was aborted rather than commit a memory store in an unknown state. Establish what gitlore_compose did, then retry the commit — the approved summary is still in place." \
          "$unknown
gitlore: the commit was aborted rather than commit a memory store in an unknown state. Open this project in Claude Code and ask it to repair the memory store, then retry." >&2
        # The restamp above the tier loop names why.
        touch "$msgfile"
        return 1
        ;;
    esac
    # Tiers first: a tier commit moves its gitlink, and the `add -A` below is what
    # records that move in the memory commit. Reversing the order would pin the
    # pre-commit tier SHA — the same one-behind lag the parent's gitlink staging
    # exists to prevent.
    # Restamps its own non-merge failures (see above the tier loop).
    gitlore_sync_tiers_to_live "$mempath" "$msgfile" || return 1
    # Checked explicitly, for the same reason as the tier loop above: called
    # via `|| exit $?` at the pre-commit call site, errexit is off here, and an
    # unchecked failure would delete the approved $msgfile below and let the
    # no-op push report success.
    gitlore_git -C "$mempath" add -A || { touch "$msgfile"; return 1; }
    # Every tier gitlink is staged now, so no landing record is left with a
    # commit to vouch for.
    while IFS= read -r tier; do
      [ -n "$tier" ] || continue
      [ -e "$mempath/$tier/.git" ] || continue
      rm -f "$(gitlore_tier_landing_file "$mempath/$tier")"
    done < <(gitlore_tier_paths "$mempath")
    # Blessed commit: carry the sentinel so the submodule gate (memory-pre-commit)
    # admits it. A naked commit never sets this and is blocked (FR11/D12).
    GITLORE_MEMORY_COMMIT=1 gitlore_git -C "$mempath" commit -q -F "$msgfile" \
      || { touch "$msgfile"; return 1; }
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

# Report the abort an unreadable index status forces, on both channels. That
# read decides whether a composition problem is in a file this commit changes,
# i.e. whether committing would publish it, so a failure there leaves the
# question open and the commit stops on it — with the compose refusal that sent
# the run to the read, which is the list a retry has to fix. The approval is
# restamped by the caller, as after every failure that prepared no merge, so the
# retry reuses the summary as it stands.
# Args: $1 = the index file whose status could not be read, $2 = that refusal.
gitlore_say_unreadable_index_status() {
  local file="$1" refusal="$2"
  gitlore_say_for_agent_or_user \
    "$refusal
gitlore: the commit was aborted because git could not read the status of $file, so whether this commit changes that index is unknown. Establish why \`git status\` fails in the store holding it, then retry the commit — the approved summary is still in place." \
    "$refusal
gitlore: the commit was aborted because git could not read the status of $file. Open this project in Claude Code and ask it to repair the memory store, then retry the commit." >&2
}

# Stage the gitlink of each tier whose HEAD is the commit gitlore_sync_tiers_to_live
# made and a stopped run never recorded: memory's `add -A` failed after it (a
# transient index.lock) or the run died between the two. That tier sits ahead of
# its pin, the shape gitlore_compose_check_pins refuses for a tier moved behind
# gitlore's back, so without this the retry memory-commit-batch.sh promises is
# refused for good. Staging it overwrites nothing: the commit path composed that
# carrier from the root index just before committing it.
#
# Recognised by the landing record written just before that commit — HEAD's
# parent must be the commit the record names, and memory's index must still pin
# it. Not by the commit's message: a session that edits memory before the retry
# lands approves a new summary, and the old commit no longer matches it.
# Residual: a run killed after writing the record and before its commit failed
# leaves the record behind, and a commit later made on that same pin by other
# means would be adopted.
# Returns 1, after git's own message, when a gitlink cannot be staged.
# Args: $1 = memory worktree path.
gitlore_stage_landed_tiers() {
  local mempath="$1" tier tierpath landing recorded pinned parent
  while IFS= read -r tier; do
    [ -n "$tier" ] || continue
    tierpath="$mempath/$tier"
    # `git -C` into an unmaterialized submodule walks up to the enclosing repo.
    [ -e "$tierpath/.git" ] || continue
    landing=$(gitlore_tier_landing_file "$tierpath") || continue
    [ -f "$landing" ] || continue
    recorded=""
    IFS= read -r recorded < "$landing" || [ -n "$recorded" ] || continue
    # `-q --verify` is silent on the expected misses: no gitlink in the index
    # (mid-mount), and a HEAD that is a root commit.
    pinned=$(git -C "$mempath" rev-parse -q --verify ":$tier") || continue
    parent=$(git -C "$tierpath" rev-parse -q --verify "HEAD^") || continue
    [ "$recorded" = "$pinned" ] || continue
    [ "$parent" = "$recorded" ] || continue
    gitlore_git -C "$mempath" add -- "$tier" || return 1
    rm -f "$landing"
  done < <(gitlore_tier_paths "$mempath")
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
  local mempath="$1" remote_url tier tierpath tier_err push_err origin_live

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
    # other than the commit its pointer names. One of the two disagreements is
    # not a decision — a `live` behind a HEAD containing it is repaired here
    # rather than reported, and the check then sees two refs that agree.
    gitlore_repair_stranded_live "$tierpath" "tier '$tier'" || return 1
    # The other direction is not a repair but a take: a `live` ahead of a HEAD
    # sitting at the pin holds approved commits the memory store never recorded,
    # and moving HEAD onto it alone would take the tier off that pin (D43), which
    # is what the next composition refuses. The whole take pass, not this tier
    # alone, and for the reason the behind-tier branch below gives: it runs
    # root-first, and a tier take writes a bookkeeping commit that would meet an
    # equally-behind root's upstream one as a divergence. No `continue` after it
    # — unlike a take from the remote, what was adopted here has never been
    # published, so this tier's push is exactly what has to happen next.
    #
    # This take and the behind arm's run marked as inside a push, so a repair
    # names this push as what publishes it rather than /gitlore:push — also
    # when the repair lands on a different tier than this iteration's: a later
    # tier goes out with its own iteration's push, and one whose iteration
    # already finished with the post-loop pass below.
    if gitlore_live_ahead_of_head "$tierpath"; then
      GITLORE_TAKE_IN_PUSH=1 gitlore_merge_stores "$mempath" || return 1
    fi
    gitlore_check_head_live_agree "$tierpath" "tier '$tier'" "$tier" || return 1
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
              # Nothing of ours to publish, and the remote holds facts this repo
              # does not. A push is attempt → take → attempt again (D49), so the
              # take happens here rather than being handed back as an errand:
              # the fast-forward is exactly what /gitlore:merge would do, and the
              # commits it takes are already on this remote, so the lockstep this
              # loop guarantees is untouched. A take that cannot fast-forward
              # yields a prepared merge and returns non-zero, as everywhere else.
              #
              # The whole take pass, not this tier alone: it runs root-first, and
              # a tier take writes a bookkeeping commit that would meet an
              # equally-behind root's upstream one as a divergence.
              GITLORE_TAKE_IN_PUSH=1 gitlore_merge_stores "$mempath" || return 1
              # The take can repair a defective arrival, committing on top of
              # what it fetched, and memory's push below records that commit —
              # so a `live` the remote does not already hold goes out now, for
              # the lockstep above (D17), and before a later tier's failure can
              # return 1 from the loop. A repair the same take made to a tier
              # whose iteration already finished is left to the post-loop pass
              # below; one to a later tier goes out with that tier's own push.
              if ! git -C "$tierpath" merge-base --is-ancestor live origin/live; then
                if ! tier_err=$(gitlore_git -C "$tierpath" push -q origin live 2>&1); then
                  gitlore_report_tier_push_failure "$tier" "$tier_err"
                  return 1
                fi
              fi
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
              gitlore_report_tier_push_failure "$tier" "$tier_err"
              return 1
              ;;
          esac
          ;;
        *)
          gitlore_report_tier_push_failure "$tier" "$tier_err"
          ;;
      esac
      return 1
    fi
  done < <(gitlore_tier_paths "$mempath")

  # A take run mid-loop, while a different tier's own iteration was being
  # processed, can fetch and repair a tier whose iteration already finished —
  # committing on top of what it fetched, entirely in that tier's local
  # `live`, with no push of its own to send it out. One more pass over every
  # tier, before memory's remote is even considered (a memory kept local still
  # publishes every tier), catches anything left behind this way. The loop
  # above's own pushes already moved each tier's `origin/live`, so a tier
  # already out is not pushed again here.
  while IFS= read -r tier; do
    [ -n "$tier" ] || continue
    tierpath="$mempath/$tier"
    [ -e "$tierpath/.git" ] || continue
    git -C "$tierpath" rev-parse -q --verify live >/dev/null || continue
    # No local `origin/live` to compare against is the same as `live` not
    # being its ancestor: push rather than assume nothing changed.
    origin_live=$(git -C "$tierpath" rev-parse -q --verify refs/remotes/origin/live) || origin_live=""
    if [ -z "$origin_live" ] || ! git -C "$tierpath" merge-base --is-ancestor live "$origin_live"; then
      if ! tier_err=$(gitlore_git -C "$tierpath" push -q origin live 2>&1); then
        gitlore_report_tier_push_failure "$tier" "$tier_err"
        return 1
      fi
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

  # The same pre-publish invariant the tiers get, repaired the same way where it
  # is unambiguous: `live` is what goes out, HEAD is what the parent's gitlink
  # records.
  gitlore_repair_stranded_live "$mempath" "memory" || return 1
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
      # Every tier is published and memory has nothing of its own to send, while
      # the remote holds facts this clone lacks. Take them here rather than
      # reporting an errand (D49): the same fast-forward /gitlore:merge performs,
      # publishing nothing that was not already published. Every tier is already
      # reconciled by the loop above, so the root is all that is left to take.
      gitlore_merge_one_store "$mempath" "$mempath" "" || return 1
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

# Words a failed tier push by git's parenthesized reason, the discriminator
# gitlore_push_stores applies to its own pushes. A refusal shaped like
# divergence (fetch first / non-fast-forward) reaches here only once ancestry
# has left nothing to merge, so it means the remote moved during the push, or
# the fetch before it failed; anything else is not divergence.
# Args: $1 = tier name, $2 = git's stderr from the failed push.
gitlore_report_tier_push_failure() {
  local tier="$1" tier_err="$2"
  case "$tier_err" in
    *"(fetch first)"*|*"(non-fast-forward)"*)
      gitlore_say_for_agent_or_user \
        "gitlore: pushing tier '$tier' was refused as a non-fast-forward, but its local 'live' already contains the remote's. The remote moved during the push, or the fetch before it failed. git said:
$tier_err" \
        "gitlore: pushing tier '$tier' was refused as a non-fast-forward, but its local 'live' already contains the remote's. The remote moved during the push, or the fetch before it failed. git said:
$tier_err" >&2
      ;;
    *)
      gitlore_say_for_agent_or_user \
        "gitlore: pushing tier '$tier' failed, and not because of divergence. git said:
$tier_err" \
        "gitlore: pushing tier '$tier' failed, and not because of divergence. git said:
$tier_err" >&2
      ;;
  esac
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

  # Root FIRST, the mirror of the publish order (D49). Taking goes top-down
  # because the root commit arriving from upstream already records the tier
  # commits it names, all of them on the tier's own remote: taking it costs
  # nothing and leaves each tier merely behind. Tiers-first inverts that — the
  # tier take writes a bookkeeping commit of its own, which meets the upstream
  # root's equivalent commit as a DIVERGENCE and spends a synthesis on two
  # sides that recorded the same fast-forward. Publishing keeps the opposite
  # order for the opposite reason: a pointer must never go out ahead of what it
  # points at.
  gitlore_merge_one_store "$mempath" "$mempath" "" || return 1

  while IFS= read -r tier; do
    [ -n "$tier" ] || continue
    tierpath="$mempath/$tier"
    # `git -C` into an unchecked-out submodule walks up to the enclosing repo.
    [ -e "$tierpath/.git" ] || continue
    gitlore_guard_stale_merge_state "$tierpath" || return 1
    gitlore_merge_one_store "$mempath" "$tierpath" "$tier" || return 1
  done < <(gitlore_tier_paths "$mempath")

  return 0
}

# One store's reconcile. Args: $1 = memory worktree, $2 = store worktree,
# $3 = tier name ("" when the store IS the memory root, which adopts nothing —
# its own MEMORY.md moves with the fast-forward).
gitlore_merge_one_store() {
  local mempath="$1" store="$2" tier="$3"
  local label remote_url fetched=0 fetch_err="" remote="" live head adopt_rc=0
  local root_dirty_before

  if [ -n "$tier" ]; then label="tier '$tier'"; else label="memory"; fi

  remote_url=$(git -C "$store" config --get remote.origin.url || true)
  if [ -z "$remote_url" ] || gitlore_is_placeholder_url "$remote_url"; then
    remote_url=""
  elif fetch_err=$(git -C "$store" fetch -q origin live 2>&1); then
    fetched=1
    # `-q --verify` is silent on the expected miss: a remote with no `live` yet.
    remote=$(git -C "$store" rev-parse -q --verify refs/remotes/origin/live) || remote=""
  fi

  # A tier's local `live` ahead of HEAD holds commits the ancestry tests below
  # cannot see, since they read HEAD, so those commits are adopted first —
  # unless the fetched remote already contains `live`. Then the fast-forward
  # takes origin's commits instead, including a repair of the same arrival that
  # another consumer already published, which adopting the stale copy would
  # repair a second time and diverge from. No remote, a failed fetch and a
  # remote with no `live` all adopt: nothing else here reaches those commits. A
  # failed adoption has reported itself, and the remote's report still follows,
  # so neither problem hides the other.
  live=$(git -C "$store" rev-parse -q --verify live) || live=""
  if [ -z "$remote" ] || [ -z "$live" ] || ! git -C "$store" merge-base --is-ancestor "$live" "$remote"; then
    gitlore_adopt_advanced_live "$mempath" "$store" "$tier" || adopt_rc=1
  fi

  if [ -z "$remote_url" ]; then
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
  if [ "$fetched" -eq 0 ]; then
    gitlore_say_for_agent_or_user \
      "gitlore: could not fetch $label from its remote. git said:
$fetch_err" \
      "gitlore: could not fetch $label from its remote. git said:
$fetch_err" >&2
    return 1
  fi
  if [ -z "$remote" ]; then
    printf 'gitlore: %s — its remote has no '\''live'\'' branch yet; nothing to take.\n' "$label"
    return "$adopt_rc"
  fi
  [ "$adopt_rc" -eq 0 ] || return 1
  head=$(git -C "$store" rev-parse HEAD) || return 1

  if git -C "$store" merge-base --is-ancestor "$remote" "$head"; then
    # Nothing to take, which is not the same as nothing to do: this test reads
    # HEAD, and the ref a push sends is `live`. A store whose `live` was left
    # behind reaches exactly here and would otherwise be told it is finished.
    # Repair BEFORE the report, so the reassurance is never the first thing a
    # store about to fail on its refs is told.
    gitlore_repair_stranded_live "$store" "$label" || return 1
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

  # Read before anything moves: what matters is whether the root store already
  # held work the canned commit would sweep up. Asked of the paths OUTSIDE the
  # pair — a root whose own take just landed shows the tier lagging its new
  # gitlink, which is this pass's business rather than someone else's edit. Root
  # `MEMORY.md` is inside the pair on purpose: the adoption below rewrites it
  # whatever it held, so composition already owns that file (D31).
  root_dirty_before=$(gitlore_root_dirty_beyond_pair "$mempath" "$tier")

  # Fast-forward: advance the local `live` (created here when the store never had
  # one), then move the working tree onto it. `push .` is ff-checked, so a race
  # that advanced `live` underneath us is refused rather than overwritten.
  local ff_err
  if ! ff_err=$(gitlore_git -C "$store" push -q . "$remote:refs/heads/live" 2>&1); then
    gitlore_say_for_agent_or_user \
      "gitlore: $label — its local 'live' could not be advanced. git said:
$ff_err" \
      "gitlore: $label — its local 'live' could not be advanced. git said:
$ff_err" >&2
    return 1
  fi
  if ! ff_err=$(gitlore_git -C "$store" checkout -q --detach live 2>&1); then
    gitlore_say_for_agent_or_user \
      "gitlore: $label — its 'live' advanced but its working tree could not follow. git said:
$ff_err" \
      "gitlore: $label — its 'live' advanced but its working tree could not follow. git said:
$ff_err" >&2
    return 1
  fi
  printf 'gitlore: %s — fast-forwarded to %s\n' "$label" "$(git -C "$store" rev-parse --short HEAD)"

  # Adopt: the carrier that just arrived becomes root's block for this tier. The
  # memory root adopts nothing — its own index is one of the files that moved.
  gitlore_adopt_tier_into_root "$mempath" "$tier" "$root_dirty_before" "$head" || return 1
  return 0
}

# Advance a store's local `live` when it has been left strictly behind a HEAD
# that already contains it.
#
# A store rests DETACHED AT `live` (D17), so `live` behind a HEAD containing it
# can only mean `live` failed to keep up: every commit in HEAD arrived through a
# path that advances both, and no path produces a HEAD deliberately ahead. The
# move is therefore unambiguous where gitlore_check_head_live_agree's general
# case is not — local, ff-checked, publishing nothing — and it is invisible to a
# take's ancestry test, which reads HEAD alone. A failed merge preparation that
# checked HEAD out at `origin/live` and stopped leaves precisely this, and the
# store then reports itself finished on every subsequent merge while every push
# is refused.
#
# Runs ahead of the report every publish preflight and every take makes, because
# there is nothing here for a human to decide: a round-trip that can only end in
# the one command this already ran is a round-trip not worth asking for.
#
# Only that direction. `live` AHEAD of HEAD is a pin (D43) or a publication
# awaiting its push, both someone else's business; a genuine divergence is
# reported and not touched, since which ref was intended is not recoverable
# from the refs themselves.
# Args: $1 = store, $2 = label.
# Returns 1 after emitting when the two have diverged.
gitlore_repair_stranded_live() {
  local store="$1" label="$2" head live push_err
  # An unborn store has neither ref to reconcile.
  head=$(git -C "$store" rev-parse -q --verify HEAD) || return 0
  # No local `live` yet (a tier never fetched) — nothing to strand.
  live=$(git -C "$store" rev-parse -q --verify live) || return 0
  [ "$live" != "$head" ] || return 0
  if ! git -C "$store" merge-base --is-ancestor "$live" "$head"; then
    # `live` ahead of HEAD: left alone, deliberately. Written as an `if` rather
    # than a `&&` list because a failing left side of `cmd && return 0` is an
    # errexit trip, not a fall-through.
    if git -C "$store" merge-base --is-ancestor "$head" "$live"; then
      return 0
    fi
    gitlore_say_for_agent_or_user \
      "gitlore: $label — HEAD and its local 'live' have each moved since they last agreed (HEAD $(git -C "$store" rev-parse --short "$head"), live $(git -C "$store" rev-parse --short "$live")), so neither was moved. Run /gitlore:resolve to reconcile them." \
      "gitlore: $label — HEAD and its local 'live' have each moved since they last agreed (HEAD $(git -C "$store" rev-parse --short "$head"), live $(git -C "$store" rev-parse --short "$live")), so neither was moved. Run /gitlore:resolve to reconcile them." >&2
    return 1
  fi
  # `push .` is ff-checked, as on the fast-forward path: a race that advanced
  # `live` underneath us is refused rather than overwritten.
  if ! push_err=$(gitlore_git -C "$store" push -q . HEAD:refs/heads/live 2>&1); then
    gitlore_say_for_agent_or_user \
      "gitlore: $label — its local 'live' could not be advanced. git said:
$push_err" \
      "gitlore: $label — its local 'live' could not be advanced. git said:
$push_err" >&2
    return 1
  fi
  printf 'gitlore: %s — its local '\''live'\'' was stranded behind HEAD; advanced it to %s.\n' \
    "$label" "$(git -C "$store" rev-parse --short "$head")"
  return 0
}

# True when a store's local `live` holds commits its HEAD does not. Silent on
# every expected miss — an unborn store, a tier never fetched, refs that agree —
# so the callers below read as the question they are asking.
# Args: $1 = store.
gitlore_live_ahead_of_head() {
  local store="$1" head live
  head=$(git -C "$store" rev-parse -q --verify HEAD) || return 1
  live=$(git -C "$store" rev-parse -q --verify live) || return 1
  [ "$head" != "$live" ] || return 1
  git -C "$store" merge-base --is-ancestor "$head" "$live"
}

# Adopt a TIER's local `live` when it holds commits its HEAD does not: move the
# working tree onto them, project the carrier up into root's block, and record
# the pair. The mirror of gitlore_repair_stranded_live, and the direction that
# one deliberately leaves alone.
#
# A tier commit advances HEAD and `live` together, so the two part only when the
# MEMORY side loses the moved gitlink afterwards — a merge preparation checks the
# memory store out and rewrites its index, and the next SessionStart pins HEAD
# back at the older commit (D43) while `live` keeps what was approved. Nothing
# reports it: `live` is invisible to the take's ancestry test, which reads HEAD,
# and to SessionStart's, which compares HEAD against the remote.
#
# Neither ref may simply be moved onto the other. Rewinding `live` discards
# approved commits; moving HEAD alone takes the tier off the commit the store
# records, which is the state gitlore_compose_check_pins refuses — so the publish
# gate's bare "put HEAD back on 'live'" remedy is the one that breaks the store.
# What the state calls for is the take: the same fast-forward-plus-adoption a
# remote arrival gets, sourced from a local ref. `live` already holds the target,
# so no ref moves here at all.
#
# TIERS ONLY. The memory root has no pin above it — SessionStart checks it out at
# `live` and the parent's gitlink is allowed to lag (D46) — so there a `live`
# ahead of HEAD is answered by the checkout the gate names, and moving the root
# store here would take a decision the refs do not carry.
# Args: $1 = memory worktree, $2 = store worktree, $3 = tier name ("" = root).
# Returns 1 after emitting when the adoption cannot proceed.
gitlore_adopt_advanced_live() {
  local mempath="$1" store="$2" tier="$3" label root_dirty_before head err
  [ -n "$tier" ] || return 0
  gitlore_live_ahead_of_head "$store" || return 0
  label="tier '$tier'"

  # Refused rather than checked out over, exactly as the remote take refuses a
  # dirty store: the working tree may hold this session's unapproved facts, and
  # the checkout below would carry them onto a commit nobody approved them
  # against.
  if [ "$(gitlore_memory_dirty "$store")" = "1" ]; then
    gitlore_say_for_agent_or_user \
      "gitlore: $label — its local 'live' holds commits the memory store never recorded, but the tier has uncommitted changes, so nothing was adopted. Commit them (approved summary, then a memory commit) and run /gitlore:merge again." \
      "gitlore: $label — its local 'live' holds commits the memory store never recorded, but the tier has uncommitted changes, so nothing was adopted. Commit them and merge again." >&2
    return 1
  fi

  # Read BEFORE the tree moves, same as the remote take: what matters is whether
  # the root already held work the canned bookkeeping commit would sweep up.
  root_dirty_before=$(gitlore_root_dirty_beyond_pair "$mempath" "$tier")
  head=$(git -C "$store" rev-parse HEAD) || return 1
  if ! err=$(gitlore_git -C "$store" checkout -q --detach live 2>&1); then
    gitlore_say_for_agent_or_user \
      "gitlore: $label — its working tree could not follow its local 'live'. git said:
$err" \
      "gitlore: $label — its working tree could not follow its local 'live'. git said:
$err" >&2
    return 1
  fi
  printf 'gitlore: %s — its local '\''live'\'' held commits the memory store never recorded; adopted them at %s.\n' \
    "$label" "$(git -C "$store" rev-parse --short HEAD)"
  gitlore_adopt_tier_into_root "$mempath" "$tier" "$root_dirty_before" "$head" || return 1
  return 0
}

# Project a tier's newly-adopted carrier up into the root index, stage the pair
# and record it — the tail every take shares, whether what arrived came from the
# tier's own remote or from a local `live` that ran ahead of the pin. A no-op for
# the memory root, which adopts nothing: its own index is one of the files that
# moved.
#
# A failed up projection records nothing and returns the tier's working tree to
# the pre-take commit. Staging the gitlink alone would put the tier back on its
# pin while root still holds the older block, so the next compose would write
# that older text over the carrier and report success (D50). Leaving the tier
# ahead of an unstaged pin is no better: the pin guard refuses every commit until
# SessionStart walks it back, and a take meanwhile finds nothing to take. Walked
# back here, the tier is on its pin with the arrival held in its local `live` —
# the state gitlore_adopt_advanced_live adopts — so the next take retries the
# whole adoption. The checkout loses nothing: a take refuses a dirty tier, and
# the up projection writes no carrier.
#
# A refusal in which any problem names the arriving carrier is repaired first:
# gitlore_adopt_repair_arrival commits the repaired carrier on top of the
# arrival, advances the tier's local `live` to it and retries. The repair then
# rests in `live` whether the retry adopts it or still refuses on root, the
# manifest or another tier — problems this repo fixes itself, which the retry's
# refusal reports and walks back from as above.
# Args: $1 = memory worktree, $2 = tier name ("" = the memory root), $3 = "1"
#       when the root store was dirty before the take, $4 = the pre-take commit.
# Returns 1 after emitting when the root index could not take the carrier.
gitlore_adopt_tier_into_root() {
  local mempath="$1" tier="$2" root_dirty_before="$3" old_gitlink="$4"
  local label composed carrier_problems rc=0
  [ -n "$tier" ] || return 0
  label="tier '$tier'"

  composed=$(gitlore_compose_up "$mempath" "$tier") || rc=$?
  if [ "$rc" -eq 1 ] && carrier_problems=$(gitlore_compose_problems_in "$mempath/$tier/MEMORY.md" <<<"$composed"); then
    gitlore_adopt_repair_arrival "$mempath" "$tier" "$old_gitlink" \
      "$root_dirty_before" "$label" "$carrier_problems" "$composed" || return 1
    return 0
  fi
  if [ "$rc" -ne 0 ]; then
    gitlore_adopt_report_refusal_and_walk_back "$mempath" "$tier" "$old_gitlink" "$label" "$composed" || :
    return 1
  fi
  [ -n "$composed" ] && printf '%s\n' "$composed" | sed 's/^/gitlore: /'
  gitlore_adopt_stage_pair_and_commit "$mempath" "$tier" "$root_dirty_before" "$old_gitlink" "$label"
}

# Repair the carrier a take just checked out, commit the repair on top of the
# arrival, advance the tier's local `live` to it and retry the up projection.
# History stays linear (D6), and the commit is unprompted (D49): it restructures
# lines that already passed an approval gate and adds no text. The worktree
# never holds the repair uncommitted — the rewrite happens on a scratch copy
# outside the repository, and the tier moves only by checking out `live` once
# it holds the commit — so a killed take leaves the tier clean, on the arrival,
# the repair or its pin, with `live` holding the arrival or the repair.
# Args: $1 = memory worktree, $2 = tier name, $3 = the pre-take commit,
#       $4 = "1" when the root store was dirty before the take,
#       $5 = "tier '<name>'", $6 = the first refusal's problems naming the
#       carrier, in the arrival's own line numbering, $7 = the first refusal's
#       full text, printed whole when the repair fails on something the next
#       take redoes, and for its problems beyond the carrier when the repair
#       cannot fix it.
# Returns 0 once the retry adopts the repair. Returns 1, having emitted and
# walked the tier back to its pin, when the repair cannot be built or cannot fix
# the carrier, `live` cannot be advanced, the worktree cannot follow it, or the
# retry still refuses.
gitlore_adopt_repair_arrival() {
  local mempath="$1" tier="$2" old_gitlink="$3" root_dirty_before="$4" label="$5" carrier_problems="$6" composed="$7"
  local tierpath="$mempath/$tier" scratch report line repair="" err retry_composed retry_rc=0
  local remedy="" other_lines

  if ! scratch=$(mktemp -d "${TMPDIR:-/tmp}/gitlore-repair.XXXXXX"); then
    printf 'gitlore: %s — its arrival could not be repaired: no scratch directory could be made.\n' "$label" >&2
    gitlore_adopt_report_refusal_and_walk_back "$mempath" "$tier" "$old_gitlink" "$label" "$composed" "Run /gitlore:merge again." || :
    return 1
  fi
  # A pin that predates the tier's own MEMORY.md leaves no pin copy, which
  # gitlore_repair_index reads as an empty carrier; `-q --verify` is silent on
  # that miss.
  if ! git -C "$tierpath" show HEAD:MEMORY.md > "$scratch/arrival"; then
    printf 'gitlore: %s — its arrival could not be read for repair.\n' "$label" >&2
  elif git -C "$tierpath" rev-parse -q --verify "$old_gitlink:MEMORY.md" >/dev/null &&
       ! git -C "$tierpath" show "$old_gitlink:MEMORY.md" > "$scratch/pin"; then
    printf 'gitlore: %s — the carrier at its pin could not be read for repair.\n' "$label" >&2
  elif ! report=$(gitlore_repair_index "$scratch/arrival" "$scratch/pin" "$tierpath"); then
    printf 'gitlore: %s — its arrival could not be rewritten during repair.\n' "$label" >&2
  elif [ -n "$(gitlore_compose_check_index "$scratch/arrival")" ]; then
    # The first refusal's lines, not the rechecked copy's: every line number
    # then counts in the commit the upstream fix is made against.
    printf 'gitlore: tier '\''%s'\'' took an index the take cannot repair; it is held in the tier'\''s local '\''live'\'' and must be fixed where it was published:\n' "$tier" >&2
    while IFS= read -r line || [ -n "$line" ]; do
      [ -n "$line" ] || continue
      printf 'gitlore:   live:MEMORY.md: %s\n' "${line#"$tierpath/MEMORY.md: "}" >&2
    done <<<"$carrier_problems"
    other_lines=$(
      while IFS= read -r line || [ -n "$line" ]; do
        [ -n "$line" ] || continue
        gitlore_compose_problems_in "$tierpath/MEMORY.md" <<<"$line" >/dev/null && continue
        printf '%s\n' "$line"
      done <<<"$composed"
    )
    if [ -n "$other_lines" ]; then
      printf 'gitlore: the root index could not take %s'\''s lines:\n' "$label" >&2
      printf '%s\n' "$other_lines" | sed 's/^/gitlore:   /' >&2
      remedy="Fix the problems listed above in this repo; once the index is fixed where it was published, run /gitlore:merge again."
    else
      remedy="Once the index is fixed where it was published, run /gitlore:merge again."
    fi
    rm -rf -- "$scratch"
    gitlore_adopt_walk_back_tier "$mempath" "$tier" "$old_gitlink" "$label" "$remedy" || :
    return 1
  elif ! repair=$(gitlore_adopt_commit_repair "$tierpath" "$tier" "$scratch" "$report"); then
    printf 'gitlore: %s — its arrival could not be repaired: building the repair commit failed.\n' "$label" >&2
    repair=""
  fi
  rm -rf -- "$scratch"
  # Every arm left here without a repair failed on something the next take
  # redoes from scratch.
  if [ -z "$repair" ]; then
    gitlore_adopt_report_refusal_and_walk_back "$mempath" "$tier" "$old_gitlink" "$label" "$composed" "Run /gitlore:merge again." || :
    return 1
  fi

  if ! err=$(gitlore_git -C "$tierpath" push -q . "$repair:refs/heads/live" 2>&1); then
    printf 'gitlore: %s — its repair could not advance its local '\''live'\''. git said:\n%s\n' "$label" "$err" >&2
    gitlore_adopt_report_refusal_and_walk_back "$mempath" "$tier" "$old_gitlink" "$label" "$composed" "Run /gitlore:merge again." || :
    return 1
  fi
  if ! err=$(gitlore_git -C "$tierpath" checkout -q --detach live 2>&1); then
    printf 'gitlore: %s — its repair advanced its local '\''live'\'' but its working tree could not follow. git said:\n%s\n' "$label" "$err" >&2
    gitlore_adopt_report_refusal_and_walk_back "$mempath" "$tier" "$old_gitlink" "$label" "$composed" "Run /gitlore:merge again." "the repair" || :
    return 1
  fi
  while IFS= read -r line || [ -n "$line" ]; do
    [ -n "$line" ] || continue
    printf 'gitlore: repaired %s'\''s arrival: %s\n' "$tier" "$line"
  done <<<"$report"

  retry_composed=$(gitlore_compose_up "$mempath" "$tier") || retry_rc=$?
  if [ "$retry_rc" -ne 0 ]; then
    gitlore_adopt_report_refusal_and_walk_back "$mempath" "$tier" "$old_gitlink" "$label" "$retry_composed" "" "the repair" || :
    return 1
  fi
  # Inside a push the take is itself publishing, and naming /gitlore:push would
  # send the reader to run again what is already running.
  if [ -n "${GITLORE_TAKE_IN_PUSH:-}" ]; then
    printf 'gitlore: %s — the repair is committed in its local '\''live'\'', and this push publishes it.\n' "$label"
  else
    printf 'gitlore: %s — the repair is committed in its local '\''live'\''; /gitlore:push publishes it.\n' "$label"
  fi
  [ -n "$retry_composed" ] && printf '%s\n' "$retry_composed" | sed 's/^/gitlore: /'
  gitlore_adopt_stage_pair_and_commit "$mempath" "$tier" "$root_dirty_before" "$old_gitlink" "$label"
}

# Print a commit whose only parent is the tier's HEAD and whose tree is HEAD's
# with MEMORY.md replaced, byte for byte, by <scratch>/arrival. Built from a
# temporary index in <scratch>, so the worktree is never the commit's staging
# area, and with `commit-tree`, which runs no hook.
# Args: $1 = tier worktree, $2 = tier name, $3 = scratch directory, $4 = the
#       repair report, which becomes the commit body.
gitlore_adopt_commit_repair() {
  local tierpath="$1" tier="$2" scratch="$3" report="$4" entry blob tree
  entry=$(git -C "$tierpath" ls-tree HEAD -- MEMORY.md) || return 1
  [ -n "$entry" ] || return 1
  GIT_INDEX_FILE="$scratch/index" git -C "$tierpath" read-tree HEAD || return 1
  blob=$(git -C "$tierpath" hash-object -w --no-filters -- "$scratch/arrival") || return 1
  GIT_INDEX_FILE="$scratch/index" git -C "$tierpath" update-index --cacheinfo "${entry%% *},$blob,MEMORY.md" || return 1
  tree=$(GIT_INDEX_FILE="$scratch/index" git -C "$tierpath" write-tree) || return 1
  git -C "$tierpath" commit-tree -p HEAD -m "Repair the MEMORY.md structure $tier received" -m "$report" "$tree"
}

# Print the problems the up projection could not take, then walk the tier back.
# Shared by a refusal naming nothing in the arriving carrier, by a repair that
# fails on something the next take redoes, and by a repair's retry that still
# finds root, the manifest or another tier refusing.
# Args: $1 = memory worktree, $2 = tier name, $3 = the pre-take commit,
#       $4 = "tier '<name>'", $5 = the compose problems, $6 = the closing
#       remedy and $7 = what the tier's local `live` keeps, both optional and
#       passed to gitlore_adopt_walk_back_tier, whose default an empty one keeps.
# Returns 1 after emitting.
gitlore_adopt_report_refusal_and_walk_back() {
  local mempath="$1" tier="$2" old_gitlink="$3" label="$4" composed="$5" remedy="${6:-}"
  local live_holds="${7:-}"
  printf 'gitlore: the root index could not take %s'\''s lines:\n' "$label" >&2
  printf '%s\n' "$composed" | sed 's/^/gitlore:   /' >&2
  gitlore_adopt_walk_back_tier "$mempath" "$tier" "$old_gitlink" "$label" "$remedy" "$live_holds" || :
  return 1
}

# Return the tier to the commit the memory store records, after a refusal left
# nothing to adopt.
# Args: $1 = memory worktree, $2 = tier name, $3 = the pre-take commit,
#       $4 = "tier '<name>'", for the messages, $5 = the closing remedy when
#       the store is not what needs fixing (optional; empty keeps "Fix the
#       store, …"), $6 = what the tier's local `live` keeps (optional; empty
#       keeps "what arrived").
# Returns 1 after emitting, whether or not the checkout succeeded.
gitlore_adopt_walk_back_tier() {
  local mempath="$1" tier="$2" old_gitlink="$3" label="$4" err abs
  local remedy="${5:-Fix the store, then run /gitlore:merge again.}"
  local live_holds="${6:-what arrived}"
  if ! err=$(gitlore_git -C "$mempath/$tier" checkout -q --detach "$old_gitlink" 2>&1); then
    # Absolute, so the printed command runs from anywhere.
    abs=$(CDPATH='' cd -- "$mempath/$tier" && pwd) || abs="$mempath/$tier"
    # shellcheck disable=SC2016  # backticks are markdown for the reader, not a command sub
    printf 'gitlore: nothing was recorded, but %s could not be returned to the commit the memory store records. git said:\n%s\ngitlore: run `git -C "%s" checkout --detach %s`, fix the store, then run /gitlore:merge again.\n' \
      "$label" "$err" "$abs" "$old_gitlink" >&2
    return 1
  fi
  printf 'gitlore: nothing was recorded, and %s is back on the commit the memory store records; its local '\''live'\'' keeps %s. %s\n' "$label" "$live_holds" "$remedy" >&2
  return 1
}

# Stage the tier's newly-adopted carrier pair and record it in a canned commit
# — the tail a landed take and a landed repair share.
# Args: $1 = memory worktree, $2 = tier name, $3 = "1" when the root store was
#       dirty before the take, $4 = the pre-take commit, $5 = "tier '<name>'".
gitlore_adopt_stage_pair_and_commit() {
  local mempath="$1" tier="$2" root_dirty_before="$3" old_gitlink="$4" label="$5" abs
  # Stage the pair the take just produced. `submodule update` reads the gitlink
  # from the superproject's INDEX, so an unstaged one is walked back to the
  # pre-take commit by the next SessionStart tier pass — and the composed root
  # index, being an ordinary working-tree write, survives to describe facts the
  # tier no longer holds. Staged, the unconditional pin is idempotent rather than
  # destructive. Staging is best-effort: a failure here must not turn a landed
  # take into a failed merge.
  # The printed path is absolute, so the command runs from anywhere.
  if ! gitlore_git -C "$mempath" add -- MEMORY.md "$tier"; then
    abs=$(CDPATH='' cd -- "$mempath" && pwd) || abs="$mempath"
    # shellcheck disable=SC2016  # backticks are markdown for the reader, not a command sub
    printf 'gitlore: %s advanced, but its pointer could not be staged in the memory store. Run `git -C "%s" add -- MEMORY.md "%s"` before the next session, or the pointer will be reset to its previous commit.\n' "$label" "$abs" "$tier" >&2
  fi
  # Then commit the pair, so an explicit take leaves a clean store (D49). The
  # dirty reading is the one taken BEFORE the tree moved: everything dirty now is
  # this take's own work, and anything that was dirty before it is unapproved
  # content the canned commit must not sweep up.
  gitlore_commit_tier_bookkeeping "$mempath" "$tier" "$root_dirty_before" "$old_gitlink"
}

# Commit the root index and moved tier gitlink an explicit take just staged,
# with a canned message, and fast-forward the store's local `live` onto it.
# Unprompted by design (D49): both parents of the take passed an approval gate
# already — the local side at its own FR11 commit, the upstream side in the repo
# that published it — so the bookkeeping introduces no unapproved content.
#
# Refuses, leaving the staged pair for the next FR11 episode, when the root
# store was dirty BEFORE the take: those edits are unapproved, and a canned
# `commit` would carry whatever else is staged alongside the pair. That path is
# D43's staged-pair discipline, which stays the degraded case rather than the
# resting state.
#
# Best-effort throughout: a landed fast-forward must not become a failed take
# because its bookkeeping could not be recorded. Every failure names the pair
# and leaves it staged.
# Args: $1 = memory worktree, $2 = tier name, $3 = "1" when the root store was
#       already dirty before the take, $4 = the tier's pre-take commit.
gitlore_commit_tier_bookkeeping() {
  local mempath="$1" tier="$2" dirty_before="$3" old_gitlink="$4"
  local msgfile err

  if [ "$dirty_before" = "1" ]; then
    printf 'gitlore: the memory store had uncommitted changes before this take, so the moved %s pointer and the recomposed root index were staged rather than committed. They ride the next memory commit (approved summary).\n' "$tier"
    return 0
  fi
  # Nothing staged: the root already records this exact state — a root commit
  # taken from upstream carried the gitlink, and the tier loop's fast-forward
  # then only caught the worktree up. An empty commit would fail, and reporting
  # that failure would dress a healthy path as a broken one.
  if git -C "$mempath" diff --cached --quiet; then
    return 0
  fi

  msgfile=$(mktemp "${TMPDIR:-/tmp}/gitlore-tier-msg.XXXXXX") || return 0
  {
    printf 'Update MEMORY.md for %s tier merge.\n\n' "$tier"
    # The subjects the take brought in. A fast-forward creates no commit in the
    # tier itself, so without this the root commit would be the only record and
    # would say nothing about what arrived.
    git -C "$mempath/$tier" log --format='%s' "$old_gitlink..HEAD" 2>/dev/null \
      | sed 's/^/  /'
  } > "$msgfile"

  # Bare `commit`, never `-a` or an `add -A`: exactly the pair staged above goes
  # in. A store clean before the take has nothing else staged to catch.
  if ! err=$(GITLORE_MEMORY_COMMIT=1 gitlore_git -C "$mempath" commit -q -F "$msgfile" 2>&1); then
    rm -f "$msgfile"
    printf 'gitlore: %s advanced and its pointer is staged, but the bookkeeping commit failed, so it rides the next memory commit. git said:\n%s\n' "$tier" "$err" >&2
    return 0
  fi
  rm -f "$msgfile"

  # Same invariant every other memory commit restores: `live` holds the commit
  # the moment it exists. Refused only by a race, which the next gate re-reads.
  if ! err=$(gitlore_git -C "$mempath" push -q . HEAD:live 2>&1); then
    printf 'gitlore: the %s bookkeeping commit landed but memory'\''s local '\''live'\'' could not follow it. git said:\n%s\n' "$tier" "$err" >&2
    return 0
  fi
  printf 'gitlore: memory — recorded %s'\''s move in a bookkeeping commit; the store is clean.\n' "$tier"
  return 0
}

# Print 1 when the root store holds a change beyond the pair a take is about to
# commit — its own `MEMORY.md` and the tier gitlink — and 0 otherwise.
#
# The plain dirty reading cannot answer this from inside a landed merge: the
# preparation has already moved the tier, so the root is dirty by construction
# and every take would refuse. What the guard is actually asking is whether
# somebody else's unapproved work would ride the canned commit, and that is a
# question about the OTHER paths. Pathspec exclusions, not a filter over
# porcelain output: a path with a space or a quote survives them intact.
# Args: $1 = memory worktree, $2 = tier name.
gitlore_root_dirty_beyond_pair() {
  local mempath="$1" tier="$2"
  if [ -z "$(git -C "$mempath" status --porcelain -- . ":(exclude)MEMORY.md" ":(exclude)$tier")" ]; then
    printf '0\n'
  else
    printf '1\n'
  fi
}

# The repository name a store's remote points at, for a merge subject line:
# the url's last path segment, minus a trailing `.git`. A store with no remote,
# or one still carrying the placeholder, falls back to its own directory name —
# the subject is a label, and a merge is worth recording under an imperfect one.
# Args: $1 = store worktree.
gitlore_store_repo_name() {
  local store="$1" url base
  url=$(git -C "$store" config --get remote.origin.url || true)
  if [ -z "$url" ] || gitlore_is_placeholder_url "$url"; then
    base=$(cd "$store" && pwd -P) || return 1
    printf '%s\n' "${base##*/}"
    return 0
  fi
  # Strip a trailing slash, then take the last segment of either url flavor —
  # `host:org/repo.git` and `https://host/org/repo` both end at the same `/`,
  # and an scp-style url with no path separator falls back to the whole tail.
  url="${url%/}"
  base="${url##*/}"
  base="${base##*:}"
  printf '%s\n' "${base%.git}"
}

# The name of the repository performing a merge — the parent working tree the
# memory store is a submodule of. A tier's `live` history is shared across every
# repo that mounts it, so the subject says which consumer landed the merge.
# Falls back to the memory store's own directory when no superproject answers.
# Args: $1 = memory worktree.
gitlore_consumer_name() {
  local mempath="$1" parent
  parent=$(git -C "$mempath" rev-parse --show-superproject-working-tree) || parent=""
  if [ -z "$parent" ]; then
    parent=$(cd "$mempath" && pwd -P) || return 1
  fi
  printf '%s\n' "${parent##*/}"
}

# The canned message for a merge commit in $2, on stdout: a subject naming the
# merged repo and the consumer that merged it, then the subjects the merge
# brought INTO `live` — the second-parent side. A tier store is read by every
# repo that mounts it, and each of those already holds the first-parent side;
# what the merge contributed is the news (D49).
# Args: $1 = memory worktree (for the consumer name), $2 = the merging store.
gitlore_merge_commit_message() {
  local mempath="$1" store="$2" repo consumer
  repo=$(gitlore_store_repo_name "$store") || repo="memory"
  consumer=$(gitlore_consumer_name "$mempath") || consumer="unknown"
  printf 'merge %s from %s\n\n' "$repo" "$consumer"
  # MERGE_HEAD is the pending (local) side under D6's direction: the authority
  # is checked out as HEAD and becomes the first parent. `-q --verify` is silent
  # if it is somehow absent, and the body is then simply empty.
  local second
  second=$(git -C "$store" rev-parse -q --verify MERGE_HEAD) || return 0
  git -C "$store" log --format='%s' "HEAD..$second" | sed 's/^/  /'
}
