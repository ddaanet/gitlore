#!/usr/bin/env bash
# The tier half of a take: the dirty-tier refusal, then each mounted tier's
# reconcile, take and carrier repair, before root's own. Called from
# gitlore_merge_stores and from push-memory.sh.
# Part of lib/resolve.sh; source that, not this file.

# Every mounted tier's reconcile and take, in order, the part of a take that
# precedes root's reconcile. Stops at the first store that yields or refuses. The
# dirty-tier refusal opens it, so /gitlore:merge, /gitlore:push and the pre-push
# hook meet the same preamble.
# Args: $1 = memory worktree path.
gitlore_take_tiers() {
  local mempath="$1" tier
  gitlore_refuse_dirty_tiers "$mempath" || return 1
  while IFS= read -r tier; do
    [ -n "$tier" ] || continue
    # `git -C` into an unchecked-out submodule walks up to the enclosing repo.
    [ -e "$mempath/$tier/.git" ] || continue
    gitlore_take_tier "$mempath" "$tier" || return 1
  done < <(gitlore_tier_paths "$mempath")
}

# One tier's reconcile, take and carrier repair. A tier inside a push is taken
# only when it holds something to take: the publish that follows owns the reports
# for a tier with no remote, a failed fetch and a remote with no `live`.
# Args: $1 = memory worktree path, $2 = tier name.
gitlore_take_tier() {
  local mempath="$1" tier="$2" tierpath="$1/$2"
  gitlore_reconcile_one "$tierpath" "tier '$tier'" || return 1
  if [ -z "${GITLORE_TAKE_IN_PUSH:-}" ] || gitlore_tier_has_arrivals "$tierpath"; then
    gitlore_merge_one_store "$mempath" "$tierpath" "$tier" || return 1
  fi
  gitlore_repair_moved_carrier "$mempath" "$tier"
}

# True when a tier's local `live` or its remote's holds commits its HEAD does not.
# Args: $1 = tier worktree.
gitlore_tier_has_arrivals() {
  local tierpath="$1" remote
  if gitlore_live_ahead_of_head "$tierpath"; then return 0; fi
  # Redirected because failure is an answer here, and the publish that follows
  # reports the same remote in its own words.
  git -C "$tierpath" fetch -q --no-recurse-submodules origin live >/dev/null 2>&1 || return 1
  remote=$(git -C "$tierpath" rev-parse -q --verify refs/remotes/origin/live) || return 1
  ! git -C "$tierpath" merge-base --is-ancestor "$remote" HEAD
}

# Refuse a take while any mounted tier has uncommitted changes and something to
# take, naming each. Something to take is what the take itself decides by.
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
