#!/usr/bin/env bash
# The memory-position report stage of session-start.sh (D59), and the position
# rule every module's report reads. Sourced by session-start.sh only; its
# functions call session-start.sh's own `add_sysmsg` and append directly to its
# `$protocol_ctx` global — neither declared here, both left for session-start.sh
# to emit.

# A report line (D59) rides both channels: the user's systemMessage (D14) and
# the agent's additionalContext, the way tier lines are added.
add_report() {
  add_sysmsg "$1"
  protocol_ctx="$protocol_ctx

$1"
}

# Print where module $1 stands against authority commit $2: `forked` when HEAD
# and local `live` each hold commits the other lacks, else the furthest of
# HEAD's and `live`'s relations to the authority — `diverged`, `ahead`, `behind`
# — or `in-sync`. A module is the memory store or a tier. Not the pin: being
# ahead of the commit memory records says nothing, so memory published before
# the parent commit reads as in sync. A module with no local `live` (a fresh
# clone, a tier never reconciled) is read as `live` at HEAD.
# Args: $1 = store worktree path, $2 = authority sha.
gitlore_module_position() {
  local store="$1" auth="$2" head live h l
  head=$(git -C "$store" rev-parse HEAD) || return 1
  live=$(git -C "$store" rev-parse -q --verify refs/heads/live) || live="$head"
  if ! git -C "$store" merge-base --is-ancestor "$live" "$head" \
     && ! git -C "$store" merge-base --is-ancestor "$head" "$live"; then
    echo forked
    return 0
  fi
  h=$(gitlore_ref_relation "$store" "$head" "$auth")
  l=$(gitlore_ref_relation "$store" "$live" "$auth")
  case "$h $l" in
    *diverged*) echo diverged ;;
    *ahead*) echo ahead ;;
    *behind*) echo behind ;;
    *) echo in-sync ;;
  esac
}

# Reports where memory stands (D59): a prepared merge, or else its position
# against the authority's `live` — its remote's when the fetch brought it, its
# own local `live` otherwise (no remote, a failed fetch, a remote with no `live`
# yet). Then the parent's pin on memory, when memory does not hold it. Reads
# only: nothing here moves HEAD, the worktree or any local branch.
# Args: $1 = memory worktree path.
report_memory_position() {
  local mempath="$1" dirty=0 head live auth n unit remote_url fetch_err remote="" fetched=1
  local position tip rc out crossing pin
  if gitlore_store_mid_merge "$mempath"; then
    report_memory_mid_merge "$mempath"
  else
    dirty=$(gitlore_memory_dirty "$mempath")
    [ "$dirty" = "1" ] && add_report "gitlore: memory — uncommitted changes present."
  fi

  # Remote: a read-only fetch of `live`, and only for a real remote. The
  # placeholder (or no origin at all) is a local-only install with nothing to
  # ask, and a remote that has no `live` yet has nothing upstream; both read
  # against local `live` and add no line. Any other fetch failure is named,
  # with git's own reason, ahead of the position line.
  remote_url=$(git -C "$mempath" config --get remote.origin.url || true)
  if [ -n "$remote_url" ] && ! gitlore_is_placeholder_url "$remote_url"; then
    if fetch_err=$(git -C "$mempath" fetch -q origin live 2>&1); then
      remote=$(git -C "$mempath" rev-parse -q --verify refs/remotes/origin/live) || remote=""
    else
      case "$fetch_err" in
        *"couldn't find remote ref"*) ;;
        *)
          fetched=0
          # git's stderr can carry text the remote chose (`remote: …` lines), so
          # it goes to the user only; the agent's context gets the fixed sentence.
          add_sysmsg "gitlore: could not fetch memory's remote 'live', so upstream memory is unknown. git said: $(printf '%s' "$fetch_err" | tr '\n' ' ')"
          protocol_ctx="$protocol_ctx

gitlore: could not fetch memory's remote 'live', so upstream memory is unknown; the user has git's message."
          ;;
      esac
    fi
  fi

  # The parent's pin, once the fetch has had its chance to bring the commit. A
  # failed fetch cannot tell an unfetched commit from a lost one.
  if [ "$fetched" -eq 1 ]; then
    pin=$(gitlore_parent_pin_absent "$mempath")
    [ -n "$pin" ] && add_report "$(gitlore_unresolvable_parent_report "$mempath" "$pin")"
  fi

  # A prepared merge moved HEAD onto its authority, so a position read now
  # describes the preparation, not memory; the mid-merge report stands alone.
  gitlore_store_mid_merge "$mempath" && return 0

  head=$(git -C "$mempath" rev-parse HEAD)
  live=$(git -C "$mempath" rev-parse -q --verify refs/heads/live) || live="$head"
  auth="${remote:-$live}"
  position=$(gitlore_module_position "$mempath" "$auth")
  case "$position" in
    forked)
      add_report "gitlore: memory's HEAD has diverged from live — run /gitlore:push, which prepares the merge." ;;
    diverged)
      # The local tip is what the rewrite record is checked against.
      if git -C "$mempath" merge-base --is-ancestor "$live" "$head"; then tip=HEAD; else tip=live; fi
      rc=0
      out=$(gitlore_rewrite_hit "$mempath" "$auth" "$tip") || rc=$?
      case "$rc" in
        0) add_report "gitlore: upstream memory has diverged from live — run /gitlore:push to reconcile and publish it." ;;
        1)
          crossing=$(gitlore_cross_rewrite_script "$mempath")
          add_report "gitlore: memory's live holds commits its remote rewrote (record gitlore/rewrites: $out is superseded), so merging upstream memory would re-import the old history. Nothing was merged. Run $crossing to cross this store." ;;
        *)
          # git's text can carry remote-chosen lines, so it goes to the user only.
          add_sysmsg "gitlore: upstream memory's rewrite record gitlore/rewrites could not be fetched, so its divergence from live cannot be checked for rewritten history. git said: $(printf '%s' "$out" | tr '\n' ' ')"
          protocol_ctx="$protocol_ctx

gitlore: upstream memory's rewrite record gitlore/rewrites could not be fetched, so its divergence from live is unchecked; the user has git's message."
          ;;
      esac ;;
    ahead)
      if git -C "$mempath" merge-base --is-ancestor "$live" "$head"; then tip="$head"; else tip="$live"; fi
      n=$(git -C "$mempath" rev-list --count "$auth..$tip")
      if [ "$n" -eq 1 ]; then unit="commit"; else unit="commits"; fi
      if [ -n "$remote" ]; then
        add_report "gitlore: memory holds $n $unit its remote's live lacks — run /gitlore:push to publish."
      else
        add_report "gitlore: memory's HEAD is $n $unit ahead of live — run /gitlore:push."
      fi ;;
    behind)
      if [ "$live" != "$auth" ]; then
        n=$(git -C "$mempath" rev-list --count "$live..$auth")
        if [ "$n" -eq 1 ]; then unit="commit"; else unit="commits"; fi
        add_report "gitlore: $n upstream memory $unit — run /gitlore:merge: it fast-forwards, may record a canned commit, and needs no push."
      elif [ "$dirty" = "0" ]; then
        # Clean only: a dirty store is reported above, and /gitlore:merge is
        # what moves HEAD onto live once it is clean.
        n=$(git -C "$mempath" rev-list --count "$head..$live")
        if [ "$n" -eq 1 ]; then unit="commit"; else unit="commits"; fi
        add_report "gitlore: $n $unit on live not checked out here — run /gitlore:merge."
      fi ;;
    *)
      add_sysmsg "gitlore: memory in sync." ;;
  esac
}

# The root's mid-merge report: the command that completes the prepared merge
# and the one that aborts it, on both channels, as `cd "<repo>" && …` lines the
# agent runs verbatim. Both flavors complete through `continue-after-merge`.
# Args: $1 = memory worktree path.
report_memory_mid_merge() {
  local mempath="$1" repo root statefile cont abort
  repo=$(git rev-parse --show-toplevel)
  root="${PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-}}"
  statefile=$(gitlore_merge_state_file "$mempath")
  cont="cd \"$repo\" && bash \"$root/scripts/resolve.sh\" continue-after-merge"
  abort="cd \"$repo\" && bash \"$root/scripts/resolve.sh\" abort-merge"
  add_sysmsg "gitlore: memory holds a prepared merge that has not landed. To land it, resolve and stage the merged files, then run:
  $cont
To abort it and put memory back on the commit the merge started from, run:
  $abort"
  protocol_ctx="$protocol_ctx

gitlore: memory holds a prepared merge that has not landed; its state file is $statefile. Do not commit memory or start another take over it. To land it, dispatch the gitlore:memory-merger sub-agent with that state file; on approval of its synthesis it runs:
  $cont
To abort the merge instead, which restores memory to the commit it started from, run:
  $abort"
}
