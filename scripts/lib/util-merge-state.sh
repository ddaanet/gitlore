#!/usr/bin/env bash
# Where a store's merge state lives, and whether there is one: the gitdir paths
# of the merge-state file and its read-only briefing artifacts, their single
# remover, the mid-merge predicates a commit path orders its own work behind,
# and the dirty-forked-root predicate the take refuses on and the pin guard
# yields on.
# Part of util.sh; source that, not this file. Function-only (safe to source
# twice, unlike util.sh), so definition order between the two files does not
# matter.
#
# The state's IO and the merge itself — writing the marker and the full state
# file and emitting the merger directive — is resolve-merge-state.sh instead,
# and preparing the merge is resolve-merge-prepare.sh. The cut is reachability
# rather than subject:
# what is here is what a caller that never sources resolve.sh can reach, which
# is why gitlore_store_mid_merge exists beside gitlore_detect_stale_merge_state
# rather than inside it.

# Print abs path to the memory submodule's merge-state file.
# Resolves through the submodule's gitdir correctly.
# Args: $1 = memory path (working tree).
gitlore_merge_state_file() {
  local mempath="$1"
  git -C "$mempath" rev-parse --git-path gitlore-merge-state
}

# Print abs path to one of the merge's read-only briefing artifacts — the two
# side diffs and the store's file tree, written at prepare time for the merger
# sub-agent. They live beside the state file in the gitdir, so they are invisible
# to `git status` and need no `.gitignore` entry, and they are named in the state
# file rather than reconstructed: the sub-agent runs no git of its own beyond
# `add`. Args: $1 = memory path, $2 = artifact suffix (mine.diff, theirs.diff, tree).
gitlore_merge_artifact_file() {
  git -C "$1" rev-parse --git-path "gitlore-merge-$2"
}

# Remove the merge state file and every artifact that was written with it.
# One remover, so a continuation cannot drop the state and leave the briefing
# behind for the next merge to be read against. Args: $1 = memory path.
gitlore_clear_merge_state() {
  local mempath="$1" name
  rm -f "$(gitlore_merge_state_file "$mempath")"
  for name in mine.diff theirs.diff tree; do
    rm -f "$(gitlore_merge_artifact_file "$mempath" "$name")"
  done
}

# Exit 0 when a store holds an unfinished merge — a merge-state file, a
# MERGE_HEAD, or both. This is gitlore_detect_stale_merge_state's "clean"
# outcome inverted, without its classification of the other three: a caller that
# only needs to order a merge ahead of its own work lives outside resolve.sh
# (index-compose-check.sh, which resolve.sh sources) and cannot reach that
# function.
#
# Kept rather than replaced by gitlore_any_store_mid_merge below: a caller that
# asks about one *named* store still needs this one. index-compose-check.sh runs
# its own per-tier loop and reports which tier is mid-merge, which the composed
# predicate's single yes/no cannot tell it.
# Args: $1 = store worktree path.
gitlore_store_mid_merge() {
  local store="$1"
  [ -f "$(gitlore_merge_state_file "$store")" ] && return 0
  # `-q --verify` is silent on the expected miss: no merge in progress.
  git -C "$store" rev-parse -q --verify MERGE_HEAD >/dev/null
}

# Exit 0 when the memory store or any mounted tier holds an unfinished merge —
# a tier's merge lives in the tier's own gitdir, not the root's. Skips an
# unmaterialized tier, where `git -C` answers for the enclosing repo instead.
#
# The loop reads gitlore_tier_paths — every mounted tier — and not
# gitlore_active_tiers, the manifest subset. What it orders against is
# gitlore_sync_tiers_to_live, which commits inside a mounted-but-unlisted tier
# too, so tightening the loop to the manifest would leave a dormant tier's
# prepared merge invisible to every screen, with the suite still green.
# Args: $1 = memory worktree path — the root store, NOT a tier. Passed a tier
# path, this loops over that tier's own (absent) submodules and answers for it
# alone: the root-only read it exists to replace, silently, at a call that reads
# as correct.
gitlore_any_store_mid_merge() {
  local mempath="$1" tier
  gitlore_store_mid_merge "$mempath" && return 0
  while IFS= read -r tier; do
    [ -n "$tier" ] || continue
    [ -e "$mempath/$tier/.git" ] || continue
    gitlore_store_mid_merge "$mempath/$tier" && return 0
  done < <(gitlore_tier_paths "$mempath")
  return 1
}

# Exit 0 when /gitlore:merge refuses the memory root $1 before it moves any
# store: root holds uncommitted work a take counts, and its HEAD has forked
# from its local `live`, each holding commits the other lacks, so its merge
# cannot be prepared until that work is committed. A HEAD or `live` that cannot
# be read is no fork. Read by the take's own refusal (gitlore_take_tiers), the
# yield's refusal of a tier merge on such a root, and the pin guard's yield
# (gitlore_pin_yield_tiers), which all have to agree on the state; it lives here
# because the guard runs in callers that never source resolve.sh.
# Args: $1 = memory worktree path.
gitlore_root_merge_refused() {
  local root="$1" head live
  head=$(git -C "$root" rev-parse -q --verify HEAD) || return 1
  live=$(git -C "$root" rev-parse -q --verify live) || return 1
  git -C "$root" merge-base --is-ancestor "$head" "$live" && return 1
  git -C "$root" merge-base --is-ancestor "$live" "$head" && return 1
  [ "$(gitlore_store_dirty_for_take "$root" "")" = "1" ]
}

# Print 1 when a store holds uncommitted work a take must not move over, 0
# otherwise. For the memory root that leaves out a tier gitlink moved in the
# worktree: tiers move first by design, and the root merge records their HEADs
# through the prepare. A staged gitlink counts: it is root's record of a tier
# it has seen (D78), which must reach a commit, and git's merge refuses a
# staged entry in any case.
# Args: $1 = store worktree, $2 = tier name ("" = the memory root).
gitlore_store_dirty_for_take() {
  local store="$1" tier="$2"
  if [ -n "$tier" ]; then
    gitlore_memory_dirty "$store"
  elif [ -z "$(git -C "$store" status --porcelain --ignore-submodules=all)" ] \
    && git -C "$store" diff --cached --quiet; then
    printf '0\n'
  else
    printf '1\n'
  fi
}

# Exit 0 when /gitlore:merge refuses tier $2 of memory root $1 before it moves
# any store (gitlore_refuse_dirty_tiers): the tier holds uncommitted changes and
# has something to take. Read by that refusal and by the pin guard's yield
# (gitlore_pin_yield_tiers), which have to agree on the state.
# Args: $1 = memory worktree path, $2 = tier name.
gitlore_tier_take_refused() {
  local tierpath="$1/$2"
  [ -e "$tierpath/.git" ] || return 1
  [ "$(gitlore_memory_dirty "$tierpath")" = "1" ] || return 1
  gitlore_tier_has_arrivals "$tierpath"
}

# Fetch the remote's `live` into tier $1, at most once per process. The outcome
# is recorded in the memo file the entry script names in GITLORE_FETCH_MEMO,
# which subshells share (gitlore_fetch_memo_note); with no memo file set every
# call fetches. A memo that cannot be written costs only a repeated fetch. A
# non-empty GITLORE_NO_FETCH makes no fetch and answers success, so the caller
# reads the remote-tracking ref as it was last fetched. Exit 0 when the fetch
# succeeded.
# Args: $1 = tier worktree.
gitlore_tier_fetch_memoized() {
  local tierpath="$1" memo="${GITLORE_FETCH_MEMO:-}"
  [ -z "${GITLORE_NO_FETCH:-}" ] || return 0
  if [ -n "$memo" ] && [ -f "$memo" ]; then
    grep -qFx -- "ok $tierpath" "$memo" && return 0
    grep -qFx -- "failed $tierpath" "$memo" && return 1
  fi
  # The output is dropped because failure is an answer here, and the publish
  # that follows reports the same remote in its own words.
  if gitlore_fetch_bounded "$tierpath" -q --no-recurse-submodules origin live; then
    gitlore_fetch_memo_note ok "$tierpath"
    return 0
  fi
  gitlore_fetch_memo_note failed "$tierpath"
  return 1
}

# Record in the fetch memo that the fetch of tier $2 ended `ok` or `failed` ($1),
# so gitlore_tier_fetch_memoized answers from it. A timed-out fetch is `failed`.
# Args: $1 = ok|failed, $2 = tier worktree.
gitlore_fetch_memo_note() {
  local memo="${GITLORE_FETCH_MEMO:-}"
  [ -z "$memo" ] || printf '%s %s\n' "$1" "$2" >> "$memo" || true
}

# Run `git -C $1 fetch $2...`, bounded by GITLORE_FETCH_TIMEOUT seconds when that
# is a positive integer (gitlore_fetch_timeout_ok) and unbounded otherwise. Its
# stdout and stderr land in GITLORE_FETCH_OUT. Exit status is git's, or 124 when
# the timeout killed the fetch.
#
# The fetch runs as a background job of a subshell under `set -m`, which gives
# it a process group of its own, and a watchdog job (its own group too) sleeps
# the timeout and then signals the fetch's whole group, so the ssh transport
# dies with git. Once the fetch ends the watchdog's group is killed, sleeper
# included, so nothing outlives the call and an early finish waits for nothing.
# Args: $1 = tier or memory worktree, $2... = fetch arguments.
# shellcheck disable=SC2034 # GITLORE_FETCH_OUT is read by the callers
gitlore_fetch_bounded() {
  local dir="$1" secs="${GITLORE_FETCH_TIMEOUT:-}" tmp rc=0
  shift
  GITLORE_FETCH_OUT=""
  if ! gitlore_fetch_timeout_ok "$secs" ||
     ! tmp=$(mktemp -d "${TMPDIR:-/tmp}/gitlore-fetch.XXXXXX"); then
    GITLORE_FETCH_OUT=$(git -C "$dir" fetch "$@" 2>&1) || rc=$?
    return "$rc"
  fi
  # The subshell's own stdout and stderr are dropped: job control prints
  # "Terminated" notices for the jobs it kills, and the watchdog must not hold
  # the caller's pipes. The fetch's output goes to a file.
  (
    set -m
    r=0
    git -C "$dir" fetch "$@" >"$tmp/out" 2>&1 &
    fpid=$!
    { sleep "$secs"; : > "$tmp/timeout"; kill -TERM -- "-$fpid"; } &
    wpid=$!
    wait "$fpid" || r=$?
    kill -TERM -- "-$wpid" || true
    wait "$wpid" || true
    if [ "$r" -eq 143 ] && [ -e "$tmp/timeout" ]; then exit 124; fi
    exit "$r"
  ) >/dev/null 2>&1 || rc=$?
  GITLORE_FETCH_OUT=$(cat "$tmp/out")
  rm -rf "$tmp"
  return "$rc"
}

# Exit 0 when $1 is a usable fetch timeout: a positive integer, all digits with
# at least one of them non-zero. Anything else (empty, 0, 00, abc, -1, 1.5)
# would make `sleep` return at once or fail and kill every fetch.
# Args: $1 = candidate GITLORE_FETCH_TIMEOUT value.
gitlore_fetch_timeout_ok() {
  case "$1" in
    ''|*[!0-9]*) return 1 ;;
    *[1-9]*) return 0 ;;
  esac
  return 1
}

# True when a tier's HEAD does not contain its local `live` or its remote's
# `live`: ahead of HEAD, forked from it or diverged, each is something to take.
# Args: $1 = tier worktree.
gitlore_tier_has_arrivals() {
  local tierpath="$1" live remote
  # `-q --verify` is silent on the expected miss: a tier never fetched has no
  # local `live`.
  if live=$(git -C "$tierpath" rev-parse -q --verify live) &&
     ! git -C "$tierpath" merge-base --is-ancestor "$live" HEAD; then
    return 0
  fi
  gitlore_tier_fetch_memoized "$tierpath" || return 1
  remote=$(git -C "$tierpath" rev-parse -q --verify refs/remotes/origin/live) || return 1
  ! git -C "$tierpath" merge-base --is-ancestor "$remote" HEAD
}
