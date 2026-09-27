#!/usr/bin/env bash
# Where a store's merge state lives, and whether there is one: the gitdir paths
# of the merge-state file and its read-only briefing artifacts, their single
# remover, and the mid-merge predicates a commit path orders its own work behind.
# Part of util.sh; source that, not this file. Function-only (safe to source
# twice, unlike util.sh), so definition order between the two files does not
# matter.
#
# The state's IO and the merge itself — writing the marker and the full state
# file, preparing the merge, emitting the merger directive — is
# resolve-merge-state.sh instead. The cut is reachability rather than subject:
# what is here is what a caller that never sources resolve.sh can reach, which
# is why gitlore_store_mid_merge exists beside gitlore_detect_stale_merge_state
# rather than inside it.

# Print abs path to the memory submodule's merge-state file.
# Resolves through the submodule's gitdir correctly.
# Args: $1 = memory path (working tree).
gitlore_merge_state_file() {
  local mempath="$1"
  git -C "$mempath" rev-parse --git-path gitlore-merge-state
}

# Print abs path to one of the merge's read-only briefing artifacts — the two
# side diffs and the store's file tree, written at prepare time for the merger
# sub-agent. They live beside the state file in the gitdir, so they are invisible
# to `git status` and need no `.gitignore` entry, and they are named in the state
# file rather than reconstructed: the sub-agent runs no git of its own beyond
# `add`. Args: $1 = memory path, $2 = artifact suffix (mine.diff, theirs.diff, tree).
gitlore_merge_artifact_file() {
  git -C "$1" rev-parse --git-path "gitlore-merge-$2"
}

# Remove the merge state file and every artifact that was written with it.
# One remover, so a continuation cannot drop the state and leave the briefing
# behind for the next merge to be read against. Args: $1 = memory path.
gitlore_clear_merge_state() {
  local mempath="$1" name
  rm -f "$(gitlore_merge_state_file "$mempath")"
  for name in mine.diff theirs.diff tree; do
    rm -f "$(gitlore_merge_artifact_file "$mempath" "$name")"
  done
}

# Exit 0 when a store holds an unfinished merge — a merge-state file, a
# MERGE_HEAD, or both. This is gitlore_detect_stale_merge_state's "clean"
# outcome inverted, without its classification of the other three: a caller that
# only needs to order a merge ahead of its own work lives outside resolve.sh
# (memory-commit-batch.sh, and index-compose-check.sh, which resolve.sh sources)
# and cannot reach that function.
#
# Kept rather than replaced by gitlore_any_store_mid_merge below: a caller that
# asks about one *named* store still needs this one. index-compose-check.sh runs
# its own per-tier loop and reports which tier is mid-merge, which the composed
# predicate's single yes/no cannot tell it.
# Args: $1 = store worktree path.
gitlore_store_mid_merge() {
  local store="$1"
  [ -f "$(gitlore_merge_state_file "$store")" ] && return 0
  # `-q --verify` is silent on the expected miss: no merge in progress.
  git -C "$store" rev-parse -q --verify MERGE_HEAD >/dev/null
}

# Exit 0 when the memory store or any mounted tier holds an unfinished merge —
# a tier's merge lives in the tier's own gitdir, not the root's. Skips an
# unmaterialized tier, where `git -C` answers for the enclosing repo instead.
#
# The loop reads gitlore_tier_paths — every mounted tier — and not
# gitlore_active_tiers, the manifest subset. What it orders against is
# gitlore_sync_tiers_to_live, which commits inside a mounted-but-unlisted tier
# too, so tightening the loop to the manifest would leave a dormant tier's
# prepared merge invisible to every screen, with the suite still green.
# Args: $1 = memory worktree path — the root store, NOT a tier. Passed a tier
# path, this loops over that tier's own (absent) submodules and answers for it
# alone: the root-only read it exists to replace, silently, at a call that reads
# as correct.
gitlore_any_store_mid_merge() {
  local mempath="$1" tier
  gitlore_store_mid_merge "$mempath" && return 0
  while IFS= read -r tier; do
    [ -n "$tier" ] || continue
    [ -e "$mempath/$tier/.git" ] || continue
    gitlore_store_mid_merge "$mempath/$tier" && return 0
  done < <(gitlore_tier_paths "$mempath")
  return 1
}
