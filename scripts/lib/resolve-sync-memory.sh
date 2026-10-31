#!/usr/bin/env bash
# Commit the memory store and its dirty tiers from the sectioned summary, and
# fast-forward each committed store's local `live`: the FR11 commit path,
# including tier composition, the pin guard and the landing record. It never
# prepares or takes a merge; a `live` that cannot fast-forward is reported.
# Part of lib/resolve.sh; source that, not this file.

# Say that a store has forked from its local `live` after a commit. Not an
# error: the commit stands and the next act is named. $1 = the store's label.
gitlore_report_forked() {
  local label="$1"
  printf 'gitlore: %s committed. Local live has diverged. Run /gitlore:merge to reconcile them, or /gitlore:push to reconcile and publish.\n' "$label" >&2
}

# Fast-forward a store's local `live` to its HEAD. Returns 0 when live advanced,
# was already there, or cannot fast-forward because the two have forked (reported
# by gitlore_report_forked). Returns 1 when the store is behind its own live, or
# the update fails for a reason other than divergence.
# Args: $1 = store worktree, $2 = label for messages, $3 = tier name ("" for memory).
gitlore_advance_live() {
  local store="$1" label="$2" tier="${3-}" push_err live head
  # `-q --verify` is silent when `live` does not exist (a tier never fetched).
  live=$(git -C "$store" rev-parse -q --verify live) || return 0
  head=$(git -C "$store" rev-parse HEAD)
  [ "$head" = "$live" ] && return 0
  # Capture, don't discard: a failure for any reason other than divergence (a
  # ref lock, a corrupt object) must not be read as a fork.
  if push_err=$(gitlore_git -C "$store" push -q . HEAD:live 2>&1); then
    return 0
  fi
  case "$push_err" in
    *"(fetch first)"*|*"(non-fast-forward)"*) ;;
    *)
      gitlore_say_for_agent_or_user \
        "gitlore: $label could not advance its local 'live', and not because of divergence. git said:
$push_err" \
        "gitlore: $label could not advance its local 'live'. git said:
$push_err" >&2
      return 1
      ;;
  esac
  case "$(gitlore_classify_refusal "$store" HEAD live)" in
    diverged)
      gitlore_report_forked "$label"
      return 0
      ;;
    behind)
      # HEAD behind its own live: a checkout or take owns that, not a commit.
      gitlore_check_head_live_agree "$store" "$label" "$tier" || true
      return 1
      ;;
  esac
  gitlore_say_for_agent_or_user \
    "gitlore: $label could not advance its local 'live', though neither side has diverged. git said:
$push_err" \
    "gitlore: $label could not advance its local 'live'. git said:
$push_err" >&2
  return 1
}

# Whether the staged MEMORY.md of the memory worktree $1 changes a link into the
# tier $2. Captured rather than `grep -q`: an early exit would SIGPIPE the diff
# under the caller's pipefail.
# Args: $1 = memory worktree, $2 = tier name.
gitlore_staged_index_links_into() {
  local hits
  hits=$(git -C "$1" diff --cached -U0 -- MEMORY.md | grep -E '^[-+]' | grep -vE '^(\+\+\+|---) ' | grep -F -- "]($2/" || true)
  [ -n "$hits" ]
}

# Commit the memory store's own changes: every change left after the tiers
# committed, staged with `add -A` so the moved tier gitlinks ride along. Under a
# `== memory ==` section that section is the message; with none, the commit is
# the canned index commit naming the tiers whose pointers it carries.
# Returns 1 on a failed stage or commit. Args: $1 = memory worktree, $2 = summary.
gitlore_commit_root() {
  local mempath="$1" summary="$2" tier body names="" canned
  # Checked explicitly, for the same reason as the tier loop: a caller that
  # tests this function's status suspends errexit.
  gitlore_git -C "$mempath" add -A || return 1
  # Every tier gitlink is staged now, so no landing record is left with a
  # commit to vouch for.
  while IFS= read -r tier; do
    [ -n "$tier" ] || continue
    [ -e "$mempath/$tier/.git" ] || continue
    rm -f "$(gitlore_tier_landing_file "$mempath/$tier")"
  done < <(gitlore_tier_paths "$mempath")
  # Nothing staged: a store whose only change was a tier already committed, with
  # no pointer left to record. Nothing to commit is not a failure.
  if git -C "$mempath" diff --cached --quiet; then
    return 0
  fi
  body=$(gitlore_summary_section "$summary" memory)
  if [ -n "${body//[[:space:]]/}" ]; then
    gitlore_git -C "$mempath" commit -q -m "$body" || return 1
    return 0
  fi
  while IFS= read -r tier; do
    [ -n "$tier" ] || continue
    if [ -n "$(git -C "$mempath" diff --cached --name-only -- "$tier")" ] \
      || gitlore_staged_index_links_into "$mempath" "$tier"; then
      names="${names:+$names, }$tier"
    fi
  done < <(gitlore_tier_paths "$mempath")
  canned="Index lines${names:+ from $names}"
  gitlore_git -C "$mempath" commit -q -m "$canned" || return 1
}

# Commit the memory store and its dirty tiers from the summary, then advance each
# committed store's local `live`. The caller has checked the summary's sections
# and that something has changes.
# Returns 0 on success. Returns 1 after emitting a directive when a stale merge
# state is present, the compose or pin guard refuses, or a commit or a
# fast-forward fails for a reason other than divergence.
# Args: $1 = memory worktree path, $2 = the summary text.
gitlore_sync_memory_to_live() {
  local mempath="$1" summary="$2"

  # Stale merge-state precheck: never commit on top of a half-finished merge.
  gitlore_guard_stale_merge_state "$mempath" || return 1

  local tier
  # A tier holding a prepared merge makes memory dirty by construction, so every
  # tier gets its stale-merge guard before the first write into any of them.
  while IFS= read -r tier; do
    [ -n "$tier" ] || continue
    # `git -C` into an unmaterialized submodule walks up to the enclosing repo.
    [ -e "$mempath/$tier/.git" ] || continue
    gitlore_guard_stale_merge_state "$mempath/$tier" || return 1
  done < <(gitlore_tier_paths "$mempath")

  # A previous run that committed inside a tier and stopped before memory's
  # `add -A` recorded it left that tier ahead of its pin — the shape the pin
  # guard below refuses — so it is adopted first.
  gitlore_stage_landed_tiers "$mempath" || return 1

  # A tier off its pin refuses composition itself (D31, D36), but leaving that
  # refusal to gitlore_compose's own rc-1 arm would let the `add -A` below stage
  # the moved gitlink anyway. Checked here, ahead of compose, so an off-pin tier
  # aborts instead.
  # The declaration stays on its own line: folded into `local pin_problems=$(…)`
  # the status read is `local`'s, always 0, and the refusal is swallowed.
  local pin_problems
  if ! pin_problems=$(gitlore_compose_check_pins "$mempath"); then
    local pin_header="gitlore: a tier was moved off the commit the memory store records for it, so the commit was aborted rather than adopt the move:
$pin_problems"
    # The agent arm names no remedy of its own: every branch of
    # gitlore_compose_check_pins already printed the one its cause takes, and
    # $pin_problems can carry several tiers with different causes.
    gitlore_say_for_agent_or_user \
      "$pin_header
gitlore: composing would have overwritten what that tier holds, and committing would have adopted the move silently. Follow the remedy on each line above, then retry the commit." \
      "$pin_header
gitlore: composing would have overwritten what that tier holds. Open this project in Claude Code and ask it to repair the memory store, then retry." >&2
    return 1
  fi

  # Compose before the tier commit below: composition writes carrier files
  # inside the tiers, so it must land before the tiers' gitlinks move, or the
  # gitlink pins the pre-compose content.
  local compose_result compose_rc=0
  compose_result=$(gitlore_compose "$mempath") || compose_rc=$?
  case "$compose_rc" in
    0) ;;
    1)
      # A refusal writes nothing (D31, D36): projecting root's older text over
      # an unadopted carrier would destroy approved upstream facts. The commit
      # aborts only on a problem it would publish: a rule 1, 4 or 6 problem in
      # root's MEMORY.md or a tier carrier, when that file has uncommitted
      # changes. The same problems in a file with none report and let the commit
      # go ahead.
      local refusal="gitlore: tier composition refused — the memory indexes were left untouched:
$compose_result"
      # A status read that fails aborts rather than reading as a clean index.
      local abort_files="" index_status
      if printf '%s\n' "$compose_result" \
        | gitlore_compose_problems_in "$mempath/MEMORY.md" >/dev/null; then
        index_status=$(git -C "$mempath" status --porcelain -- MEMORY.md) \
          || { gitlore_say_unreadable_index_status "$mempath/MEMORY.md" "$refusal"
               return 1; }
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
               return 1; }
        [ -z "$index_status" ] \
          || abort_files="${abort_files:+$abort_files
}$mempath/$tier/MEMORY.md"
      done < <(gitlore_tier_paths "$mempath")
      if [ -n "$abort_files" ]; then
        gitlore_say_for_agent_or_user \
          "$refusal
gitlore: the commit was aborted because a problem is in an index file this commit changes — committing would publish it. The changed index files with problems:
$abort_files
Fix them by editing the lines above that name those files, then retry the commit." \
          "$refusal
gitlore: the commit was aborted because a problem is in an index file this commit changes. Open this project in Claude Code and ask it to repair the memory store, then retry." >&2
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
      # be committed, so this aborts before any store is committed.
      local partial="gitlore: tier composition could not write an index — the memory indexes are only partly composed:
$compose_result"
      gitlore_say_for_agent_or_user \
        "$partial
gitlore: the commit was aborted so the half-written carrier is not committed. Investigate that path (permissions, disk space, a read-only worktree), then retry the commit." \
        "$partial
gitlore: the commit was aborted so the half-written carrier is not committed. Open this project in Claude Code and ask it to repair the memory store, then retry." >&2
      return 1
      ;;
    *)
      # Unreachable from gitlore_compose, which returns 0, 1 or 2 and nothing
      # else. Kept because silently proceeding on an unknown status is the
      # failure the case exists to remove.
      local unknown="gitlore: tier composition exited with an unrecognised status ($compose_rc), so what it wrote is unknown:
$compose_result"
      gitlore_say_for_agent_or_user \
        "$unknown
gitlore: the commit was aborted rather than commit a memory store in an unknown state. Establish what gitlore_compose did, then retry the commit." \
        "$unknown
gitlore: the commit was aborted rather than commit a memory store in an unknown state. Open this project in Claude Code and ask it to repair the memory store, then retry." >&2
      return 1
      ;;
  esac

  # Tiers first: a tier commit moves its gitlink, and the root commit records
  # that move. Reversing the order would pin the tier SHA from before the commit.
  gitlore_sync_tiers_to_live "$mempath" "$summary" || return 1
  gitlore_commit_root "$mempath" "$summary" || return 1
  gitlore_advance_live "$mempath" memory || return 1
  return 0
}

# Stage the memory gitlink into the superproject index (D58) when this run moved
# memory HEAD. A no-op run stages nothing. The staging is skipped during a replay
# (rebase, cherry-pick, revert): a replayed commit must keep the pointer it
# recorded, and the memory worktree does not move when the parent's HEAD does.
# Args: $1 = memory worktree path.
gitlore_stage_memory_pointer() {
  local mempath="$1" super top rel p name op err
  super=$(git -C "$mempath" rev-parse --show-superproject-working-tree)
  [ -n "$super" ] || return 0
  top=$(git -C "$mempath" rev-parse --show-toplevel)
  rel="${top#"$super"/}"
  # Marker list: path:operation. A merge is deliberately absent — it is authored now.
  for marker in rebase-merge:rebase rebase-apply:rebase \
                CHERRY_PICK_HEAD:cherry-pick REVERT_HEAD:revert; do
    name="${marker%%:*}"
    p=$(git -C "$super" rev-parse --git-path "$name")
    case "$p" in /*) ;; *) p="$super/$p" ;; esac
    if [ -e "$p" ]; then
      op="${marker##*:}"
      echo "gitlore: $op in progress — skipping the staging of the memory pointer; stage it yourself once the $op is done." >&2
      return 0
    fi
  done
  if ! err=$(git -C "$super" add -- "$rel" 2>&1); then
    echo "gitlore: memory was committed, but its pointer could not be staged in the parent (git: $err). The pointer floats until you stage it." >&2
  fi
}
