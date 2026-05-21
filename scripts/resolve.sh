#!/usr/bin/env bash
# Diagnose and repair gitlore remote state. Detection order matches
# Section 6.2 of the spec. Idempotent: a healthy state produces no changes.
set -euo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:?CLAUDE_PLUGIN_ROOT must be set}"
# shellcheck disable=SC1091
source "$PLUGIN_ROOT/scripts/lib/util.sh"
# shellcheck disable=SC1091
source "$PLUGIN_ROOT/scripts/lib/log.sh"

# Step 1: gitlore installed?
if ! gitlore_has_submodule; then
  gitlore_say_for_agent_or_user \
    "gitlore: not installed in this repo. Run /gitlore:install." \
    "gitlore: not installed in this repo. Open this project in Claude Code and run /gitlore:install." >&2
  exit 1
fi

mempath=$(gitlore_memory_path)

# Step 2: remote.origin.url set?
remote_url=$(git -C "$mempath" config --get remote.origin.url 2>/dev/null || true)
if [ -z "$remote_url" ] || [ "$remote_url" = "./.git/gitlore-placeholder" ]; then
  echo "gitlore: no memory remote configured. Creating one." >&2
  bash "$PLUGIN_ROOT/scripts/install/create-remote.sh" "$mempath"
  echo "gitlore: memory remote created and live pushed." >&2
  exit 0
fi

# Step 3: remote reachable?
if ! git -C "$mempath" ls-remote origin >/dev/null 2>&1; then
  gitlore_say_for_agent_or_user \
    "gitlore: memory remote unreachable. Check network or 'gh auth status'. Manual fix required." \
    "gitlore: memory remote unreachable. Check network or run 'gh auth status'." >&2
  exit 1
fi

# Step 4: live exists on remote?
if ! git -C "$mempath" ls-remote origin live | grep -q .; then
  echo "gitlore: remote has no live branch. Pushing." >&2
  git -C "$mempath" push origin live
  echo "gitlore: live pushed." >&2
  exit 0
fi

# Step 5: ff-relationship between local and remote live?
local_live=$(git -C "$mempath" rev-parse live)
remote_live=$(git -C "$mempath" ls-remote origin live | awk '{print $1}')
if [ "$local_live" != "$remote_live" ]; then
  if git -C "$mempath" merge-base --is-ancestor "$remote_live" "$local_live"; then
    echo "gitlore: local live is ahead of remote. Pushing." >&2
    git -C "$mempath" push origin live
    echo "gitlore: live pushed." >&2
    exit 0
  fi
  gitlore_say_for_agent_or_user \
    "gitlore: local and remote live diverged. Manual resolution required — Plan 02 does not auto-resolve divergence. Inspect with 'git -C $mempath log live..origin/live' and 'git -C $mempath log origin/live..live'." \
    "gitlore: local and remote live diverged. Open the memory submodule and resolve manually." >&2
  exit 1
fi

echo "gitlore: state is healthy. Nothing to do." >&2
exit 0
