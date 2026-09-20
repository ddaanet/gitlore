#!/usr/bin/env bash
# Commit every dirty tier and fast-forward each one's local `live`, reusing
# the episode's approved commit-message file (D17 lockstep).
# Part of lib/resolve.sh; source that, not this file.

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
