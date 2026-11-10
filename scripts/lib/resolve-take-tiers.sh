#!/usr/bin/env bash
# The tier half of a take: each mounted tier's reconcile, take and carrier
# repair, before root's own, called from gitlore_merge_stores and from
# push-memory.sh; and the dirty-tier refusal, which gitlore_guard_every_store
# runs ahead of every take and every publish.
# Part of lib/resolve.sh; source that, not this file.

# Every mounted tier's reconcile and take, in order, the part of a take that
# precedes root's reconcile. Stops at the first store that yields or refuses
# with 1. A tier whose remote was left untaken with nothing prepared or to
# resolve by hand (gitlore_merge_one_store's 2) is passed over, so the tiers
# after it are still taken and the end compose records the ones that moved; the
# run then returns 2, and gitlore_merge_stores reads it to still fail the take.
#
# A dirty memory root whose HEAD has forked from its local `live` is refused
# first, with the yield's own refusal: root's reconcile refuses it after the
# tiers, and a tier moved by then sits ahead of its pin, which the memory
# commit that refusal asks for is itself refused on.
# Returns 0 when every tier is reconciled, 2 when one was passed over, 1 after
# emitting on a yield or any other refusal.
# Args: $1 = memory worktree path.
gitlore_take_tiers() {
  local mempath="$1" tier rc=0 tier_rc
  if [ "$(gitlore_classify_refusal "$mempath" HEAD live)" = "diverged" ]; then
    gitlore_refuse_dirty_merge "$mempath" live || return 1
  fi
  while IFS= read -r tier; do
    [ -n "$tier" ] || continue
    # `git -C` into an unchecked-out submodule walks up to the enclosing repo.
    [ -e "$mempath/$tier/.git" ] || continue
    tier_rc=0
    gitlore_take_tier "$mempath" "$tier" || tier_rc=$?
    case "$tier_rc" in
      0) ;;
      2) rc=2 ;;
      *) return 1 ;;
    esac
  done < <(gitlore_tier_paths "$mempath")
  return "$rc"
}

# One tier's reconcile, take and carrier repair. A tier inside a push is taken
# only when it holds something to take: the publish that follows owns the reports
# for a tier with no remote, a failed fetch and a remote with no `live`.
# Returns gitlore_merge_one_store's 2 as is and skips the repair, though the
# adoption of a local `live` ahead of HEAD may have moved the tier.
# Args: $1 = memory worktree path, $2 = tier name.
gitlore_take_tier() {
  local mempath="$1" tier="$2" tierpath="$1/$2" rc=0
  gitlore_reconcile_one "$tierpath" "tier '$tier'" || return 1
  if [ -z "${GITLORE_TAKE_IN_PUSH:-}" ] || gitlore_tier_has_arrivals "$tierpath"; then
    gitlore_merge_one_store "$mempath" "$tierpath" "$tier" || rc=$?
    [ "$rc" -eq 0 ] || return "$rc"
  fi
  gitlore_repair_moved_carrier "$mempath" "$tier"
}

# True when a tier's HEAD does not contain its local `live` or its remote's
# `live`: ahead of HEAD, forked from it or diverged, each is something to take.
# Args: $1 = tier worktree.
gitlore_tier_has_arrivals() {
  local tierpath="$1" live remote
  # `-q --verify` is silent on the expected miss: a tier never fetched has no
  # local `live`.
  if live=$(git -C "$tierpath" rev-parse -q --verify live) &&
     ! git -C "$tierpath" merge-base --is-ancestor "$live" HEAD; then
    return 0
  fi
  # Redirected because failure is an answer here, and the publish that follows
  # reports the same remote in its own words.
  git -C "$tierpath" fetch -q --no-recurse-submodules origin live >/dev/null 2>&1 || return 1
  remote=$(git -C "$tierpath" rev-parse -q --verify refs/remotes/origin/live) || return 1
  ! git -C "$tierpath" merge-base --is-ancestor "$remote" HEAD
}

# Refuse while any mounted tier has uncommitted changes and something to take,
# naming each. Something to take is what the take itself decides by.
# Args: $1 = memory worktree path. Returns 1 after emitting.
gitlore_refuse_dirty_tiers() {
  local mempath="$1" tier refused=0
  while IFS= read -r tier; do
    [ -n "$tier" ] || continue
    [ -e "$mempath/$tier/.git" ] || continue
    [ "$(gitlore_memory_dirty "$mempath/$tier")" = "1" ] || continue
    gitlore_tier_has_arrivals "$mempath/$tier" || continue
    refused=1
    gitlore_say_for_agent_or_user \
      "gitlore: tier '$tier' has uncommitted changes, so nothing was taken. Commit them (approved summary, then a memory commit) and run /gitlore:merge again." \
      "gitlore: tier '$tier' has uncommitted changes, so nothing was taken. Commit them and merge again." >&2
  done < <(gitlore_tier_paths "$mempath")
  [ "$refused" -eq 0 ]
}
