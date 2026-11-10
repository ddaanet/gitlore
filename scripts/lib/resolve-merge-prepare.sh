#!/usr/bin/env bash
# Prepare a memory merge against its authority, then yield it to the merger.
# Part of lib/resolve.sh; source that, not this file.

# Prepare a merge of the pending commit into the more authoritative side. One
# shape serves both flavors (D17 unified branch model): memory is detached at
# `live`, so the authority is reached with `checkout --detach` — no named branch
# is ever checked out, so the one-checkout-per-branch contention that used to
# make this fail (D3) cannot arise, and there is no branch to return to.
# The authority becomes the merge's FIRST parent (D6); the pending commit is
# merged in as the second. The pending commit is pinned at
# `$GITLORE_PENDING_REF` before HEAD moves — nothing else references it once
# `merge --abort` drops MERGE_HEAD.
# The pending ref is taken from the caller rather than assumed to be HEAD: an
# earlier interrupted run can leave HEAD sitting ON the authority (the checkout
# below already ran; the caller died before recording state), and a raw
# `rev-parse HEAD` would then re-diagnose real, still-unmerged divergence as
# nothing to merge. Callers pass whichever ref their own flavor treats as the
# pending side — `HEAD` for head-vs-live (this call is inherently about HEAD
# vs the `live` branch), `live` for head-vs-remote (HEAD can be displaced by a
# prior interruption; the local `live` branch is untouched by a checkout onto
# some other authority).
# Every mounted tier's gitlink on both sides is checked ahead of the checkout, so
# a stop moves nothing, and staged once the merge exists: the tier's HEAD is the
# answer whichever way git merged the gitlink, and the merger is asked nothing
# about it. The stage precedes the state file, which then lists no tier.
# Args: $1 = memory worktree path, $2 = authority ref (`live` or `origin/live`),
#       $3 = pending ref (`HEAD` or `live`).
# Stdout: `<base_sha>:<pending_sha>`.
# Returns 1 after git's words, 2 after a stop that has said all there is to say.
gitlore_prepare_merge() {
  local mempath="$1" authority="$2" pending_ref="$3"
  local pending base merge_err restore_err tiers
  pending=$(git -C "$mempath" rev-parse "$pending_ref")
  # Nothing to merge: the authority already contains the pending commit, so the
  # merge below would report "Already up to date." and leave no MERGE_HEAD.
  # Tested BEFORE the checkout, because that checkout is a side effect — a
  # failed diagnosis that moves HEAD onto the authority is what silently
  # un-adopts a store, by making the next `/gitlore:merge` take its
  # "already holds everything" early return and skip the adopt step. Callers
  # classify by ancestry and do not reach here in this state; this is the lock
  # on the mutating path itself.
  if git -C "$mempath" merge-base --is-ancestor "$pending" "$authority"; then
    printf 'gitlore: %s already contains HEAD, so there is no merge to prepare.\n' "$authority" >&2
    return 1
  fi
  # Read before the merge, which can leave `.gitmodules` holding conflict markers.
  tiers=$(gitlore_tier_paths "$mempath")
  gitlore_check_tier_gitlinks "$mempath" "$tiers" "$authority" "$pending" || return 2
  base=$(git -C "$mempath" merge-base "$pending" "$authority")
  gitlore_git -C "$mempath" update-ref "$GITLORE_PENDING_REF" "$pending"
  gitlore_git -C "$mempath" checkout -q --detach "$authority"
  # A conflicting merge is the EXPECTED outcome here — the conflicted worktree is
  # exactly what the merger sub-agent resolves — so a non-zero exit is not a
  # failure and the conflict listing is noise the state file already carries in
  # `conflicted_files`. Captured rather than discarded, because a merge that
  # failed for some other reason (an unmergeable ref, an index left unmerged by
  # something else) leaves no MERGE_HEAD, and the directive would then announce a
  # merge nobody prepared. MERGE_HEAD is the discriminator; git's own words are
  # what the user gets when it is absent.
  #
  # `merge.conflictStyle=diff3` is set per invocation rather than in the store's
  # config: this merge is gitlore's, and a store's config is also the user's.
  # The base section is what makes a memory conflict resolvable — with only two
  # versions, "one side added this sentence" and "the other side deleted it" are
  # the same picture, and the resolver has to guess which.
  merge_err=$(gitlore_git -C "$mempath" -c merge.conflictStyle=diff3 \
    merge --no-commit --no-ff "$pending" 2>&1) || true
  if ! git -C "$mempath" rev-parse -q --verify MERGE_HEAD >/dev/null; then
    printf '%s\n' "$merge_err" >&2
    # Put HEAD back where it was. The checkout above was preparation for a merge
    # that did not happen, and handing the caller a moved HEAD makes a failed
    # diagnosis indistinguishable from a landed one. No --force: the stores
    # reaching here are clean, and a checkout refused by real content is a
    # message worth having rather than a tree worth discarding.
    if ! restore_err=$(gitlore_git -C "$mempath" checkout -q --detach "$pending" 2>&1); then
      printf 'gitlore: HEAD in %s is still at %s after a merge that could not be prepared. Restore it with: git -C "%s" checkout --detach %s\ngit said: %s\n' \
        "$mempath" "$authority" "$mempath" "$pending" "$restore_err" >&2
    fi
    return 1
  fi
  if ! gitlore_stage_tier_heads "$mempath" "$tiers"; then
    gitlore_git -C "$mempath" merge --abort || :
    gitlore_git -C "$mempath" checkout -q --detach "$pending" || :
    return 1
  fi
  # Redo every index file entry-wise, over git's line-wise result. Unconditional:
  # the failure this catches — both sides adding the same pointer path at
  # different offsets, which merges CLEANLY into a duplicate — leaves no
  # conflict for a conditional to test.
  gitlore_merge_indexes "$mempath" "$base" "$authority" "$pending" >/dev/null || \
    echo "gitlore: the entry-wise index merge could not run in $mempath; git's line-wise result stands." >&2
  printf '%s:%s\n' "$base" "$pending"
}

# Prepare the merge, record its state file, and emit the sub-agent directive.
# The caller yields (return/exit 1) immediately afterwards. Returns 1 without
# emitting if the merge could not be prepared at all.
# Args: $1 = memory worktree path, $2 = authority ref, $3 = flavor label,
#       $4 = pending ref (see gitlore_prepare_merge).
gitlore_yield_merge() {
  local mempath="$1" authority="$2" flavor="$3" pending_ref="$4"
  local prep base pending statefile pending_sha rc=0
  # Before anything is written: a refusal must leave no marker, state file or
  # merge behind for the next gate to classify.
  # Gated here for every caller: the take, the push, the resolve command.
  gitlore_refuse_dirty_merge "$mempath" "$authority" || return 1
  gitlore_refuse_rewritten "$mempath" "$authority" "$pending_ref" || return 1
  # The marker goes down BEFORE the preparation, so every window inside it
  # leaves a state file for the next gate to classify (D7): a merge that staged
  # is completed and continued, one that never ran is discarded and re-prepared.
  # Written even though the preparation may refuse outright — it is removed on
  # that path below, and the alternative is the window this exists to close.
  pending_sha=$(git -C "$mempath" rev-parse -q --verify "$pending_ref^{commit}") || pending_sha="$pending_ref"
  if ! gitlore_write_merge_marker "$mempath" "$flavor" "$pending_sha" "$authority" "continue-after-merge"; then
    gitlore_say_for_agent_or_user \
      "gitlore: no merge was started in $mempath because its merge state file could not be written, so nothing can record one. Inspect the memory worktree." \
      "gitlore: no merge was started in $mempath because its merge state file could not be written, so nothing can record one. Inspect the memory worktree." >&2
    return 1
  fi
  prep=$(gitlore_prepare_merge "$mempath" "$authority" "$pending_ref") || rc=$?
  if [ "$rc" -ne 0 ]; then
    # No merge was started, so the marker describes nothing. Dropped with the
    # pin, which the preparation may have set before it failed.
    gitlore_drop_merge_preparation "$mempath"
    [ "$rc" -ne 2 ] || return 1
    gitlore_say_for_agent_or_user \
      "gitlore: could not prepare the memory merge against '$authority'. Inspect the memory worktree at $mempath." \
      "gitlore: could not prepare the memory merge against '$authority'. Inspect the memory worktree at $mempath." >&2
    return 1
  fi
  base="${prep%%:*}"
  pending="${prep#*:}"
  if ! gitlore_write_merge_state "$mempath" "$flavor" "$base" "$pending" "$authority" "continue-after-merge"; then
    gitlore_say_for_agent_or_user \
      "gitlore: the merge was prepared in $mempath but its state file could not be written, so no continuation can run. Inspect the memory worktree." \
      "gitlore: the merge was prepared in $mempath but its state file could not be written, so no continuation can run. Inspect the memory worktree." >&2
    return 1
  fi
  statefile=$(gitlore_merge_state_file "$mempath")
  gitlore_emit_merge_directive "$statefile" "$flavor" "continue-after-merge"
  return 0
}

# Refuse a merge on a store with uncommitted changes: a merge is prepared on a
# clean store only, since the continuation commits with `add -A` and
# uncommitted edits would ride into the merge commit unapproved. Called by the
# yield above, and by the take's preflight for a memory root forked from its
# local `live`, so that refusal comes before any tier moves. The root arm of
# the take's predicate is the rule for any store: a tier has no submodules for
# its --ignore-submodules=all to leave out.
# Args: $1 = store worktree, $2 = the merge's authority ref.
# Returns 1 after emitting when the store is dirty.
gitlore_refuse_dirty_merge() {
  local mempath="$1" authority="$2"
  [ "$(gitlore_store_dirty_for_take "$mempath" "")" = "1" ] || return 0
  gitlore_say_for_agent_or_user \
    "gitlore: $mempath has uncommitted changes and has diverged from '$authority', so no merge was prepared. Commit them (approved summary, then a memory commit) and run the command again." \
    "gitlore: $mempath has uncommitted changes and has diverged from '$authority', so no merge was prepared. Commit them and try again." >&2
  return 1
}

# Stop a memory merge whose gitlink the tier cannot answer with its HEAD: a commit
# neither the tier nor its remote holds, or one the tier holds and HEAD does not
# descend. A tier merge commit and a fast-forward both descend each side.
# Args: $1 = memory worktree, $2 = tier paths, one per line, $3 and $4 = the
#       merge's two sides. Returns 1 after emitting.
gitlore_check_tier_gitlinks() {
  local mempath="$1" tiers="$2" tier tierpath head side sha msg
  shift 2
  while IFS= read -r tier; do
    [ -n "$tier" ] || continue
    tierpath="$mempath/$tier"
    # `git -C` into an unchecked-out submodule walks up to the enclosing repo.
    [ -e "$tierpath/.git" ] || continue
    head=$(git -C "$tierpath" rev-parse -q --verify HEAD) || continue
    for side in "$@"; do
      # `-q --verify` is silent on the expected miss: a side with no such gitlink.
      sha=$(git -C "$mempath" rev-parse -q --verify "$side:$tier") || continue
      gitlore_tier_holds_gitlink "$mempath" "$tier" "$sha" || return 1
      git -C "$tierpath" merge-base --is-ancestor "$sha" "$head" && continue
      msg="gitlore: tier '$tier' sits at ${head:0:12}, which does not contain ${sha:0:12}, the commit memory records for it, so no memory merge was prepared. Run /gitlore:merge, which takes the tier before memory."
      gitlore_say_for_agent_or_user "$msg" "$msg" >&2
      return 1
    done
  done <<<"$tiers"
}

# Stage each mounted tier's HEAD into the pending merge, resolving an unmerged
# gitlink. A tier the merged index no longer lists stays deleted.
# Args: $1 = memory worktree, $2 = tier paths, one per line.
gitlore_stage_tier_heads() {
  local mempath="$1" tier
  while IFS= read -r tier; do
    [ -n "$tier" ] || continue
    [ -e "$mempath/$tier/.git" ] || continue
    [ -n "$(git -C "$mempath" ls-files -- "$tier")" ] || continue
    gitlore_git -C "$mempath" add -- "$tier" || return 1
  done <<<"$2"
}

# Refuse root's fast-forward onto a commit recording a tier commit no repository
# holds. Args: $1 = memory worktree, $2 = the incoming commit. Returns 1 after
# emitting.
gitlore_refuse_unresolvable_gitlinks() {
  local mempath="$1" incoming="$2" tier sha
  while IFS= read -r tier; do
    [ -n "$tier" ] || continue
    [ -e "$mempath/$tier/.git" ] || continue
    # `-q --verify` is silent on the expected miss: a commit with no such gitlink.
    sha=$(git -C "$mempath" rev-parse -q --verify "$incoming:$tier") || continue
    gitlore_tier_holds_gitlink "$mempath" "$tier" "$sha" || return 1
  done < <(gitlore_tier_paths "$mempath")
}

# True when tier $2 holds commit $3, after one fetch of it from the tier's remote
# if it does not yet. Refused otherwise, as an integrity error: the checkout that
# recorded the commit is the one that can publish it. git's words go with the
# refusal, since a remote that could not be reached says nothing about the
# commit — to the user only, with the remote's url as `gitlore_url_for_display`
# shows it: the url is the user's config, and git repeats it as configured,
# credential included.
# Args: $1 = memory worktree, $2 = tier name, $3 = the recorded commit.
# Returns 1 after emitting.
gitlore_tier_holds_gitlink() {
  local mempath="$1" tier="$2" sha="$3" tierpath="$1/$2" url err shown tail agent
  git -C "$tierpath" rev-parse -q --verify "$sha^{commit}" >/dev/null && return 0
  if err=$(git -C "$tierpath" fetch -q --no-recurse-submodules origin "$sha" 2>&1) \
     && git -C "$tierpath" rev-parse -q --verify "$sha^{commit}" >/dev/null; then
    return 0
  fi
  url=$(git -C "$tierpath" config --get remote.origin.url || true)
  tail="supplied that commit, so memory was neither moved nor composed."
  if [ -n "$url" ]; then
    shown=$(gitlore_url_for_display "$url")
    err=${err//"$url"/"$shown"}
    tail="$tail The checkout that recorded it runs /gitlore:push; /gitlore:merge then retries."
    agent="neither the tier nor its remote $tail The user has the remote's url and git's words."
  else
    # A retry refuses identically while there is no remote to supply the
    # commit, so the tail is the remedy a take gives for the same state.
    shown="(none configured)"
    tail="$tail Mount the tier against a remote or unmount it."
    agent="the tier has no remote and does not hold it, so nothing $tail The user has git's words."
  fi
  gitlore_say_for_agent_or_user \
    "gitlore: memory records ${sha:0:12} for tier '$tier', and $agent" \
    "gitlore: memory records ${sha:0:12} for tier '$tier', and neither the tier nor its remote $shown $tail git said:
$err" >&2
  return 1
}
