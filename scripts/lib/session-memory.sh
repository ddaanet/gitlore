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

# A report whose two channels differ: $1 to the user, $2 to the agent. For a
# line carrying text a remote or a contributor chose (a url, git's own output),
# which the user reads and the agent does not need.
add_report_each() {
  add_sysmsg "$1"
  protocol_ctx="$protocol_ctx

$2"
}

# Add store $1 with position word $2 (`in sync`, `N ahead`, `N behind`,
# `diverged`, `unreachable`) to the session line, which the hook emits once
# after every store has reported. The line's command is /gitlore:push when any
# store is ahead or diverged, else /gitlore:merge when any is behind, else none.
# Args: $1 = store name, $2 = position word.
gitlore_line_add() {
  gitlore_line_stores="${gitlore_line_stores:+$gitlore_line_stores; }$1 $2"
  case "$2" in
    diverged|*ahead) gitlore_line_cmd=push ;;
    *behind) [ "$gitlore_line_cmd" = push ] || gitlore_line_cmd=merge ;;
  esac
}

# Print the N of a store's `N ahead` / `N behind`, against authority commit $2
# for position $3 (`ahead` or `behind`). Ahead counts the commits the store
# holds, HEAD or local `live` whichever is further, that the authority lacks.
# Behind counts the authority's commits HEAD lacks, or when HEAD lacks none,
# those local `live` lacks.
# Args: $1 = store worktree path, $2 = authority sha, $3 = position.
gitlore_line_count() {
  local store="$1" auth="$2" pos="$3" head live tip n
  head=$(git -C "$store" rev-parse HEAD)
  live=$(git -C "$store" rev-parse -q --verify refs/heads/live) || live="$head"
  if [ "$pos" = ahead ]; then
    if git -C "$store" merge-base --is-ancestor "$live" "$head"; then tip="$head"; else tip="$live"; fi
    git -C "$store" rev-list --count "$auth..$tip"
  else
    n=$(git -C "$store" rev-list --count "$head..$auth")
    [ "$n" -gt 0 ] || n=$(git -C "$store" rev-list --count "$live..$auth")
    printf '%s\n' "$n"
  fi
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
# own local `live` otherwise (no remote, a remote with no `live` yet); a failed
# fetch makes the store `unreachable`. The position goes to the session line
# (gitlore_line_add), not to a report of its own. Then the parent's pin on memory, when memory does not hold it. Reads
# only: nothing here moves HEAD, the worktree or any local branch.
# Args: $1 = memory worktree path.
report_memory_position() {
  local mempath="$1" dirty=0 head live auth remote_url fetch_err remote="" fetched=1
  local position tip rc out crossing pin timed_out mid=0
  gitlore_store_mid_merge "$mempath" && mid=1
  if [ "$mid" -eq 1 ]; then
    report_memory_mid_merge "$mempath"
  else
    dirty=$(gitlore_memory_dirty "$mempath")
    [ "$dirty" = "1" ] && add_report "gitlore: memory — uncommitted changes present."
  fi

  # Remote: a read-only fetch of `live`, and only for a real remote. The
  # placeholder (or no origin at all) is a local-only install with nothing to
  # ask, and a remote that has no `live` yet has nothing upstream; both read
  # against local `live` and add no message. Any other fetch failure is named,
  # with git's own reason, ahead of the session line.
  remote_url=$(git -C "$mempath" config --get remote.origin.url || true)
  if [ -n "$remote_url" ] && ! gitlore_is_placeholder_url "$remote_url"; then
    rc=0
    # The match below reads git's English text, so this fetch runs under the C locale.
    LC_ALL=C gitlore_fetch_bounded "$mempath" -q origin live || rc=$?
    fetch_err="$GITLORE_FETCH_OUT"
    if [ "$rc" -eq 0 ]; then
      remote=$(git -C "$mempath" rev-parse -q --verify refs/remotes/origin/live) || remote=""
    else
      case "$fetch_err" in
        *"couldn't find remote ref"*) ;;
        *)
          fetched=0
          if [ "$rc" -eq 124 ]; then
            timed_out="gitlore: could not fetch memory's remote 'live' (timed out after ${GITLORE_FETCH_TIMEOUT}s), so upstream memory is unknown."
            add_report_each "$timed_out" "$timed_out"
          else
            # git's stderr can carry text the remote chose (`remote: …` lines),
            # so it goes to the user only; the agent's context gets the fixed
            # sentence.
            add_report_each "gitlore: could not fetch memory's remote 'live', so upstream memory is unknown. git said: $(printf '%s' "$fetch_err" | tr '\n' ' ')" \
              "gitlore: could not fetch memory's remote 'live', so upstream memory is unknown; the user has git's message."
          fi
          ;;
      esac
    fi
  fi

  # The parent's pin, once the fetch has had its chance to bring the commit. A
  # failed fetch cannot tell an unfetched commit from a lost one.
  if [ "$fetched" -eq 1 ]; then
    pin=$(gitlore_parent_pin_absent "$mempath")
    [ -n "$pin" ] && add_report_each "$(gitlore_unresolvable_parent_report "$mempath" "$pin" user)" \
      "$(gitlore_unresolvable_parent_report "$mempath" "$pin" agent)"
  fi

  # A prepared merge moved HEAD onto its authority, so a position read now
  # describes the preparation, not memory; the mid-merge report stands alone.
  [ "$mid" -eq 1 ] && return 0
  if [ "$fetched" -eq 0 ]; then gitlore_line_add memory unreachable; return 0; fi

  head=$(git -C "$mempath" rev-parse HEAD)
  live=$(git -C "$mempath" rev-parse -q --verify refs/heads/live) || live="$head"
  auth="${remote:-$live}"
  position=$(gitlore_module_position "$mempath" "$auth")
  case "$position" in
    forked)
      gitlore_line_add memory diverged ;;
    diverged)
      # The local tip is what the rewrite record is checked against.
      if git -C "$mempath" merge-base --is-ancestor "$live" "$head"; then tip=HEAD; else tip=live; fi
      rc=0
      out=$(gitlore_rewrite_hit "$mempath" "$auth" "$tip") || rc=$?
      case "$rc" in
        0) gitlore_line_add memory diverged ;;
        1)
          crossing=$(gitlore_cross_rewrite_script "$mempath")
          add_report "gitlore: memory's live holds commits its remote rewrote (record gitlore/rewrites: $out is superseded), so merging upstream memory would re-import the old history. Nothing was merged. Run $crossing to cross this store." ;;
        3)
          timed_out="gitlore: upstream memory's rewrite record gitlore/rewrites could not be fetched (timed out after ${GITLORE_FETCH_TIMEOUT}s), so its divergence from live is unchecked."
          add_report_each "$timed_out" "$timed_out" ;;
        *)
          # git's text can carry remote-chosen lines, so it goes to the user only.
          add_report_each "gitlore: upstream memory's rewrite record gitlore/rewrites could not be fetched, so its divergence from live cannot be checked for rewritten history. git said: $(printf '%s' "$out" | tr '\n' ' ')" \
            "gitlore: upstream memory's rewrite record gitlore/rewrites could not be fetched, so its divergence from live is unchecked; the user has git's message."
          ;;
      esac ;;
    ahead|behind)
      gitlore_line_add memory "$(gitlore_line_count "$mempath" "$auth" "$position") $position" ;;
    *)
      gitlore_line_add memory "in sync" ;;
  esac
}

# The root's mid-merge report: the command that completes the prepared merge
# and the one that aborts it, on both channels, as `cd "<repo>" && …` lines the
# agent runs verbatim. Both flavors complete through `continue-after-merge`. A
# MERGE_HEAD with no state file is a merge gitlore did not prepare — a hand-run
# `git merge`, or an agent asked to merge by hand; gitlore writes the state
# file before its own preparation starts (gitlore_yield_merge), so a push
# killed mid-way leaves one — which neither command can read: that report
# gives what /gitlore:resolve gives the same store — look, then undo it — and
# names no state file.
# Args: $1 = memory worktree path.
report_memory_mid_merge() {
  local mempath="$1" repo root statefile cont abort mh look undo
  repo=$(git rev-parse --show-toplevel)
  root="${PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-}}"
  statefile=$(gitlore_merge_state_file "$mempath")
  if [ ! -f "$statefile" ]; then
    mh=$(git -C "$mempath" rev-parse -q --verify MERGE_HEAD)
    look="cd \"$repo\" && git -C \"$mempath\" status --short"
    undo="cd \"$repo\" && git -C \"$mempath\" merge --abort"
    add_report_each "gitlore: memory holds a merge gitlore did not prepare (MERGE_HEAD ${mh:0:12}, no merge state file), so nothing was changed. Finish it or undo it in the store:
  $look
  $undo" \
      "gitlore: memory holds a merge gitlore did not prepare (MERGE_HEAD ${mh:0:12}, no merge state file). Do not commit memory or start another take over it. It may hold work in progress: look first, and undo it only if the user confirms:
  $look
  $undo"
    return 0
  fi
  cont="cd \"$repo\" && bash \"$root/scripts/resolve.sh\" continue-after-merge"
  abort="cd \"$repo\" && bash \"$root/scripts/resolve.sh\" abort-merge"
  # A merge the continuation cannot land as it stands — MERGE_HEAD cleared by a
  # checkout, or a marker whose preparation died before its briefing — goes to
  # /gitlore:resolve, whose guard repairs both; the hook itself repairs nothing.
  if ! git -C "$mempath" rev-parse -q --verify MERGE_HEAD >/dev/null \
     || ! jq -e 'has("changed_files")' "$statefile" >/dev/null 2>&1; then
    add_report_each "gitlore: memory holds a merge that gitlore prepared but that cannot be landed as it stands. Run /gitlore:resolve to repair and land it. To abort it and put memory back on the commit the merge started from, run:
  $abort" \
      "gitlore: memory holds an unfinished merge whose state needs repair before it can land; its state file is $statefile. Do not commit memory or start another take over it. Run /gitlore:resolve to repair and land it. To abort the merge instead, which restores memory to the commit it started from, run:
  $abort"
    return 0
  fi
  add_report_each "gitlore: memory holds a prepared merge that has not landed. To land it, resolve and stage the merged files, then run:
  $cont
To abort it and put memory back on the commit the merge started from, run:
  $abort" \
    "gitlore: memory holds a prepared merge that has not landed; its state file is $statefile. Do not commit memory or start another take over it. To land it, dispatch the gitlore:memory-merger sub-agent with that state file; on approval of its synthesis it runs:
  $cont
To abort the merge instead, which restores memory to the commit it started from, run:
  $abort"
}
