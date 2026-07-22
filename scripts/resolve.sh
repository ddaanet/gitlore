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
  found=$(gitlore_stores_with_merge_state "$(gitlore_memory_path)")
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

# Subcommand dispatch (Plan 03 continuations).
if [ $# -ge 1 ]; then
  subcmd="$1"
  shift
  case "$subcmd" in
    continue-after-merge)
      load_continuation_state
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
      if ! gitlore_git -C "$mempath" push -q . HEAD:live; then
        gitlore_yield_merge "$mempath" live head-vs-live || exit 1
        exit 1
      fi
      if [ "$flavor" = "head-vs-remote" ]; then
        if ! gitlore_git -C "$mempath" push -q origin live; then
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
if ! git -C "$mempath" ls-remote origin live | grep -q .; then
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
  if ! gitlore_git -C "$store" push -q . HEAD:live; then
    gitlore_yield_merge "$store" live head-vs-live || exit 1
    exit 1
  fi
  if ! gitlore_git -C "$store" push -q origin live; then
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
