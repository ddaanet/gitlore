#!/usr/bin/env bash
# Diagnose and repair gitlore remote state. Detection order matches
# Section 6.2 of the spec. Idempotent: a healthy state produces no changes.
set -euo pipefail
unset CDPATH   # else `cd` may echo its target into the $(cd … && pwd) capture below

# Derive plugin root: prefer the env var, fall back to the script's own location.
# The fallback matters for continuation invocations dispatched from a sub-agent
# whose shell may not inherit CLAUDE_PLUGIN_ROOT.
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then
  PLUGIN_ROOT="$CLAUDE_PLUGIN_ROOT"
else
  PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fi
export PLUGIN_ROOT CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
# shellcheck disable=SC1091
source "$PLUGIN_ROOT/scripts/lib/util.sh"
# shellcheck disable=SC1091
source "$PLUGIN_ROOT/scripts/lib/log.sh"
# shellcheck disable=SC1091
source "$PLUGIN_ROOT/scripts/lib/resolve.sh"
# shellcheck disable=SC1091
source "$PLUGIN_ROOT/scripts/lib/index-compose.sh"

# Load shared continuation state: require an installed submodule and exactly one
# prepared merge, then set mempath/statefile/flavor/publish for the caller.
#
# The store is FOUND, not derived. Memory and every tier share one merge policy
# and one state-file name resolved inside their own gitdirs, so a continuation
# that assumed `gitlore_memory_path` would commit in memory while the prepared
# merge sat in a tier. The search walks the same store list the gates do, and
# `mempath` comes from the state file's own `store` field — absolute, so it does
# not depend on where the continuation was invoked from.
load_continuation_state() {
  gitlore_has_submodule || { echo "gitlore: not installed" >&2; exit 1; }
  local found
  # The memory ROOT, kept apart from `mempath`: composition spans the whole
  # memory tree, so it is anchored here even when the merge sits in a tier.
  memroot=$(gitlore_memory_path)
  found=$(gitlore_stores_with_merge_state "$memroot")
  if [ -z "$found" ]; then
    echo "gitlore: no merge state file in memory or any tier" >&2
    exit 1
  fi
  # A gate yields on the first divergence and stops, so two prepared merges mean
  # the state is not what any continuation assumes. Refusing beats guessing which
  # one this invocation meant.
  if [ "$(printf '%s\n' "$found" | wc -l)" -gt 1 ]; then
    echo "gitlore: merges are prepared in more than one store, which should not happen:" >&2
    printf '%s\n' "$found" | sed 's/^/gitlore:   /' >&2
    echo "gitlore: land or abort one of them before continuing." >&2
    exit 1
  fi
  statefile=$(gitlore_merge_state_file "$found")
  mempath=$(jq -r '.store // ""' "$statefile")
  if [ -z "$mempath" ] || [ ! -e "$mempath/.git" ]; then
    echo "gitlore: merge state at $statefile does not name a usable store." >&2
    exit 1
  fi
  flavor=$(jq -r .flavor "$statefile")
  # `// ""` covers a state file written before the field existed, and jq's own
  # `null` for a key present but empty: both mean "publish", the gate default.
  publish=$(jq -r '.publish // ""' "$statefile")
}

# Adopt a merged tier into the root index: project the merged carrier UP, so
# root's block for that tier becomes what the merge produced.
#
# This is the step that makes a tier merge reach the surface CC recalls from. A
# tier is pinned at its gitlink and composition projects the ROOT down, so
# nothing else would ever move the merged lines into root — the in-session pass
# would read them as carrier lines root chose not to carry, keep them where they
# are, and report them. The adoption is also the one moment a carrier outranks
# root's text: it is the artifact the user just approved, line by line.
#
# Once, here, and in this direction only. Projecting down would write a carrier
# the user never reviewed as a side effect of approving this merge.
#
# A memory-store merge adopts nothing: root's own `MEMORY.md` is one of the files
# git merged, so the propagation is already in the merged content. The pass still
# runs, with no tier named — the merge produced whatever order the two sides
# implied, and the layout, the four validations and the dangling report all still
# have something to say about it.
#
# A refusal never blocks the merge. Compose is fail-safe (it writes nothing), and
# the merge is synthesized and approved by this point: stranding it half-landed
# over an index problem the agent fixes in one edit is the worse outcome. Report,
# then commit what the merger produced.
# Sets `merged_tier` for the caller: the store's path relative to the memory
# root, or empty when the merge is memory's own. The continuation needs it after
# the commit to stage the moved gitlink, and this is where it is already derived.
# Args: $1 = memory root worktree path, $2 = the store being committed.
compose_merged_indexes() {
  local memroot="$1" store="$2" memroot_abs composed dangling rc=0
  merged_tier=""
  # The state file records an absolute store path while `memroot` is the
  # submodule path as `.gitmodules` spells it, so the two are compared in one
  # form. `-ef` rather than string equality: this decides whether a tier is
  # adopted at all, and a path spelled two ways would adopt a tier named after
  # the memory root itself.
  memroot_abs=$(CDPATH='' cd -- "$memroot" && pwd) || memroot_abs="$memroot"
  if ! [ "$store" -ef "$memroot" ]; then
    merged_tier=${store#"$memroot_abs"/}
    if [ "$merged_tier" = "$store" ]; then
      merged_tier=""
      echo "gitlore: the merged store $store is not inside the memory root $memroot_abs; the root index was left uncomposed." >&2
      gitlore_git -C "$store" add -A
      return 0
    fi
  fi

  composed=$(gitlore_compose_up "$memroot" "$merged_tier") || rc=$?
  if [ "$rc" -eq 0 ]; then
    [ -n "$composed" ] && printf '%s\n' "$composed" | sed 's/^/gitlore: /' >&2
    # The dangling pass reports rather than refuses, so it runs on the composed
    # store and speaks whether or not composition wrote anything.
    dangling=$(gitlore_compose_dangling "$memroot")
    if [ -n "$dangling" ]; then
      echo "gitlore: these index lines name files that are not there. Nothing was rewritten or deleted:" >&2
      printf '%s\n' "$dangling" | sed 's/^/gitlore:   /' >&2
    fi
  elif [ "$rc" -eq 2 ]; then
    echo "gitlore: the root index could not be written — the merge is being committed without the adopted tier's lines. Investigate the path named below, then edit MEMORY.md to retrigger composition:" >&2
    printf '%s\n' "$composed" | sed 's/^/gitlore:   /' >&2
  else
    echo "gitlore: tier composition refused — the merge is being committed without the adopted tier's lines in the root index. Fix the store by hand, then edit MEMORY.md to retrigger it:" >&2
    printf '%s\n' "$composed" | sed 's/^/gitlore:   /' >&2
  fi
  # The merger already ran `git add -A` in the store being committed; re-running
  # it is how anything written there joins the same commit. Then the root index,
  # which for a tier merge lives in a DIFFERENT store: staging it there is what
  # puts it in the next FR11 commit rather than leaving it as an unexplained
  # working-tree change. For a memory merge the two calls are the same repo, and
  # the second is what stages the compose write the first ran too early to see.
  gitlore_git -C "$store" add -A
  # A store with no root index — seeded from an empty auto-memory dir — has
  # nothing to stage; gitlore_compose_up tolerated its absence above, and the
  # merge must not be blocked on it. Say so: nothing composes up into a root
  # index that does not exist, and that is the store's defect, not the merge's.
  if [ -f "$memroot/MEMORY.md" ]; then
    gitlore_git -C "$memroot" add -- MEMORY.md
  else
    echo "gitlore: the memory root $memroot_abs has no MEMORY.md, so no tier lines can compose into it. The merge is committed regardless; create the root index (\`# Memory Index\`) and edit it to trigger composition." >&2
  fi
}

# Fast-forward a ref with `push`, routing a refusal by its cause. Returns 0 on
# success; returns 1 when git's parenthesized reason says the ref diverged,
# which is the caller's cue to prepare a merge; reports git's own explanation
# and EXITS 1 on any other refusal — a protected branch, a pre-receive decline,
# a bad credential, a full quota.
#
# The same discriminator `pre-push` and `gitlore_sync_memory_to_live` apply, and
# for the same reason: only divergence is something a merge can fix. Without it
# a policy refusal prepares a merge that cannot help — and this script is where
# the user lands *after* pre-push has correctly told them the push failed for a
# reason other than divergence, so it is the last place that should re-diagnose
# it as one.
#
# An empty message is treated as divergence, matching the memory gate: `push -q`
# names its rejection reason, so silence here means the refusal carried no text
# to route on and the local `HEAD:live` case is the only cause left.
# Args: $1 = store worktree, $2… = push arguments (remote and refspec).
push_or_report() {
  local store="$1"; shift
  local push_err
  if push_err=$(gitlore_git -C "$store" push -q "$@" 2>&1); then
    return 0
  fi
  case "$push_err" in
    *"(fetch first)"*|*"(non-fast-forward)"*) return 1 ;;
    *) [ -n "$push_err" ] || return 1 ;;
  esac
  gitlore_say_for_agent_or_user \
    "gitlore: pushing '$*' in $store failed, and not because of divergence — no merge can fix this. git said:
$push_err" \
    "gitlore: pushing '$*' in $store failed, and not because of divergence — no merge can fix this. git said:
$push_err" >&2
  exit 1
}

# Subcommand dispatch (Plan 03 continuations).
if [ $# -ge 1 ]; then
  subcmd="$1"
  shift
  case "$subcmd" in
    continue-after-merge)
      load_continuation_state
      # Compose before committing, so what lands is composed: a merge is the one
      # write path into a memory store that no compose trigger sees.
      compose_merged_indexes "$memroot" "$mempath"
      # Is the ROOT store carrying unapproved work this merge's bookkeeping
      # would sweep up? Asked of the paths OUTSIDE the pair: the preparation has
      # already moved the tier, so the root is dirty by construction here and a
      # plain dirty reading would refuse every tier merge. Only meaningful for a
      # tier merge — for a memory merge the store being committed IS the root.
      if [ -n "$merged_tier" ]; then
        root_dirty_before=$(gitlore_root_dirty_beyond_pair "$memroot" "$merged_tier")
      else
        root_dirty_before=1
      fi
      # Commit the merge. The authority is HEAD, so it is the first parent (D6),
      # and the message is canned rather than git's MERGE_MSG: a merge whose two
      # sides both passed an approval gate needs no prompt, and the subject that
      # serves every consumer of a shared store names the repos rather than the
      # refs (D49). Blessed path: carry the sentinel past the submodule gate.
      # Via a file, not a pipe: the sentinel has to be in the environment of
      # `git commit` itself, and `VAR=1 printf … | git commit` exports it to
      # the wrong end of the pipeline.
      merge_msgfile=$(mktemp "${TMPDIR:-/tmp}/gitlore-merge-msg.XXXXXX")
      gitlore_merge_commit_message "$memroot" "$mempath" > "$merge_msgfile"
      GITLORE_MEMORY_COMMIT=1 gitlore_git -C "$mempath" commit -q -F "$merge_msgfile"
      rm -f "$merge_msgfile"
      # Stage the gitlink the commit above just moved — after it, because the
      # merge commit does not exist until then and an earlier `add` would pin
      # the pre-merge authority. Not cosmetic: `submodule update` checks a tier
      # out at the sha the superproject's INDEX holds, so a gitlink left in the
      # working tree alone is walked back to the pre-merge commit by the next
      # SessionStart tier pass — silently, while the recomposed root index
      # survives to describe facts the tier no longer carries. Staged, the
      # unconditional pin is idempotent rather than destructive.
      if [ -n "$merged_tier" ]; then
        # Read the pointer the root still records — the commit the tier sat at
        # before this merge — for the bookkeeping body, before the `add` moves
        # it in the index and the commit moves it in HEAD.
        old_gitlink=$(git -C "$memroot" rev-parse "HEAD:$merged_tier") || old_gitlink=""
        gitlore_git -C "$memroot" add -- "$merged_tier" \
          || echo "gitlore: the merge landed, but $merged_tier's moved pointer could not be staged in the memory store. Stage it before the next session, or the tier will be reset to its pre-merge commit." >&2
        # And record the pair, so a merge the user asked for leaves a clean
        # store rather than dirt the next FR11 episode has to explain (D49).
        [ -z "$old_gitlink" ] \
          || gitlore_commit_tier_bookkeeping "$memroot" "$merged_tier" "$root_dirty_before" "$old_gitlink"
      fi
      gitlore_clear_merge_state "$mempath"
      gitlore_git -C "$mempath" update-ref -d "$GITLORE_PENDING_REF"
      # Restore the invariant: fast-forward local `live` onto the merge commit,
      # then — when the merge was against the remote — the remote's `live` too.
      # Either can lose a race with a concurrent advance; re-prepare against
      # whichever side refused and yield again.
      if ! push_or_report "$mempath" . HEAD:live; then
        gitlore_yield_merge "$mempath" live head-vs-live HEAD || exit 1
        exit 1
      fi
      # `publish: "no"` is /gitlore:merge's mark: reconcile, do not share. Every
      # gate leaves it empty, because a merge a refused push prepared exists to
      # let that push through.
      if [ "$publish" = "no" ]; then
        echo "gitlore: merged without publishing, as /gitlore:merge asks. Run /gitlore:push when you want these facts on the remote." >&2
        exit 0
      fi
      if [ "$flavor" = "head-vs-remote" ]; then
        if ! push_or_report "$mempath" origin live; then
          gitlore_git -C "$mempath" fetch -q origin live || true
          gitlore_yield_merge "$mempath" origin/live head-vs-remote live || exit 1
          exit 1
        fi
      fi
      exit 0
      ;;
    *)
      echo "gitlore: unknown resolve subcommand: $subcmd" >&2
      exit 2
      ;;
  esac
fi

# Default mode: detect + try both pushes in turn. Yield on the first failure;
# continuations re-enter from the hook (commit/push retries), not from here.

gitlore_has_submodule || {
  gitlore_say_for_agent_or_user \
    "gitlore: not installed in this repo. Run /gitlore:install." \
    "gitlore: not installed in this repo. Open this project in Claude Code and run /gitlore:install." >&2
  exit 1
}
mempath=$(gitlore_memory_path)

# Existing Plan 02 simple repairs (remote.origin.url, ls-remote, push live)
# happen first — they precede semantic-merge detection.
remote_url=$(git -C "$mempath" config --get remote.origin.url || true)
if [ -z "$remote_url" ] || gitlore_is_placeholder_url "$remote_url"; then
  echo "gitlore: no memory remote configured. Creating one." >&2
  bash "$PLUGIN_ROOT/scripts/install/create-remote.sh" "$mempath"
  echo "gitlore: memory remote created and live pushed." >&2
  # Fall through rather than exiting: a repair to memory says nothing about the
  # tiers, and stopping here would leave a diverged tier undetected.
fi
if ! git -C "$mempath" ls-remote origin >/dev/null 2>&1; then
  gitlore_say_for_agent_or_user \
    "gitlore: memory remote unreachable. Check network or 'gh auth status'." \
    "gitlore: memory remote unreachable. Check network or 'gh auth status'." >&2
  exit 1
fi
# Captured rather than piped into `grep -q`: this script runs with `set -o
# pipefail`, where an early-exiting consumer can leave `ls-remote` writing into
# a closed pipe and turn a healthy remote into a SIGPIPE failure.
if [ -z "$(git -C "$mempath" ls-remote origin live)" ]; then
  echo "gitlore: remote has no live branch. Pushing." >&2
  gitlore_git -C "$mempath" push origin live
  # Fall through, same reason: the gates below re-check memory as a no-op and
  # then walk every tier.
fi

# Both gates for one store: local `live` first (cheaper, local-only), then the
# remote's. No branch guard is needed at either level — every store is checked
# out detached, so `HEAD:live` is always the right question and is a silent
# no-op when HEAD is already there. Yields and exits on the first divergence;
# `commands/resolve.md` re-runs this script until it exits 0, which is what
# walks the remaining gates and stores.
check_store_gates() {
  local store="$1"
  gitlore_git -C "$store" fetch -q origin live || true
  if ! push_or_report "$store" . HEAD:live; then
    # git refuses a merely-BEHIND ref with the same wording as a genuinely
    # diverged one; only ancestry tells them apart. Same discriminator every
    # other yield site applies (gitlore_sync_tiers_to_live et al.) — this was
    # the one call site that skipped it and routed straight into a merge
    # prepare against a store with nothing to merge.
    if [ "$(gitlore_classify_refusal "$store" HEAD live)" = "diverged" ]; then
      gitlore_yield_merge "$store" live head-vs-live HEAD || exit 1
      exit 1
    elif gitlore_check_head_live_agree "$store" "$store"; then
      gitlore_say_for_agent_or_user \
        "gitlore: pushing HEAD to $store's local 'live' was refused, though HEAD and 'live' agree and neither has diverged." \
        "gitlore: pushing HEAD to $store's local 'live' was refused, though HEAD and 'live' agree and neither has diverged." >&2
      exit 1
    else
      exit 1
    fi
  fi
  if ! push_or_report "$store" origin live; then
    case "$(gitlore_classify_refusal "$store" live origin/live)" in
      behind)
        # Nothing of ours to publish — the remote is ahead, which is
        # /gitlore:merge's business, not a failed push to report on.
        gitlore_say_for_agent_or_user \
          "gitlore: $store has nothing to publish — its remote 'live' is ahead of the local one. Run /gitlore:merge to take those facts." \
          "gitlore: $store has nothing to publish — its remote 'live' is ahead of the local one. Run /gitlore:merge to take those facts." >&2
        ;;
      diverged)
        gitlore_yield_merge "$store" origin/live head-vs-remote live || exit 1
        exit 1
        ;;
      *)
        gitlore_say_for_agent_or_user \
          "gitlore: pushing $store's 'live' to origin was refused as a non-fast-forward, but its local 'live' already contains the remote's. The remote moved during the push, or the fetch before it failed." \
          "gitlore: pushing $store's 'live' to origin was refused as a non-fast-forward, but its local 'live' already contains the remote's. The remote moved during the push, or the fetch before it failed." >&2
        exit 1
        ;;
    esac
  fi
}

# A half-finished merge anywhere is the first thing to report: pushing on top of
# one is exactly what the guard exists to prevent.
while IFS= read -r store; do
  gitlore_guard_stale_merge_state "$store" || exit 1
done < <(gitlore_memory_stores "$mempath")

check_store_gates "$mempath"

# Every mounted tier, through the identical pair of gates — one merge policy at
# every level. A tier with no remote or no local `live` has nothing to reconcile
# yet; `pre-push` is where a missing tier remote is fatal, because that is the
# point at which its absence starts losing writes.
while IFS= read -r store; do
  if [ "$store" = "$mempath" ]; then continue; fi
  [ -n "$(git -C "$store" config --get remote.origin.url || true)" ] || continue
  git -C "$store" rev-parse -q --verify live >/dev/null || continue
  check_store_gates "$store"
done < <(gitlore_memory_stores "$mempath")

echo "gitlore: state is healthy. Nothing to do." >&2
exit 0
