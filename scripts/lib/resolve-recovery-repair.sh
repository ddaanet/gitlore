#!/usr/bin/env bash
# Repair a merge whose MERGE_HEAD a checkout cleared: landed, adopted or staged.
# Part of lib/resolve.sh; source that, not this file.

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
