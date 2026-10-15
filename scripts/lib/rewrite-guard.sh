#!/usr/bin/env bash
# The rewritten-history guard (D62): refuse a divergence whose local side sits
# on commits the remote rewrote, test a range against the `gitlore/rewrites`
# record, and print the crossing command a refusal names.
# Part of lib/resolve.sh; source that, not this file. SessionStart reaches
# gitlore_rewrite_hit and gitlore_cross_rewrite_script through it too.

# Refuse a divergence whose local side sits on rewritten history (D62), before
# any merge is prepared. Only an origin/* authority is checked, so a head-vs-live
# divergence fetches nothing. Returns 1 with the refusal on stderr; 0 when the
# yield may proceed.
# git's own text can carry remote-chosen lines, so only the user's copy of the
# fetch-failure message includes it.
# Args: $1 = memory worktree path, $2 = authority ref, $3 = pending ref.
gitlore_refuse_rewritten() {
  local mempath="$1" authority="$2" pending_ref="$3"
  local rc=0 out crossing
  case "$authority" in origin/*) ;; *) return 0 ;; esac
  out=$(gitlore_rewrite_hit "$mempath" "$authority" "$pending_ref") || rc=$?
  case "$rc" in
    0) return 0 ;;
    1)
      crossing=$(gitlore_cross_rewrite_script "$mempath")
      gitlore_say_for_agent_or_user \
        "gitlore: the local side of $mempath holds commits the remote rewrote (record gitlore/rewrites: $out is superseded). Merging against '$authority' would re-import the old history, so nothing was merged. Run $crossing to cross this store." \
        "gitlore: the local side of $mempath holds commits the remote rewrote (record gitlore/rewrites: $out is superseded). Merging against '$authority' would re-import the old history, so nothing was merged. Run $crossing to cross this store." >&2
      ;;
    *)
      gitlore_say_for_agent_or_user \
        "gitlore: the rewrite record gitlore/rewrites exists on origin but could not be fetched, so $mempath cannot be checked for superseded history. Nothing was merged. Run the command again once the remote is reachable. The user has git's message." \
        "gitlore: the rewrite record gitlore/rewrites exists on origin but could not be fetched, so $mempath cannot be checked for superseded history. Nothing was merged. Run the command again once the remote is reachable. git said: $out" >&2
      ;;
  esac
  return 1
}

# Test a divergence for rewritten history (D62). The record `gitlore/rewrites`
# on origin maps old commit ids (first column) to new ones; a commit in
# authority..pending whose id is a key is superseded history, and merging it
# would re-import the old line. Key membership only: chains are not followed.
# The record is fetched by explicit refspec with --no-write-fetch-head, so no
# other remote branch (the archive branches included) reaches the store and
# FETCH_HEAD keeps what the caller read from it. Prints nothing itself.
# Returns 0 for no hit, an absent record, or no origin; 1 with the superseded
# id on stdout; 2 with git's error on stdout when the record is advertised but
# cannot be fetched, or the range or map cannot be read.
# Args: $1 = store path, $2 = authority ref or sha, $3 = pending ref.
gitlore_rewrite_hit() {
  local store="$1" authority="$2" pending="$3"
  local fetch_err mine map hit
  [ -n "$(git -C "$store" config --get remote.origin.url)" ] || return 0
  if ! fetch_err=$(git -C "$store" fetch -q --no-write-fetch-head origin +refs/heads/gitlore/rewrites:refs/gitlore/rewrites 2>&1); then
    case "$fetch_err" in
      *"couldn't find remote ref"*) return 0 ;;
    esac
    printf '%s' "$fetch_err"
    return 2
  fi
  if ! mine=$(git -C "$store" rev-list "$authority..$pending" 2>&1); then
    printf '%s' "$mine"
    return 2
  fi
  if ! map=$(git -C "$store" show refs/gitlore/rewrites:map 2>&1); then
    printf '%s' "$map"
    return 2
  fi
  # Both lists go in on stdin, never through the environment: a rewrite that
  # changed the root leaves thousands of ids in $mine, past the per-string
  # limit of exec (E2BIG), and a failed awk would read as "no hit". No early
  # exit either, so a large map is read to its end and printf takes no SIGPIPE.
  hit=$({ printf '%s\n' "$mine"; printf '%s\n' '--'; printf '%s\n' "$map"; } | awk '
    $0 == "--" { in_map = 1; next }
    !in_map { if (NF) mine[$1] = 1; next }
    NF && !found && ($1 in mine) { print $1; found = 1 }') \
    || { printf 'the record could not be compared with the local commits'; return 2; }
  [ -n "$hit" ] || return 0
  printf '%s' "$hit"
  return 1
}

# The crossing command for a message, runnable as printed: the script's path,
# absolute when the plugin root is known, and the store it crosses.
# Args: $1 = store path.
gitlore_cross_rewrite_script() {
  local root="${PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-}}"
  printf '"%s" "%s"\n' "${root:+$root/}scripts/cross-rewrite.sh" "$1"
}
