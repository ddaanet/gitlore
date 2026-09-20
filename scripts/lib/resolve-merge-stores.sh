#!/usr/bin/env bash
# Take whatever each store's remote is holding, without publishing anything:
# every tier first, then memory — the counterpart of gitlore_push_stores.
# Part of lib/resolve.sh; source that, not this file.

# Take whatever each store's remote is holding, without publishing anything:
# every tier first, then memory. The counterpart of gitlore_push_stores, and the
# only path by which a pinned tier advances (D17) — SessionStart names an
# upstream-ahead tier, this is what acts on it.
#
# Three outcomes per store, decided by ancestry against the fetched `origin/live`:
#
#   - the remote is already contained in HEAD → nothing to take. Local commits
#     awaiting publication are /gitlore:push's business, not this one's.
#   - HEAD is an ancestor of the remote → take it by fast-forward, then ADOPT:
#     for a tier, its merged carrier becomes root's block for it. No sub-agent —
#     nothing is in dispute, and spending a synthesis on a fast-forward would
#     make taking upstream facts expensive enough to skip.
#   - neither contains the other → prepare a merge and yield, exactly as a
#     refused push does, but marked not-to-publish.
#
# A dirty store is refused rather than checked out over: the working tree may
# hold this session's uncommitted facts, and a fast-forward would either fail
# mid-way or carry them onto a commit nobody approved them against.
#
# Returns 0 when every store is reconciled (nothing-to-take included), 1 after
# emitting a message otherwise — including the prepared-merge directive.
# Args: $1 = memory worktree path.
gitlore_merge_stores() {
  local mempath="$1" tier tierpath

  gitlore_guard_stale_merge_state "$mempath" || return 1

  # Root FIRST, the mirror of the publish order (D49). Taking goes top-down
  # because the root commit arriving from upstream already records the tier
  # commits it names, all of them on the tier's own remote: taking it costs
  # nothing and leaves each tier merely behind. Tiers-first inverts that — the
  # tier take writes a bookkeeping commit of its own, which meets the upstream
  # root's equivalent commit as a DIVERGENCE and spends a synthesis on two
  # sides that recorded the same fast-forward. Publishing keeps the opposite
  # order for the opposite reason: a pointer must never go out ahead of what it
  # points at.
  gitlore_merge_one_store "$mempath" "$mempath" "" || return 1

  while IFS= read -r tier; do
    [ -n "$tier" ] || continue
    tierpath="$mempath/$tier"
    # `git -C` into an unchecked-out submodule walks up to the enclosing repo.
    [ -e "$tierpath/.git" ] || continue
    gitlore_guard_stale_merge_state "$tierpath" || return 1
    gitlore_merge_one_store "$mempath" "$tierpath" "$tier" || return 1
  done < <(gitlore_tier_paths "$mempath")

  return 0
}

# One store's reconcile. Args: $1 = memory worktree, $2 = store worktree,
# $3 = tier name ("" when the store IS the memory root, which adopts nothing —
# its own MEMORY.md moves with the fast-forward).
gitlore_merge_one_store() {
  local mempath="$1" store="$2" tier="$3"
  local label remote_url fetched=0 fetch_err="" remote="" live head adopt_rc=0
  local root_dirty_before

  if [ -n "$tier" ]; then label="tier '$tier'"; else label="memory"; fi

  remote_url=$(git -C "$store" config --get remote.origin.url || true)
  if [ -z "$remote_url" ] || gitlore_is_placeholder_url "$remote_url"; then
    remote_url=""
  elif fetch_err=$(git -C "$store" fetch -q origin live 2>&1); then
    fetched=1
    # `-q --verify` is silent on the expected miss: a remote with no `live` yet.
    remote=$(git -C "$store" rev-parse -q --verify refs/remotes/origin/live) || remote=""
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
    # Nothing to take, which is not the same as nothing to do: this test reads
    # HEAD, and the ref a push sends is `live`. A store whose `live` was left
    # behind reaches exactly here and would otherwise be told it is finished.
    # Repair BEFORE the report, so the reassurance is never the first thing a
    # store about to fail on its refs is told.
    gitlore_repair_stranded_live "$store" "$label" || return 1
    printf 'gitlore: %s — already holds everything its remote does.\n' "$label"
    return 0
  fi

  if [ "$(gitlore_memory_dirty "$store")" = "1" ]; then
    gitlore_say_for_agent_or_user \
      "gitlore: $label has uncommitted changes, so its remote was left untouched. Commit them (approved summary, then a memory commit) and run /gitlore:merge again." \
      "gitlore: $label has uncommitted changes, so its remote was left untouched. Commit them and merge again." >&2
    return 1
  fi

  if ! git -C "$store" merge-base --is-ancestor "$head" "$remote"; then
    # Diverged. Same preparation a refused push yields, marked not-to-publish so
    # the continuation stops after the local `HEAD:live` fast-forward.
    GITLORE_MERGE_NO_PUBLISH=1 gitlore_yield_merge "$store" origin/live head-vs-remote HEAD || return 1
    return 1
  fi

  # Read before anything moves: what matters is whether the root store already
  # held work the canned commit would sweep up. Asked of the paths OUTSIDE the
  # pair — a root whose own take just landed shows the tier lagging its new
  # gitlink, which is this pass's business rather than someone else's edit. Root
  # `MEMORY.md` is inside the pair on purpose: the adoption below rewrites it
  # whatever it held, so composition already owns that file (D31).
  root_dirty_before=$(gitlore_root_dirty_beyond_pair "$mempath" "$tier")

  # Fast-forward: advance the local `live` (created here when the store never had
  # one), then move the working tree onto it. `push .` is ff-checked, so a race
  # that advanced `live` underneath us is refused rather than overwritten.
  local ff_err
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

  # Adopt: the carrier that just arrived becomes root's block for this tier. The
  # memory root adopts nothing — its own index is one of the files that moved.
  gitlore_adopt_tier_into_root "$mempath" "$tier" "$root_dirty_before" "$head" || return 1
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
