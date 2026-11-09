#!/usr/bin/env bash
# The store-diagnostics stage of session-start.sh (D74). Sourced by
# session-start.sh only; reports through `add_report` (session-memory.sh), which
# session-start.sh also sources, and reads its `$unresolvable_tiers` global.
# Nothing here writes an index or moves a ref: the indexes are composed where
# the edit happens, and a store that arrives with a pending compose is reported,
# not repaired.

# Report the rule problems of the memory indexes (gitlore_compose_check), the
# indexes a compose pass would change, or, when a pass would change nothing, the
# tier index lines root does not carry.
#
# The pending report runs over every tier wherever it sits: the check is
# read-only, and a tier off its pin is one of the problems it reports, naming
# the take. Two states hold it back, and only the rule problems are reported over them: a
# prepared merge in memory or any tier, whose own notice is the report and whose
# merged index is the merger's business, and a tier whose recorded commit no
# repository holds, which composes nothing (gitlore_sync_nested_tiers reports
# it).
#
# A tier whose local `live` strictly contains its HEAD is taken with
# /gitlore:merge, not composed: composing first dirties the tier and the take
# refuses. The merge report then stands in for the compose report.
# Args: $1 = memory worktree path.
report_store_diagnostics() {
  local mempath="$1" tier tierpath ahead="" problems pending rc=0 held=0

  gitlore_store_mid_merge "$mempath" && held=1
  [ -n "${unresolvable_tiers:-}" ] && held=1
  while IFS= read -r tier; do
    [ -n "$tier" ] || continue
    # `git -C` into an unmaterialized submodule answers for the enclosing repo.
    [ -e "$mempath/$tier/.git" ] || continue
    gitlore_store_mid_merge "$mempath/$tier" && held=1
  done < <(gitlore_tier_paths "$mempath")

  if [ "$held" -eq 1 ]; then
    problems=$(gitlore_compose_check "$mempath") || rc=$?
    [ "$rc" -eq 0 ] || add_report "gitlore: the memory indexes cannot be composed until these are fixed:
$problems"
    return 0
  fi

  while IFS= read -r tier; do
    [ -n "$tier" ] || continue
    tierpath="$mempath/$tier"
    [ -e "$tierpath/.git" ] || continue
    if gitlore_live_ahead_of_head "$tierpath"; then
      ahead="$ahead$tier
"
    fi
  done < <(gitlore_active_tiers "$mempath")

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
  # Orphans describe a store as a pass leaves it: before one, a carrier line the
  # layout would adopt into root (a mount) reads as an orphan and is the pending
  # report's.
  if [ -z "$pending" ]; then
    report_store_orphans "$mempath"
    return 0
  fi

  if [ -n "$ahead" ]; then
    add_report "gitlore: these tiers hold commits on their local 'live' that the memory store has not taken. Run /gitlore:merge.
$(printf '%s' "$ahead" | sed 's/^/  /')"
    return 0
  fi
  add_report "gitlore: a compose pass would change these indexes:
$pending
Run gitlore-compose."
}

# The orphan report: carrier lines root never carried. A line the tier added
# changes nothing in a pass, so the pending report does not see it; it is
# reported and never refused, since which surface is right is a judgement about
# the fact. The user gets the count, the agent each line with both edits.
# Args: $1 = memory worktree path.
report_store_orphans() {
  local mempath="$1" orphans o unit capped
  orphans=$(gitlore_compose_orphans "$mempath")
  [ -n "$orphans" ] || return 0
  o=$(printf '%s\n' "$orphans" | grep -c .)
  if [ "$o" -eq 1 ]; then unit="line"; else unit="lines"; fi
  capped=$(printf '%s\n' "$orphans" | gitlore_cap_list
    gitlore_cap_rest_note "$o" "$mempath")
  add_sysmsg "gitlore: $o tier index $unit not in the root index, so not recallable here. Nothing was rewritten or deleted."
  protocol_ctx="$protocol_ctx

gitlore: these lines are in an active tier's own index but not in the root index ($o total), so they are not recallable here and nothing propagates them: composition projects the ROOT down, and root never carried them. Nothing was rewritten or deleted. Each line names both edits: delete it from the tier's index if the fact does not belong in this repo, or add the quoted line to $mempath/MEMORY.md if it does. Either edit is final.
$capped"
}

# Print dangling-report lines $2 without the root lines under a tier whose
# recorded commit no repository holds: those files are in the lost commit, the
# unresolvable-pin report covers them, and its remedies make them resolve or
# revert them, so telling anyone to delete the lines would be wrong.
# Args: $1 = memory worktree path, $2 = gitlore_compose_dangling's output.
gitlore_drop_unresolvable_dangling() {
  local mempath="$1" line tier keep
  while IFS= read -r line || [ -n "$line" ]; do
    [ -n "$line" ] || continue
    keep=1
    while IFS= read -r tier; do
      [ -n "$tier" ] || continue
      case "$line" in
        "$mempath/MEMORY.md: $tier/"*) keep=0 ;;
      esac
    done <<EOF
${unresolvable_tiers:-}
EOF
    [ "$keep" -eq 1 ] && printf '%s\n' "$line"
  done <<EOF
$2
EOF
  return 0
}
