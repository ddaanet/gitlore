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

# Load shared continuation state: require an installed submodule and an existing
# merge-state file, then set mempath/statefile/flavor/pending for the caller.
# Args: $1 = "abort" to use the abort-flavored missing-state message; any other
# value (or none) uses the default "no merge state file at <path>" message.
load_continuation_state() {
  gitlore_has_submodule || { echo "gitlore: not installed" >&2; exit 1; }
  mempath=$(gitlore_memory_path)
  statefile=$(gitlore_merge_state_file "$mempath")
  if [ ! -f "$statefile" ]; then
    if [ "${1:-}" = "abort" ]; then
      echo "gitlore: no merge state file to abort" >&2
    else
      echo "gitlore: no merge state file at $statefile" >&2
    fi
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
  exit 0
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
  exit 0
fi

gitlore_git -C "$mempath" fetch -q origin live || true

# Try HEAD-vs-live first (cheaper, local-only). No branch guard is needed: the
# memory worktree is always detached, so `HEAD:live` is always the right question
# and is a silent no-op when HEAD is already at live.
if ! gitlore_git -C "$mempath" push -q . HEAD:live; then
  gitlore_yield_merge "$mempath" live head-vs-live || exit 1
  exit 1
fi

# Local `live` is in sync with HEAD. Try HEAD-vs-remote.
if ! gitlore_git -C "$mempath" push -q origin live; then
  gitlore_yield_merge "$mempath" origin/live head-vs-remote || exit 1
  exit 1
fi

echo "gitlore: state is healthy. Nothing to do." >&2
exit 0
