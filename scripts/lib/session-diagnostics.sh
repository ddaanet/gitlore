#!/usr/bin/env bash
# The store-diagnostics stage of session-start.sh (D74). Sourced by
# session-start.sh only; reports through `add_report` (session-memory.sh), which
# session-start.sh also sources. Nothing here writes an index or moves a ref:
# the indexes are composed where the edit happens, and a store that arrives with
# a pending compose is reported, not repaired.

# Report the rule problems of the memory indexes (gitlore_compose_check) and, on
# a store whose tiers all sit on their pins, the indexes a compose pass would
# change. Both ride the user's and the agent's channels.
#
# The pending report goes through gitlore_compose_pending, whose pin check puts a
# clean tier that is ahead of its pin back on it. That is a move, so the pending
# report runs only when no tier can be moved by it: every active tier's HEAD is
# its pin, and none is mid-merge. It also runs only when every active tier is
# checked out: a compose drops the root lines of a tier with no checkout, and
# those lines are not stale. A mid-merge tier and a tier with no checkout are
# the pin loop's notice alone (gitlore_sync_nested_tiers), and the rule problems
# are still reported.
#
# A tier whose local `live` strictly contains its HEAD is taken with
# /gitlore:merge, not composed: composing first dirties the tier and the take
# refuses. The merge report then stands in for the compose report.
# Args: $1 = memory worktree path.
report_store_diagnostics() {
  local mempath="$1" tier tierpath pinned head
  local movable=0 ahead="" problems pending rc=0

  while IFS= read -r tier; do
    [ -n "$tier" ] || continue
    tierpath="$mempath/$tier"
    # `git -C` into an unmaterialized submodule answers for the enclosing repo.
    if [ ! -e "$tierpath/.git" ]; then
      movable=1
      continue
    fi
    if gitlore_store_mid_merge "$tierpath"; then
      movable=1
      continue
    fi
    # No gitlink, or no HEAD yet: the pin check has no opinion about this tier
    # either, so it cannot move it.
    pinned=$(git -C "$mempath" rev-parse -q --verify ":$tier") || continue
    head=$(git -C "$tierpath" rev-parse -q --verify HEAD) || continue
    [ "$head" = "$pinned" ] || movable=1
    if gitlore_live_ahead_of_head "$tierpath"; then
      ahead="$ahead$tier
"
    fi
  done < <(gitlore_active_tiers "$mempath")

  if [ "$movable" -eq 1 ]; then
    problems=$(gitlore_compose_check "$mempath") || rc=$?
    [ "$rc" -eq 0 ] || add_report "gitlore: the memory indexes cannot be composed until these are fixed:
$problems"
    return 0
  fi

  pending=$(gitlore_compose_pending "$mempath") || rc=$?
  case "$rc" in
    0) ;;
    1)
      add_report "gitlore: the memory indexes cannot be composed until these are fixed:
$pending"
      return 0 ;;
    *)
      add_report "gitlore: the memory indexes could not be checked for pending changes:
$pending"
      return 0 ;;
  esac
  [ -n "$pending" ] || return 0

  if [ -n "$ahead" ]; then
    add_report "gitlore: these tiers hold commits on their local 'live' that the memory store has not taken. Run /gitlore:merge.
$(printf '%s' "$ahead" | sed 's/^/  /')"
    return 0
  fi
  add_report "gitlore: a compose pass would change these indexes:
$pending
Run gitlore-compose."
}
