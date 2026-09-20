#!/usr/bin/env bash
# Diagnose and repair gitlore remote state. Detection order matches
# Section 6.2 of the spec. Idempotent: a healthy state produces no changes.
#
# The continue-after-merge functions live in lib/continuation.sh, sourced
# below; they set this script's own globals and exit on its behalf.
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
# shellcheck disable=SC1091
source "$PLUGIN_ROOT/scripts/lib/continuation.sh"

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
      merge_msgfile=$(mktemp "${TMPDIR:-/tmp}/gitlore-merge-msg.XXXXXX") \
        || {
          echo "gitlore: the merge message file could not be created, so the merge was not committed; the merge stays prepared." >&2
          exit 1
        }
      # Each failure exit here keeps MERGE_HEAD and the merge state, so a rerun
      # lands it; only the message file is this run's to remove, and a failed
      # mktemp above created none. Each `||` group below removes it first:
      # errexit stays armed there, so a failing write to stderr would skip
      # whatever follows it and leave the scratch file behind.
      gitlore_merge_commit_message "$memroot" "$mempath" > "$merge_msgfile" \
        || {
          rm -f "$merge_msgfile"
          echo "gitlore: the merge message could not be built, so the merge was not committed; the merge stays prepared." >&2
          exit 1
        }
      GITLORE_MEMORY_COMMIT=1 gitlore_git -C "$mempath" commit -q -F "$merge_msgfile" \
        || {
          rm -f "$merge_msgfile"
          echo "gitlore: the merge commit was refused, so the merge was not committed; the merge stays prepared." >&2
          exit 1
        }
      rm -f "$merge_msgfile"
      # Stage the gitlink the commit above just moved — after it, because the
      # merge commit does not exist until then and an earlier `add` would pin
      # the pre-merge authority. Not cosmetic: `submodule update` checks a tier
      # out at the sha the superproject's INDEX holds, so a gitlink left in the
      # working tree alone is walked back to the pre-merge commit by the next
      # SessionStart tier pass — silently, while the recomposed root index
      # survives to describe facts the tier no longer carries. Staged, the
      # unconditional pin is idempotent rather than destructive.
      if [ -n "$merged_tier" ] && [ -z "$tier_unadopted" ]; then
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
      rc=0; push_or_report "$mempath" . HEAD:live || rc=$?
      if [ "$rc" -eq 1 ]; then
        gitlore_yield_merge "$mempath" live head-vs-live HEAD || exit 1
        exit 1
      elif [ "$rc" -eq 2 ]; then
        [ -z "$tier_unadopted" ] || rest_unadopted_tier "$memroot" "$merged_tier"
        exit 1
      fi
      # `publish: "no"` is /gitlore:merge's mark: reconcile, do not share. Every
      # gate leaves it empty, because a merge a refused push prepared exists to
      # let that push through.
      # A yield above leaves a fresh merge prepared at the tier's HEAD, whose
      # continuation retries the adoption; only a merge that has fully landed
      # rests the tier.
      if [ "$publish" = "no" ]; then
        echo "gitlore: merged without publishing, as /gitlore:merge asks. Run /gitlore:push when you want these facts on the remote." >&2
        [ -z "$tier_unadopted" ] || rest_unadopted_tier "$memroot" "$merged_tier"
        exit 0
      fi
      if [ "$flavor" = "head-vs-remote" ]; then
        rc=0; push_or_report "$mempath" origin live || rc=$?
        if [ "$rc" -eq 1 ]; then
          gitlore_git -C "$mempath" fetch -q origin live || true
          gitlore_yield_merge "$mempath" origin/live head-vs-remote live || exit 1
          exit 1
        elif [ "$rc" -eq 2 ]; then
          [ -z "$tier_unadopted" ] || rest_unadopted_tier "$memroot" "$merged_tier"
          exit 1
        fi
      fi
      [ -z "$tier_unadopted" ] || rest_unadopted_tier "$memroot" "$merged_tier"
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

# Both gates for one store: local `live` first (cheaper, local-only), then the
# remote's. No branch guard is needed at either level — every store is checked
# out detached, so `HEAD:live` is always the right question and is a silent
# no-op when HEAD is already there. Yields and exits on the first divergence;
# `commands/resolve.md` re-runs this script until it exits 0, which is what
# walks the remaining gates and stores.
check_store_gates() {
  # `tier` is the store's tier name, empty for the memory root: the head-vs-live
  # gate's remedy differs by store kind, because a tier is pinned at the gitlink
  # the memory store records (D43) and the root is not.
  local store="$1" tier="${2-}" rc
  gitlore_git -C "$store" fetch -q origin live || true
  rc=0; push_or_report "$store" . HEAD:live || rc=$?
  if [ "$rc" -eq 2 ]; then
    exit 1
  elif [ "$rc" -eq 1 ]; then
    # git refuses a merely-BEHIND ref with the same wording as a genuinely
    # diverged one; only ancestry tells them apart. Same discriminator every
    # other yield site applies (gitlore_sync_tiers_to_live et al.) — this was
    # the one call site that skipped it and routed straight into a merge
    # prepare against a store with nothing to merge.
    if [ "$(gitlore_classify_refusal "$store" HEAD live)" = "diverged" ]; then
      gitlore_yield_merge "$store" live head-vs-live HEAD || exit 1
      exit 1
    elif gitlore_check_head_live_agree "$store" "$store" "$tier"; then
      gitlore_say_for_agent_or_user \
        "gitlore: pushing HEAD to $store's local 'live' was refused, though HEAD and 'live' agree and neither has diverged." \
        "gitlore: pushing HEAD to $store's local 'live' was refused, though HEAD and 'live' agree and neither has diverged." >&2
      exit 1
    else
      exit 1
    fi
  fi
  rc=0; push_or_report "$store" origin live || rc=$?
  if [ "$rc" -eq 2 ]; then
    exit 1
  elif [ "$rc" -eq 1 ]; then
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

# Every mounted tier, through the identical pair of gates — one merge policy at
# every level — and before memory's, the order gitlore_push_stores keeps too:
# memory's commit records each tier's, so memory published ahead of a tier push
# that then fails leaves a pointer the tier's remote cannot resolve (D17). A
# tier with no remote or no local `live` has nothing to reconcile yet;
# `pre-push` is where a missing tier remote is fatal, because that is the point
# at which its absence starts losing writes.
while IFS= read -r store; do
  if [ "$store" = "$mempath" ]; then continue; fi
  [ -n "$(git -C "$store" config --get remote.origin.url || true)" ] || continue
  git -C "$store" rev-parse -q --verify live >/dev/null || continue
  # Every store under `$mempath` is a tier; the root is handled below.
  check_store_gates "$store" "${store##*/}"
done < <(gitlore_memory_stores "$mempath")

check_store_gates "$mempath"

echo "gitlore: state is healthy. Nothing to do." >&2
exit 0
