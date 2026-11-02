#!/usr/bin/env bash
# The memory-position report stage of session-start.sh (D59). Sourced by
# session-start.sh only; its functions call session-start.sh's own `add_sysmsg`
# and append directly to its `$protocol_ctx` global — neither declared here,
# both left for session-start.sh to emit.

# A report line (D59) rides both channels: the user's systemMessage (D14) and
# the agent's additionalContext, the way tier lines are added.
add_report() {
  add_sysmsg "$1"
  protocol_ctx="$protocol_ctx

$1"
}
# Reports where memory stands against local `live` and its remote (D59). Reads
# only: nothing here moves HEAD, the worktree or any ref. Every position adds a
# line, so the systemMessage is never empty; a clean store that is aligned with
# `live` or ahead of it, and in step with its remote, adds only the user's
# "memory ready" confirmation, with nothing for the agent.
# Args: $1 = memory worktree path.
report_memory_position() {
  local mempath="$1" dirty head live n unit remote_url fetch_err remote rc out crossing
  dirty=$(gitlore_memory_dirty "$mempath")
  head=$(git -C "$mempath" rev-parse HEAD)
  live=$(git -C "$mempath" rev-parse -q --verify live)
  if [ "$dirty" = "1" ]; then
    add_report "gitlore: memory — uncommitted changes present."
  fi
  if [ "$head" = "$live" ]; then
    [ "$dirty" = "1" ] || add_sysmsg "gitlore: memory ready (detached at live)."
  elif gitlore_live_ahead_of_head "$mempath"; then
    # Clean only: a dirty store is reported above, and /gitlore:merge is what
    # moves HEAD onto live once it is clean.
    if [ "$dirty" = "0" ]; then
      n=$(git -C "$mempath" rev-list --count HEAD..live)
      if [ "$n" -eq 1 ]; then unit="commit"; else unit="commits"; fi
      add_report "gitlore: $n $unit on live not checked out here — run /gitlore:merge."
    fi
  elif git -C "$mempath" merge-base --is-ancestor live HEAD; then
    # HEAD is ahead of live: nothing for this session to take. Said to the user
    # only, so every state adds a line and the systemMessage is never empty.
    [ "$dirty" = "1" ] || add_sysmsg "gitlore: memory ready."
  else
    add_report "gitlore: memory diverged from live. Run /gitlore:resolve, then start a fresh session."
  fi

  # Remote: a read-only fetch of `live`, and only for a real remote. The
  # placeholder (or no origin at all) is a local-only install with nothing to
  # ask. A remote that has no `live` yet is silent — there is nothing upstream
  # to take — and any other fetch failure is named, with git's own reason.
  remote_url=$(git -C "$mempath" config --get remote.origin.url || true)
  if [ -z "$remote_url" ] || gitlore_is_placeholder_url "$remote_url"; then
    return 0
  fi
  if ! fetch_err=$(git -C "$mempath" fetch -q origin live 2>&1); then
    case "$fetch_err" in
      *"couldn't find remote ref"*) return 0 ;;
    esac
    # git's stderr can carry text the remote chose (`remote: …` lines), so it
    # goes to the user only; the agent's context gets the fixed sentence.
    add_sysmsg "gitlore: could not fetch memory's remote 'live', so upstream memory is unknown. git said: $(printf '%s' "$fetch_err" | tr '\n' ' ')"
    protocol_ctx="$protocol_ctx

gitlore: could not fetch memory's remote 'live', so upstream memory is unknown; the user has git's message."
    return 0
  fi
  remote=$(git -C "$mempath" rev-parse -q --verify refs/remotes/origin/live) || return 0
  live=$(git -C "$mempath" rev-parse -q --verify live) || return 0
  if [ "$remote" = "$live" ]; then
    return 0
  elif git -C "$mempath" merge-base --is-ancestor "$live" "$remote"; then
    n=$(git -C "$mempath" rev-list --count live.."$remote")
    if [ "$n" -eq 1 ]; then unit="commit"; else unit="commits"; fi
    add_report "gitlore: $n upstream memory $unit — run /gitlore:merge: it fast-forwards, may record a canned commit, and needs no push."
  elif git -C "$mempath" merge-base --is-ancestor "$remote" "$live"; then
    return 0 # local live is ahead of the remote: a push's business
  else
    rc=0
    out=$(gitlore_rewrite_hit "$mempath" origin/live live) || rc=$?
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
    esac
  fi
}
