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
# prepared merge, then set mempath/statefile/flavor/pending for the caller.
#
# The store is FOUND, not derived. Memory and every tier share one merge policy
# and one state-file name resolved inside their own gitdirs, so a continuation
# that assumed `gitlore_memory_path` would commit in memory while the prepared
# merge sat in a tier. The search walks the same store list the gates do, and
# `mempath` comes from the state file's own `store` field — absolute, so it does
# not depend on where the continuation was invoked from.
# Args: $1 = "abort" to use the abort-flavored missing-state message; any other
# value (or none) uses the default "no merge state file" message.
load_continuation_state() {
  gitlore_has_submodule || { echo "gitlore: not installed" >&2; exit 1; }
  local found
  # The memory ROOT, kept apart from `mempath`: composition spans the whole
  # memory tree, so it is anchored here even when the merge sits in a tier.
  memroot=$(gitlore_memory_path)
  found=$(gitlore_stores_with_merge_state "$memroot")
  if [ -z "$found" ]; then
    if [ "${1:-}" = "abort" ]; then
      echo "gitlore: no merge state file to abort" >&2
    else
      echo "gitlore: no merge state file in memory or any tier" >&2
    fi
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
  pending=$(jq -r .source_ref "$statefile")
}

# Compose the memory tree's indexes and stage the result in the store that is
# about to be committed.
#
# A landed merge is the one route into a memory store that no compose trigger
# covers: the PostToolBatch hook fires on an index EDIT and SessionStart on a new
# session, so a synthesized index would otherwise sit uncomposed until one of
# those happened to fire. Running here puts the composed bytes in the merge
# commit itself rather than in a later, unrelated one.
#
# Composition spans the whole tree, so it can write a store OTHER than the one
# being committed — the root index when a tier merged, a carrier when memory did.
# Those writes stay dirty and ride the next FR11 commit, the same float the
# SessionStart recompose already produces.
#
# A refusal never blocks the merge. Compose is fail-safe (it writes nothing), and
# the merge is synthesized and approved by this point: stranding it half-landed
# over an index problem the agent fixes in one edit is the worse outcome. Report,
# then commit what the merger produced.
# Args: $1 = memory root worktree path, $2 = the store being committed.
compose_merged_indexes() {
  local memroot="$1" store="$2" composed dangling rc=0
  composed=$(gitlore_compose "$memroot") || rc=$?
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
    echo "gitlore: tier composition could not write an index — the merge is being committed with the indexes only PARTLY composed. Investigate the path named below, then edit MEMORY.md to retrigger the pass:" >&2
    printf '%s\n' "$composed" | sed 's/^/gitlore:   /' >&2
  else
    echo "gitlore: tier composition refused — the merge is being committed uncomposed. Fix the store by hand, then edit MEMORY.md to retrigger it:" >&2
    printf '%s\n' "$composed" | sed 's/^/gitlore:   /' >&2
  fi
  # The merger already ran `git add -A` here; re-running it is how anything
  # composition wrote joins the same commit.
  gitlore_git -C "$store" add -A
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
      # Commit the merge (uses git's MERGE_MSG; the authority is HEAD, so it is
      # the first parent per D6). Blessed path: carry the sentinel past the
      # submodule gate (FR11).
      GITLORE_MEMORY_COMMIT=1 gitlore_git -C "$mempath" commit -q --no-edit
      rm -f "$statefile"
      gitlore_git -C "$mempath" update-ref -d "$GITLORE_PENDING_REF"
      # Restore the invariant: fast-forward local `live` onto the merge commit,
      # then — when the merge was against the remote — the remote's `live` too.
      # Either can lose a race with a concurrent advance; re-prepare against
      # whichever side refused and yield again.
      if ! push_or_report "$mempath" . HEAD:live; then
        gitlore_yield_merge "$mempath" live head-vs-live || exit 1
        exit 1
      fi
      if [ "$flavor" = "head-vs-remote" ]; then
        if ! push_or_report "$mempath" origin live; then
          gitlore_git -C "$mempath" fetch -q origin live || true
          gitlore_yield_merge "$mempath" origin/live head-vs-remote || exit 1
          exit 1
        fi
      fi
      exit 0
      ;;
    abort-then-retry)
      load_continuation_state abort
      # Test for a merge in progress rather than suppressing "no merge to abort":
      # that message is the one expected failure, and gating on MERGE_HEAD removes
      # it, so a genuine abort failure is no longer swallowed.
      if git -C "$mempath" rev-parse -q --verify MERGE_HEAD >/dev/null; then
        gitlore_git -C "$mempath" merge --abort || true
      fi
      # Return to the pending commit — the divergent side the merge was landing.
      # Aborting leaves HEAD at the authority, where the divergence is invisible;
      # re-detaching there is what makes the re-entry below detect it again.
      gitlore_git -C "$mempath" checkout -q --detach "$pending" || true
      rm -f "$statefile"
      gitlore_git -C "$mempath" update-ref -d "$GITLORE_PENDING_REF"
      # Re-enter the default mode to detect the original divergence freshly.
      exec bash "$0"
      ;;
    *)
      # Other subcommands added in later tasks.
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
if [ -z "$remote_url" ] || [ "$remote_url" = "./.git/gitlore-placeholder" ]; then
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
    gitlore_yield_merge "$store" live head-vs-live || exit 1
    exit 1
  fi
  if ! push_or_report "$store" origin live; then
    gitlore_yield_merge "$store" origin/live head-vs-remote || exit 1
    exit 1
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
