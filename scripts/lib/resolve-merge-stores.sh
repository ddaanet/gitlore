#!/usr/bin/env bash
# Take whatever each store's remote is holding, without publishing anything:
# every tier first, then memory — the counterpart of gitlore_push_stores.
# Part of lib/resolve.sh; source that, not this file.

# Take whatever each store's remote is holding, without publishing anything:
# every mounted tier first, then memory, then one write of root's index. The
# counterpart of gitlore_push_stores, and the only path by which a pinned tier
# advances (D17) — SessionStart names an upstream-ahead tier, this is what acts
# on it.
#
# Each store reconciles its HEAD against its local `live` immediately before its
# take, so a root merge is only ever prepared with every tier already moved: the
# prepare records the tier's HEAD and the merger is asked nothing about a gitlink.
#
# The memory root alone also takes its own local `live` (D59): one that strictly
# contains HEAD — commits another checkout of the store made — is checked out
# detached when the store is clean, and reported and left alone when it is dirty.
# That move comes before the remote comparison below, which reads HEAD.
#
# Three outcomes per store, decided by ancestry against the fetched `origin/live`:
#
#   - the remote is already contained in HEAD → nothing to take. Local commits
#     awaiting publication are /gitlore:push's business, not this one's.
#   - HEAD is an ancestor of the remote → take it by fast-forward. No sub-agent —
#     nothing is in dispute, and spending a synthesis on a fast-forward would
#     make taking upstream facts expensive enough to skip.
#   - neither contains the other → prepare a merge and yield, exactly as a
#     refused push does, but marked not-to-publish.
#
# A dirty tier with something to take refuses the whole take before anything
# moves: the working tree may hold this session's uncommitted facts, and a
# fast-forward would either fail mid-way or carry them onto a commit nobody
# approved them against. A dirty tier with nothing to take blocks nothing.
#
# Returns 0 when every store is reconciled (nothing-to-take included), 1 after
# emitting a message otherwise — including the prepared-merge directive.
# Args: $1 = memory worktree path.
gitlore_merge_stores() {
  local mempath="$1"

  gitlore_guard_every_store "$mempath" || return 1
  gitlore_take_tiers "$mempath" || return 1

  gitlore_reconcile_one "$mempath" memory || return 1
  gitlore_merge_one_store "$mempath" "$mempath" "" || return 1

  # After root's own take, so what it writes sits on top of whatever upstream
  # root already recorded instead of meeting it as a divergence.
  gitlore_compose_moved_tiers "$mempath"
}

# The preflight of every take and every publish, run before either moves, pushes
# or prepares anything: answer a half-finished merge in any store, then refuse a
# dirty tier that has something to take.
# Args: $1 = memory worktree path.
gitlore_guard_every_store() {
  local mempath="$1" store
  while IFS= read -r store; do
    gitlore_guard_stale_merge_state "$store" || return 1
  done < <(gitlore_memory_stores "$mempath")
  gitlore_refuse_dirty_tiers "$mempath"
}

# Print 1 when a store holds uncommitted work a take must not move over, 0
# otherwise. For the memory root that leaves out every tier gitlink: tiers move
# first by design, and the root merge records their HEADs through the prepare.
# Args: $1 = store worktree, $2 = tier name ("" = the memory root).
gitlore_store_dirty_for_take() {
  local store="$1" tier="$2"
  if [ -n "$tier" ]; then
    gitlore_memory_dirty "$store"
  elif [ -z "$(git -C "$store" status --porcelain --ignore-submodules=all)" ]; then
    printf '0\n'
  else
    printf '1\n'
  fi
}

# One store's take. Args: $1 = memory worktree, $2 = store worktree,
# $3 = tier name ("" when the store IS the memory root).
gitlore_merge_one_store() {
  local mempath="$1" store="$2" tier="$3"
  local label remote_url fetched=0 fetch_err="" remote="" live head adopt_rc=0
  local live_ahead_dirty=0 n unit ff_err

  if [ -n "$tier" ]; then label="tier '$tier'"; else label="memory"; fi

  remote_url=$(git -C "$store" config --get remote.origin.url || true)
  if [ -z "$remote_url" ] || gitlore_is_placeholder_url "$remote_url"; then
    remote_url=""
  elif fetch_err=$(git -C "$store" fetch -q --no-recurse-submodules origin live 2>&1); then
    fetched=1
    remote=$(git -C "$store" rev-parse -q --verify refs/remotes/origin/live) || remote=""
  else
    # git refuses to fetch a ref the remote lacks, so a remote with no `live`
    # yet is read off that refusal: the expected miss, not a failed fetch.
    case "$fetch_err" in
      *"couldn't find remote ref"*) fetched=1 ;;
    esac
  fi

  # A tier's local `live` ahead of HEAD holds commits the ancestry tests below
  # cannot see, since they read HEAD, so those commits are adopted first —
  # unless the fetched remote already contains `live`. Then the fast-forward
  # takes origin's commits instead, including a repair of the same arrival that
  # another consumer already published, which adopting the stale copy would
  # repair a second time and diverge from. No remote, a failed fetch and a
  # remote with no `live` all adopt: nothing else here reaches those commits. A
  # failed adoption has reported itself, and the remote's report still follows,
  # so neither problem hides the other.
  live=$(git -C "$store" rev-parse -q --verify live) || live=""
  if [ -z "$remote" ] || [ -z "$live" ] || ! git -C "$store" merge-base --is-ancestor "$live" "$remote"; then
    gitlore_adopt_advanced_live "$mempath" "$store" "$tier" || adopt_rc=1
  fi

  # The memory root only (D59): a local `live` that strictly contains HEAD is
  # what HEAD catches up to before the remote take reads it. A clean store is
  # moved onto it and says so; a dirty one is left where it is and says why. The
  # remote take then skips its "already holds everything" line, which would
  # claim a store finished that is not.
  live_ahead_dirty=0
  if [ -z "$tier" ] && gitlore_live_ahead_of_head "$store"; then
    if [ "$(gitlore_store_dirty_for_take "$store" "")" = "1" ]; then
      n=$(git -C "$store" rev-list --count HEAD..live)
      if [ "$n" -eq 1 ]; then unit="commit"; else unit="commits"; fi
      printf 'gitlore: memory has uncommitted changes, so HEAD was not moved onto live (%s %s ahead) — commit memory, then run /gitlore:merge again.\n' "$n" "$unit"
      live_ahead_dirty=1
    else
      if ! ff_err=$(gitlore_git -C "$store" checkout -q --detach live 2>&1); then
        gitlore_say_for_agent_or_user \
          "gitlore: $label — its local 'live' is ahead of HEAD, but HEAD could not be moved onto it. git said:
$ff_err" \
          "gitlore: $label — its local 'live' is ahead of HEAD, but HEAD could not be moved onto it. git said:
$ff_err" >&2
        return 1
      fi
      printf 'gitlore: %s — fast-forwarded HEAD onto its local live, to %s.\n' \
        "$label" "$(git -C "$store" rev-parse --short HEAD)"
    fi
  fi

  if [ -z "$remote_url" ]; then
    # A tier exists to be shared, so one with no remote is a misconfiguration
    # worth stopping on. The memory root is not: a local-only install is a
    # supported end state (D20), and there is genuinely nothing to take.
    if [ -z "$tier" ]; then
      printf 'gitlore: memory has no remote of its own; nothing to take.\n'
      return 0
    fi
    gitlore_say_for_agent_or_user \
      "gitlore: $label has no remote configured, so there is nothing to take. Mount it against a remote or unmount it." \
      "gitlore: $label has no remote configured, so there is nothing to take." >&2
    return 1
  fi
  if [ "$fetched" -eq 0 ]; then
    gitlore_say_for_agent_or_user \
      "gitlore: could not fetch $label from its remote. git said:
$fetch_err" \
      "gitlore: could not fetch $label from its remote. git said:
$fetch_err" >&2
    return 1
  fi
  if [ -z "$remote" ]; then
    printf 'gitlore: %s — its remote has no '\''live'\'' branch yet; nothing to take.\n' "$label"
    return "$adopt_rc"
  fi
  [ "$adopt_rc" -eq 0 ] || return 1
  head=$(git -C "$store" rev-parse HEAD) || return 1

  if git -C "$store" merge-base --is-ancestor "$remote" "$head"; then
    # A dirty store whose live is ahead was reported above; nothing moved, so
    # there is nothing to reassure about.
    if [ "$live_ahead_dirty" -eq 1 ]; then return 0; fi
    # Nothing to take, which is not the same as nothing to do: this test reads
    # HEAD, and the ref a push sends is `live`. A store whose `live` was left
    # behind reaches exactly here and would otherwise be told it is finished.
    # Repair BEFORE the report, so the reassurance is never the first thing a
    # store about to fail on its refs is told.
    gitlore_repair_stranded_live "$store" "$label" || return 1
    printf 'gitlore: %s — already holds everything its remote does.\n' "$label"
    return 0
  fi

  if [ "$(gitlore_store_dirty_for_take "$store" "$tier")" = "1" ]; then
    gitlore_say_for_agent_or_user \
      "gitlore: $label has uncommitted changes, so its remote was left untouched. Commit them (approved summary, then a memory commit) and run /gitlore:merge again." \
      "gitlore: $label has uncommitted changes, so its remote was left untouched. Commit them and merge again." >&2
    return 1
  fi

  if ! git -C "$store" merge-base --is-ancestor "$head" "$remote"; then
    # Diverged. Same preparation a refused push yields, marked not-to-publish so
    # the continuation stops after the local `HEAD:live` fast-forward. Only a tier
    # inside a push keeps the publish: landing its merge sends the tier alone, and
    # a tier may go out ahead of what records it.
    if [ -n "$tier" ] && [ -n "${GITLORE_TAKE_IN_PUSH:-}" ]; then
      gitlore_yield_merge "$store" origin/live head-vs-remote HEAD || return 1
    else
      GITLORE_MERGE_NO_PUBLISH=1 gitlore_yield_merge "$store" origin/live head-vs-remote HEAD || return 1
    fi
    return 1
  fi

  # Root's own move carries gitlinks whose tiers were taken a moment ago. One no
  # repository holds is refused here, since a fast-forward never reaches the
  # prepare's check.
  if [ -z "$tier" ]; then
    gitlore_refuse_unresolvable_gitlinks "$mempath" "$remote" || return 1
  fi

  # Fast-forward: advance the local `live` (created here when the store never had
  # one), then move the working tree onto it. `push .` is ff-checked, so a race
  # that advanced `live` underneath us is refused rather than overwritten.
  if ! ff_err=$(gitlore_git -C "$store" push -q . "$remote:refs/heads/live" 2>&1); then
    gitlore_say_for_agent_or_user \
      "gitlore: $label — its local 'live' could not be advanced. git said:
$ff_err" \
      "gitlore: $label — its local 'live' could not be advanced. git said:
$ff_err" >&2
    return 1
  fi
  if ! ff_err=$(gitlore_git -C "$store" checkout -q --detach live 2>&1); then
    gitlore_say_for_agent_or_user \
      "gitlore: $label — its 'live' advanced but its working tree could not follow. git said:
$ff_err" \
      "gitlore: $label — its 'live' advanced but its working tree could not follow. git said:
$ff_err" >&2
    return 1
  fi
  printf 'gitlore: %s — fast-forwarded to %s\n' "$label" "$(git -C "$store" rev-parse --short HEAD)"
  return 0
}

# Advance a store's local `live` when it has been left strictly behind a HEAD
# that already contains it.
#
# A store rests DETACHED AT `live` (D17), so `live` behind a HEAD containing it
# can only mean `live` failed to keep up: every commit in HEAD arrived through a
# path that advances both, and no path produces a HEAD deliberately ahead. The
# move is therefore unambiguous where gitlore_check_head_live_agree's general
# case is not — local, ff-checked, publishing nothing — and it is invisible to a
# take's ancestry test, which reads HEAD alone. A failed merge preparation that
# checked HEAD out at `origin/live` and stopped leaves precisely this, and the
# store then reports itself finished on every subsequent merge while every push
# is refused.
#
# Runs ahead of the report every publish preflight and every take makes, because
# there is nothing here for a human to decide: a round-trip that can only end in
# the one command this already ran is a round-trip not worth asking for.
#
# Only that direction. `live` AHEAD of HEAD is a pin (D43) or a publication
# awaiting its push, both someone else's business; a genuine divergence is
# reported and not touched, since which ref was intended is not recoverable
# from the refs themselves.
# Args: $1 = store, $2 = label.
# Returns 1 after emitting when the two have diverged.
gitlore_repair_stranded_live() {
  local store="$1" label="$2" head live push_err
  # An unborn store has neither ref to reconcile.
  head=$(git -C "$store" rev-parse -q --verify HEAD) || return 0
  # No local `live` yet (a tier never fetched) — nothing to strand.
  live=$(git -C "$store" rev-parse -q --verify live) || return 0
  [ "$live" != "$head" ] || return 0
  if ! git -C "$store" merge-base --is-ancestor "$live" "$head"; then
    # `live` ahead of HEAD: left alone, deliberately. Written as an `if` rather
    # than a `&&` list because a failing left side of `cmd && return 0` is an
    # errexit trip, not a fall-through.
    if git -C "$store" merge-base --is-ancestor "$head" "$live"; then
      return 0
    fi
    gitlore_say_for_agent_or_user \
      "gitlore: $label — HEAD and its local 'live' have each moved since they last agreed (HEAD $(git -C "$store" rev-parse --short "$head"), live $(git -C "$store" rev-parse --short "$live")), so neither was moved. Run /gitlore:resolve to reconcile them." \
      "gitlore: $label — HEAD and its local 'live' have each moved since they last agreed (HEAD $(git -C "$store" rev-parse --short "$head"), live $(git -C "$store" rev-parse --short "$live")), so neither was moved. Run /gitlore:resolve to reconcile them." >&2
    return 1
  fi
  # `push .` is ff-checked, as on the fast-forward path: a race that advanced
  # `live` underneath us is refused rather than overwritten.
  if ! push_err=$(gitlore_git -C "$store" push -q . HEAD:refs/heads/live 2>&1); then
    gitlore_say_for_agent_or_user \
      "gitlore: $label — its local 'live' could not be advanced. git said:
$push_err" \
      "gitlore: $label — its local 'live' could not be advanced. git said:
$push_err" >&2
    return 1
  fi
  printf 'gitlore: %s — its local '\''live'\'' was stranded behind HEAD; advanced it to %s.\n' \
    "$label" "$(git -C "$store" rev-parse --short "$head")"
  return 0
}

# True when a store's local `live` holds commits its HEAD does not. Silent on
# every expected miss — an unborn store, a tier never fetched, refs that agree —
# so the callers below read as the question they are asking.
# Args: $1 = store.
gitlore_live_ahead_of_head() {
  local store="$1" head live
  head=$(git -C "$store" rev-parse -q --verify HEAD) || return 1
  live=$(git -C "$store" rev-parse -q --verify live) || return 1
  [ "$head" != "$live" ] || return 1
  git -C "$store" merge-base --is-ancestor "$head" "$live"
}

# Reconcile one store's checked-out branch with its local `live`, before its
# remote step (the take or the publish): fast-forward when HEAD is ahead of
# `live`, a prepared head-vs-live merge for `/gitlore:resolve` when the two have
# forked. A HEAD behind `live` is left to the take and the publish preflight,
# which own that direction.
# Returns 0 when the store agrees or was advanced, 1 after a merge was prepared,
# after a diverged store was refused for uncommitted changes, or when the store
# could not be advanced.
# Args: $1 = store worktree, $2 = label for messages.
gitlore_reconcile_one() {
  local store="$1" label="$2" live head push_err
  # A merge left dead by hand is disposed of, or a prepared one continued, before
  # anything here reads the refs: the take runs the same guard first.
  gitlore_guard_stale_merge_state "$store" || return 1
  # `-q --verify` is silent when `live` does not exist (never fetched).
  live=$(git -C "$store" rev-parse -q --verify live) || return 0
  head=$(git -C "$store" rev-parse HEAD)
  [ "$head" = "$live" ] && return 0
  case "$(gitlore_classify_refusal "$store" HEAD live)" in
    ahead)
      # The existing advance of a `live` stranded behind HEAD (the publish
      # preflights use the same one).
      gitlore_repair_stranded_live "$store" "$label" || return 1
      return 0
      ;;
    diverged)
      # The continuation commits with `add -A`, so uncommitted edits would ride
      # into the merge commit unapproved: refused first, as the take refuses.
      # A tier's own uncommitted edits do not ride the root merge, and a tier HEAD
      # off the gitlink this store records is what the prepare stages on purpose,
      # so tier paths do not count; untracked files do.
      if [ -n "$(git -C "$store" status --porcelain --ignore-submodules=all)" ]; then
        gitlore_say_for_agent_or_user \
          "gitlore: $label has uncommitted changes and its HEAD and local 'live' have diverged, so no merge was prepared. Commit them (approved summary, then a memory commit) and run /gitlore:merge or /gitlore:push again." \
          "gitlore: $label has uncommitted changes and its HEAD and local 'live' have diverged, so no merge was prepared. Commit them and try again." >&2
        return 1
      fi
      # The authority is `live`, the pending side is HEAD: the same preparation
      # the take uses for a diverged remote.
      gitlore_yield_merge "$store" live head-vs-live HEAD || return 1
      return 1
      ;;
  esac
  return 0
}
