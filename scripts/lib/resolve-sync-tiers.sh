#!/usr/bin/env bash
# Commit every dirty tier from its section of the summary, and advance each
# committed tier's local `live` (D17 lockstep). Never prepares a merge.
# Part of lib/resolve.sh; source that, not this file.

# Commit every dirty mounted tier, each under its own `== <tier> ==` section of
# the summary, and fast-forward each committed tier's local `live`. A tier that
# cannot fast-forward is reported by gitlore_advance_live and left where it is.
#
# Scope is every MOUNTED tier, not only the active ones: the activation manifest
# governs routing and composition, and silently dropping a dormant tier's writes
# would be data loss rather than dormancy. The caller has already refused a
# dirty tier with no section, so a missing body here is a refusal, not a skip.
#
# Runs BEFORE memory's own `git add -A`, so the moved tier gitlink is part of
# the memory commit. Each tier's gitlink is staged in memory as its commit
# lands: a staged gitlink is root's record of having seen the tier (D78), so a
# run interrupted before memory's commit meets its pin guard with the tier on
# its pin and completes on retry, while a kill between the tier's commit and
# that staging still ends at /gitlore:merge. Recursion is driver-side by
# design; the memory store gets no recursing hook.
#
# Returns 1 after emitting a message when a tier cannot be committed or its
# `live` cannot be advanced for a reason other than divergence.
# Args: $1 = memory worktree path, $2 = the summary text.
gitlore_sync_tiers_to_live() {
  local mempath="$1" summary="$2" tier tierpath body
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
    body=$(gitlore_summary_section "$summary" "$tier")
    if [ -z "${body//[[:space:]]/}" ]; then
      gitlore_say_for_agent_or_user \
        "gitlore: tier '$tier' has changes but its summary has no section for it, so nothing was committed. Run /gitlore:commit." \
        "gitlore: tier '$tier' has changes but its summary has no section for it, so nothing was committed. Run /gitlore:commit." >&2
      return 1
    fi
    gitlore_git -C "$tierpath" add -A || return 1
    # The message goes in as an argument: no file holds it, and gitlore_git's
    # lock retry has no stdin to re-read.
    gitlore_git -C "$tierpath" commit -q -m "$body" || return 1
    gitlore_git -C "$mempath" add -- "$tier" || return 1
    gitlore_advance_live "$tierpath" "tier '$tier'" "$tier" || return 1
  done < <(gitlore_tier_paths "$mempath")
  return 0
}
