#!/usr/bin/env bash
# Shared functions for memory divergence detection, state-file IO, and
# directive emission. Source; do not exec.
#
# Preparing a merge re-merges the index files, so this library pulls its own
# index dependencies in rather than making all five callers (both git hooks,
# session-start, commit-memory, resolve) declare a transitive need. Both are
# function-only and safe to source twice; util.sh is NOT (it declares a
# `readonly`), so it stays the caller's job, as does log.sh.
#
# The library is split into resolve-*.sh parts, each function-only and safe
# to source twice, that this file sources after its own two lines above:
#   resolve-recovery.sh     repair a stale merge-state file (lost MERGE_HEAD,
#                            a checkout-cleared staged merge)
#   resolve-merge-state.sh  merge-state file IO, merge preparation, and the
#                            sub-agent directive
#   resolve-sync-tiers.sh   commit dirty tiers and fast-forward their `live`
#   resolve-sync-memory.sh  commit dirty memory itself (the FR11 commit path)
#   resolve-push.sh         publish every store to its own remote
#   resolve-merge-stores.sh take whatever each store's remote holds, without
#                            publishing
#   resolve-adopt.sh        adopt a tier's arrival into the root index, with
#                            carrier repair on refusal
#   resolve-adopt-report.sh report an adoption refusal, walk a tier back, and
#                            record a landed adoption's bookkeeping commit
# shellcheck disable=SC1091
source "${BASH_SOURCE[0]%/*}/index-compose.sh"
# shellcheck disable=SC1091
source "${BASH_SOURCE[0]%/*}/index-merge.sh"
# shellcheck disable=SC1091
source "${BASH_SOURCE[0]%/*}/resolve-recovery.sh"
# shellcheck disable=SC1091
source "${BASH_SOURCE[0]%/*}/resolve-merge-state.sh"
# shellcheck disable=SC1091
source "${BASH_SOURCE[0]%/*}/resolve-sync-tiers.sh"
# shellcheck disable=SC1091
source "${BASH_SOURCE[0]%/*}/resolve-sync-memory.sh"
# shellcheck disable=SC1091
source "${BASH_SOURCE[0]%/*}/resolve-push.sh"
# shellcheck disable=SC1091
source "${BASH_SOURCE[0]%/*}/resolve-merge-stores.sh"
# shellcheck disable=SC1091
source "${BASH_SOURCE[0]%/*}/resolve-adopt.sh"
# shellcheck disable=SC1091
source "${BASH_SOURCE[0]%/*}/resolve-adopt-report.sh"

# Print every store under this memory tree — memory itself, then each mounted
# tier — in the order the gates visit them. One merge policy applies at every
# level, so callers that walk stores (divergence detection, the stale-state
# guard, the continuation's search for a prepared merge) all walk this list.
# Args: $1 = memory worktree path.
gitlore_memory_stores() {
  local mempath="$1" tier
  printf '%s\n' "$mempath"
  while IFS= read -r tier; do
    [ -n "$tier" ] || continue
    # `git -C` into an unchecked-out submodule escapes to the enclosing repo, so
    # an unmounted tier must never reach a caller.
    [ -e "$mempath/$tier/.git" ] || continue
    printf '%s/%s\n' "$mempath" "$tier"
  done < <(gitlore_tier_paths "$mempath")
}

# Print every store that currently holds a merge-state file. Normally none or
# one: a gate yields on the first divergence it meets and stops, so a second
# store's merge is not prepared until the first is landed.
# Args: $1 = memory worktree path.
gitlore_stores_with_merge_state() {
  local mempath="$1" store
  while IFS= read -r store; do
    [ -n "$store" ] || continue
    [ -f "$(gitlore_merge_state_file "$store")" ] || continue
    printf '%s\n' "$store"
  done < <(gitlore_memory_stores "$mempath")
}

# Detect whether a stale merge-state file, or an orphaned MERGE_HEAD with no
# state file at all, exists.
# Stdout: "clean" | "stale-with-merge-head" | "stale-no-merge-head" |
#         "orphaned-merge-head".
gitlore_detect_stale_merge_state() {
  local mempath="$1"
  local statefile gitdir
  statefile=$(gitlore_merge_state_file "$mempath")
  gitdir=$(git -C "$mempath" rev-parse --git-dir)
  if [ ! -f "$statefile" ]; then
    # A real MERGE_HEAD with no state file means gitlore_prepare_merge staged
    # a merge and the caller died before gitlore_write_merge_state recorded
    # it — the window an interrupted `push-memory.sh` run left open, with real
    # content staged and nothing pointing at it.
    if [ -f "$gitdir/MERGE_HEAD" ]; then
      printf 'orphaned-merge-head\n'
    else
      printf 'clean\n'
    fi
    return 0
  fi
  if [ -f "$gitdir/MERGE_HEAD" ]; then
    printf 'stale-with-merge-head\n'
  else
    printf 'stale-no-merge-head\n'
  fi
}

# Guard against a stale merge-state file before committing or pushing memory:
# never operate on top of a half-finished merge. On a clean state, return 0
# silently. Otherwise emit the appropriate directive/message on stderr and
# return 1, so callers can `|| return 1` / `|| exit 1`.
#   stale-with-merge-head → emit the merge directive again, so the prepared
#                            merge is continued
#   stale-no-merge-head    → classify and repair (gitlore_recover_stale_no_merge_head),
#                            which returns 0 when the caller may carry on
# Args: $1 = memory worktree path.
gitlore_guard_stale_merge_state() {
  local mempath="$1"
  local state_status statefile flavor
  state_status=$(gitlore_detect_stale_merge_state "$mempath")
  case "$state_status" in
    stale-with-merge-head)
      # A prepared merge is always continued. The store sits exactly where
      # gitlore_prepare_merge leaves one, so the sub-agent can pick it up
      # unchanged — and by the time a gate meets it again the merger may already
      # have synthesized and staged an answer, which discarding the merge would
      # throw away. A merge whose authority moved meanwhile lands against the
      # old one and is re-prepared by the continuation's own refused push, which
      # costs one cycle; re-preparing every stale merge costs a synthesis.
      statefile=$(gitlore_merge_state_file "$mempath")
      # A preparation interrupted between its merge and its briefing left a
      # marker; the merge itself is staged in the store, so the briefing is
      # written now and the merge continues like any other.
      if ! gitlore_complete_merge_state "$mempath"; then
        gitlore_say_for_agent_or_user \
          "gitlore: $mempath holds a prepared merge whose state file could not be completed, so no sub-agent can be briefed on it. Read $statefile, then inspect the store." \
          "gitlore: $mempath holds a prepared merge whose state file could not be completed, so no sub-agent can be briefed on it. Read $statefile, then inspect the store." >&2
        return 1
      fi
      flavor=$(jq -r .flavor "$statefile")
      gitlore_emit_merge_directive "$statefile" "$flavor" "continue-after-merge"
      return 1
      ;;
    stale-no-merge-head)
      gitlore_recover_stale_no_merge_head "$mempath" || return 1
      ;;
    orphaned-merge-head)
      local mh
      mh=$(git -C "$mempath" rev-parse -q --verify MERGE_HEAD)
      # gitlore records its own preparations before they start, so this is a
      # merge something else began in the store — a hand-run `git merge`, or an
      # agent asked to merge by hand. Reported rather than touched: nothing here
      # says what it was for, and it may hold work in progress.
      local orph_msg
      orph_msg="gitlore: $mempath holds a merge gitlore did not prepare (MERGE_HEAD $mh, no merge state file), so nothing was changed. Finish it or undo it in the store, then re-run the operation:
gitlore:   git -C \"$mempath\" status --short
gitlore:   git -C \"$mempath\" merge --abort"
      gitlore_say_for_agent_or_user "$orph_msg" "$orph_msg" >&2
      return 1
      ;;
  esac
  return 0
}

# Why a push was refused, decided by ancestry rather than by git's wording.
#
# git rejects a merely BEHIND ref with the same "(fetch first)" /
# "(non-fast-forward)" it gives a genuinely DIVERGED one — both are
# non-fast-forward pushes — and only divergence has a merge to prepare. A behind
# store has nothing of its own to publish at all, so routing it into the merge
# flow ends in a preparation that finds nothing and a diagnostic naming a
# worktree that is clean. The parenthesized reason still separates "the ref
# could not fast-forward" from a policy or credential refusal; this separates
# the two ancestries hiding behind that one reason.
#
# `ahead` is the pushed ref already containing the target, which means the
# refusal was not about ancestry: the remote moved during the push, or the fetch
# that precedes it failed and the target ref is stale.
# Args: $1 = store, $2 = pushed ref, $3 = target ref.
# Stdout: behind | diverged | ahead | unknown.
gitlore_classify_refusal() {
  local store="$1" pushed="$2" target="$3" p t
  # `-q --verify` on both: a ref that cannot be read is not a classification,
  # and answering "diverged" for one would start a merge on a guess.
  p=$(git -C "$store" rev-parse -q --verify "$pushed") || { printf 'unknown\n'; return 0; }
  t=$(git -C "$store" rev-parse -q --verify "$target") || { printf 'unknown\n'; return 0; }
  if git -C "$store" merge-base --is-ancestor "$p" "$t"; then
    printf 'behind\n'
  elif git -C "$store" merge-base --is-ancestor "$t" "$p"; then
    printf 'ahead\n'
  else
    printf 'diverged\n'
  fi
}

# Refuse to publish a store whose HEAD and local `live` name different commits.
#
# A store is checked out DETACHED AT `live` (D17), so the two agree in every
# state the tooling produces. They are read by different halves of the publish,
# though: the push sends `live`, while a merge preparation — and the gitlink the
# enclosing commit records — reason from HEAD. Once they disagree, a push can
# succeed while the recorded pointer never reaches the remote (lockstep broken
# silently), or be refused on a ref the merge preparation never looks at, which
# is how a rejection gets diagnosed against a HEAD that has nothing to say.
#
# Reported, never repaired: which ref is the intended one is not recoverable
# from the refs themselves, and the drift means some earlier step left the store
# in a state no normal path produces.
#
# One direction IS recoverable, and is repaired before this runs rather than
# here: the publish preflights call gitlore_repair_stranded_live first, so a
# `live` merely left behind a HEAD containing it is already advanced by the time
# this reads the refs. Its arm below stays because the other call sites reach
# this only after their own `push . HEAD:live` was refused — there, `live`
# behind HEAD means the ref moved under the push, which is a race and not the
# lag the repair recognizes.
#
# The remedy differs by STORE KIND, because the authoritative ref does. For the
# memory root, `live` is what SessionStart checks out and the parent's gitlink is
# allowed to lag (D46), so a HEAD behind it is put back with a checkout. A tier
# is pinned at the gitlink the memory store records (D43): the same checkout
# takes it OFF that pin, and the next composition refuses — the two gates then
# assert different invariants about one ref and obeying this one breaks the
# store. A tier goes to the take, which moves HEAD, the root index and the
# recorded pointer together.
# Args: $1 = store, $2 = label, $3 = tier name ("" when the store is the memory
# root). Returns 1 after emitting when they disagree.
gitlore_check_head_live_agree() {
  local store="$1" label="$2" tier="${3-}" head live abs remedy
  head=$(git -C "$store" rev-parse -q --verify HEAD) || return 0
  # No local `live` yet (a tier never fetched) — nothing to disagree with.
  live=$(git -C "$store" rev-parse -q --verify live) || return 0
  [ "$head" != "$live" ] || return 0
  # `--show-toplevel` rather than a subshell `cd`: the remedy below is printed
  # for a human to paste, so the path has to be absolute, and CDPATH turns
  # `$(cd … && pwd)` into a path with a directory listing glued to the front.
  abs=$(git -C "$store" rev-parse --show-toplevel) || abs="$store"
  if git -C "$store" merge-base --is-ancestor "$head" "$live"; then
    if [ -n "$tier" ]; then
      remedy="'live' holds commits the memory store never recorded; run /gitlore:merge to adopt them. Do not check the tier out at 'live' — that moves it off the commit the store records, and composition refuses there."
    else
      remedy="Put HEAD back on 'live': git -C \"$abs\" checkout --detach live"
    fi
  elif git -C "$store" merge-base --is-ancestor "$live" "$head"; then
    remedy="Advance 'live' to HEAD: git -C \"$abs\" push . HEAD:live"
  else
    remedy="HEAD and 'live' have each moved since they last agreed; run /gitlore:resolve to reconcile them."
  fi
  # `$label — …` rather than `$label's …`: a tier label already carries quotes
  # around its name, and an apostrophe-s on top of them renders `'ddaanet''s`.
  gitlore_say_for_agent_or_user \
    "gitlore: $label — HEAD is not at its local 'live' (HEAD $(git -C "$store" rev-parse --short "$head"), live $(git -C "$store" rev-parse --short "$live")), so nothing was published. $remedy" \
    "gitlore: $label — HEAD is not at its local 'live' (HEAD $(git -C "$store" rev-parse --short "$head"), live $(git -C "$store" rev-parse --short "$live")), so nothing was published. $remedy" >&2
  return 1
}

# The repository name a store's remote points at, for a merge subject line:
# the url's last path segment, minus a trailing `.git`. A store with no remote,
# or one still carrying the placeholder, falls back to its own directory name —
# the subject is a label, and a merge is worth recording under an imperfect one.
# Args: $1 = store worktree.
gitlore_store_repo_name() {
  local store="$1" url base
  url=$(git -C "$store" config --get remote.origin.url || true)
  if [ -z "$url" ] || gitlore_is_placeholder_url "$url"; then
    base=$(cd "$store" && pwd -P) || return 1
    printf '%s\n' "${base##*/}"
    return 0
  fi
  # Strip a trailing slash, then take the last segment of either url flavor —
  # `host:org/repo.git` and `https://host/org/repo` both end at the same `/`,
  # and an scp-style url with no path separator falls back to the whole tail.
  url="${url%/}"
  base="${url##*/}"
  base="${base##*:}"
  printf '%s\n' "${base%.git}"
}

# The name of the repository performing a merge — the parent working tree the
# memory store is a submodule of. A tier's `live` history is shared across every
# repo that mounts it, so the subject says which consumer landed the merge.
# Falls back to the memory store's own directory when no superproject answers.
# Args: $1 = memory worktree.
gitlore_consumer_name() {
  local mempath="$1" parent
  parent=$(git -C "$mempath" rev-parse --show-superproject-working-tree) || parent=""
  if [ -z "$parent" ]; then
    parent=$(cd "$mempath" && pwd -P) || return 1
  fi
  printf '%s\n' "${parent##*/}"
}

# The canned message for a merge commit in $2, on stdout: a subject naming the
# merged repo and the consumer that merged it, then the subjects the merge
# brought INTO `live` — the second-parent side. A tier store is read by every
# repo that mounts it, and each of those already holds the first-parent side;
# what the merge contributed is the news (D49).
# Args: $1 = memory worktree (for the consumer name), $2 = the merging store.
gitlore_merge_commit_message() {
  local mempath="$1" store="$2" repo consumer
  repo=$(gitlore_store_repo_name "$store") || repo="memory"
  consumer=$(gitlore_consumer_name "$mempath") || consumer="unknown"
  printf 'merge %s from %s\n\n' "$repo" "$consumer"
  # MERGE_HEAD is the pending (local) side under D6's direction: the authority
  # is checked out as HEAD and becomes the first parent. `-q --verify` is silent
  # if it is somehow absent, and the body is then simply empty.
  local second
  second=$(git -C "$store" rev-parse -q --verify MERGE_HEAD) || return 0
  git -C "$store" log --format='%s' "HEAD..$second" | sed 's/^/  /'
}
