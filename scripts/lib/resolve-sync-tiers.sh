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
# the memory commit. Recursion is driver-side by design; the memory store gets
# no recursing hook.
#
# Returns 1 after emitting a message when a tier cannot be committed or its
# `live` cannot be advanced for a reason other than divergence.
# Args: $1 = memory worktree path, $2 = the summary text.
gitlore_sync_tiers_to_live() {
  local mempath="$1" summary="$2" tier tierpath body landing pre
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
    # Written before the commit, so no interruption can leave the commit without
    # it, and dropped when the commit fails, so it never vouches for a commit
    # made later by other means: gitlore_stage_landed_tiers reads it on the
    # retry. A tier with no commit yet has no pin to compare, so records nothing.
    landing=$(gitlore_tier_landing_file "$tierpath") || return 1
    if pre=$(git -C "$tierpath" rev-parse -q --verify HEAD); then
      printf '%s\n' "$pre" > "$landing" || return 1
    fi
    # The message goes in on stdin: no file holds it. Plain git, not gitlore_git,
    # because its lock retry would re-read a stdin the first attempt consumed.
    if ! printf '%s\n' "$body" | GITLORE_MEMORY_COMMIT=1 git -C "$tierpath" commit -q -F -; then
      rm -f "$landing"
      return 1
    fi
    gitlore_advance_live "$tierpath" "tier '$tier'" "$tier" || return 1
  done < <(gitlore_tier_paths "$mempath")
  return 0
}
