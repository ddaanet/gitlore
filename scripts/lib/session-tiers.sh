#!/usr/bin/env bash
# The nested-tiers stage of session-start.sh (D17 3-i-a). Sourced by
# session-start.sh only; its function takes the memory path as its argument,
# calls session-start.sh's own `add_sysmsg` and session-memory.sh's
# `add_report_each`, and appends directly to session-start.sh's `$protocol_ctx`
# and `$unresolvable_tiers` globals — none declared here, all
# left for session-start.sh to emit or read.

# Report each tier submodule inside the memory store. Discovery is by
# enclosure — every entry in memory/.gitmodules is a tier. SessionStart moves no
# module: a tier that is not checked out is cloned at the commit memory records,
# and every other tier stays on the commit and the branch it is on, whatever its
# relation to that commit. A tier off its pin is the pin guard's report, which
# names /gitlore:merge; the hook leaves a tier ahead of its pin where it stands
# because the take needs it there to compose its lines up.
# Taking an upstream commit is a merge, and it goes through /gitlore:merge or
# /gitlore:push.
#
# Each tier is fetched read-only and reports its position against the
# authority's `live` (gitlore_module_position), then any recorded commit that
# neither it nor its remote holds.
#
# Every git call is guarded: a broken tier must never abort the session.
# Args: $1 = mempath.
gitlore_sync_nested_tiers() {
  local mempath="$1"
  local tier tierpath fetch_err url auth fetched position pin rc out crossing
  while IFS= read -r tier; do
    [ -n "$tier" ] || continue
    tierpath="$mempath/$tier"
    # Only a tier with no checkout is checked out, so a materialized tier's
    # merge state is never at risk: `git checkout`, which `submodule update`
    # runs, unlinks MERGE_HEAD and MERGE_MSG silently and on success.
    if [ ! -e "$tierpath/.git" ]; then
      gitlore_git -C "$mempath" submodule update --init -- "$tier" >&2 \
        || add_sysmsg "gitlore: tier '$tier' could not be checked out at its recorded commit; skipped."
      # The agent's own line: systemMessage is user-only (D14), and a pointer to
      # an absent file reads as stale to an agent told nothing.
      if [ ! -e "$tierpath/.git" ]; then
        protocol_ctx="$protocol_ctx

gitlore: tier '$tier' could not be checked out, so its facts are not available in this session. Its lines in $mempath/MEMORY.md stay: do not delete them."
        continue
      fi
    fi
    # A prepared merge is said, and nothing else is: an untouched tier that says
    # nothing is indistinguishable from one that synced, and a position read
    # would describe the preparation, which moved HEAD onto its authority, and
    # hint a second remedy. `detect` rather than `guard_stale_merge_state`: the
    # guard's directive tells the agent to abort and retry, which is wrong for a
    # merge that is simply waiting to be landed, and it writes to stderr, which
    # SessionStart does not show the user (D14).
    if [ "$(gitlore_detect_stale_merge_state "$tierpath")" != "clean" ] \
       || git -C "$tierpath" rev-parse -q --verify MERGE_HEAD >/dev/null; then
      # The agent gets its own line: systemMessage is user-only (D14), and the
      # destructive acts here are ones the agent takes unprompted, so the
      # prohibition leads and the remedy follows.
      add_report_each "gitlore: tier '$tier' has an unfinished merge, so its working tree was left as it is this session. Run /gitlore:resolve to land it." \
        "gitlore: tier at $tierpath holds an unfinished merge. Do not check it out, reset it, or commit into it. Run /gitlore:resolve to land the merge before writing anything to that tier."
      continue
    fi
    # Fetch read-only: `origin live` with no refspec moves no local branch, and
    # the remote tip is still in hand to compare against. Non-fatal — a session
    # must start whatever a tier's remote says — but NOT silent: a tier that has
    # quietly stopped talking to its remote is indistinguishable from one with
    # nothing new, so the reason is reported ahead of the position line. No
    # remote, or a remote with no `live` yet, reads against local `live`.
    auth=""
    fetched=1
    url=$(git -C "$tierpath" config --get remote.origin.url || true)
    if [ -n "$url" ]; then
      if fetch_err=$(git -C "$tierpath" fetch origin live 2>&1); then
        auth=$(git -C "$tierpath" rev-parse -q --verify FETCH_HEAD) || auth=""
      else
        case "$fetch_err" in
          *"couldn't find remote ref"*) ;;
          *)
            fetched=0
            add_sysmsg "gitlore: tier '$tier' could not fetch from its remote; it may be stale. git said: $fetch_err" ;;
        esac
      fi
    fi
    if [ -z "$auth" ]; then
      auth=$(git -C "$tierpath" rev-parse -q --verify refs/heads/live) \
        || auth=$(git -C "$tierpath" rev-parse -q --verify HEAD) || continue
    fi
    # A recorded commit the fetch did not bring is one no repository is known to
    # hold. A failed fetch cannot tell an unfetched commit from a lost one, and
    # the pin guard's report covers it.
    if [ "$fetched" -eq 1 ]; then
      pin=$(gitlore_tier_pin_absent "$mempath" "$tier")
      if [ -n "$pin" ]; then
        unresolvable_tiers="$unresolvable_tiers$tier
"
        add_report_each "$(gitlore_unresolvable_tier_report "$mempath" "$tier" "$pin" user)" \
          "$(gitlore_unresolvable_tier_report "$mempath" "$tier" "$pin" agent)"
      fi
    fi
    position=$(gitlore_module_position "$tierpath" "$auth") || continue
    case "$position" in
      forked)
        add_sysmsg "gitlore: tier '$tier' has a HEAD that diverged from its local 'live' — run /gitlore:push, which prepares the merge." ;;
      diverged)
        rc=0
        out=$(gitlore_rewrite_hit "$tierpath" "$auth" HEAD) || rc=$?
        case "$rc" in
          0) add_sysmsg "gitlore: tier '$tier' has diverged from its remote 'live' — each side has commits the other lacks. Run /gitlore:push to reconcile and publish." ;;
          1)
            crossing=$(gitlore_cross_rewrite_script "$tierpath")
            add_sysmsg "gitlore: tier '$tier' holds commits its remote rewrote (record gitlore/rewrites: $out is superseded). Nothing was merged. Run $crossing to cross this tier." ;;
          *)
            add_sysmsg "gitlore: tier '$tier' has diverged from its remote 'live', and its rewrite record gitlore/rewrites could not be fetched, so it cannot be checked for rewritten history. git said: $(printf '%s' "$out" | tr '\n' ' ')" ;;
        esac ;;
      ahead)
        if [ "$(git -C "$tierpath" rev-parse -q --verify refs/heads/live)" = "$auth" ]; then
          add_sysmsg "gitlore: tier '$tier' has a HEAD ahead of its local 'live' — run /gitlore:push."
        else
          add_sysmsg "gitlore: tier '$tier' holds commits its remote 'live' lacks — run /gitlore:push to publish them."
        fi ;;
      behind)
        if [ "$(git -C "$tierpath" rev-parse -q --verify refs/heads/live)" = "$auth" ]; then
          add_sysmsg "gitlore: tier '$tier' has commits on its local 'live' not checked out — run /gitlore:merge to take them."
        else
          add_sysmsg "gitlore: tier '$tier' has upstream facts waiting — its remote 'live' is ahead of this checkout. Run /gitlore:merge to take them; it needs no push."
        fi ;;
      *)
        add_sysmsg "gitlore: tier '$tier' in sync." ;;
    esac
  done < <(gitlore_tier_paths "$mempath")
}

# Print how commit $2 stands to commit $3 in store $1: `same`, `behind` (an
# ancestor), `ahead` (a descendant) or `diverged`.
gitlore_ref_relation() {
  local store="$1" a="$2" b="$3"
  if [ "$a" = "$b" ]; then
    echo same
  elif git -C "$store" merge-base --is-ancestor "$a" "$b"; then
    echo behind
  elif git -C "$store" merge-base --is-ancestor "$b" "$a"; then
    echo ahead
  else
    echo diverged
  fi
}
