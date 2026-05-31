#!/usr/bin/env bash
# Create the memory submodule's GitHub remote and rewire .gitmodules.
# Idempotent: no-op when remote.origin.url is already a real URL.
# Args: $1 = mempath (relative to repo root)
#       $2 = mode: auto (default) | url | local
#       $3 = remote URL (required for url mode)
set -euo pipefail

mempath="$1"

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
# shellcheck disable=SC1091
source "$PLUGIN_ROOT/scripts/lib/util.sh"

mode="${2:-auto}"
url_arg="${3:-}"

# Idempotency: a real (non-placeholder) origin already wired → nothing to do.
existing=$(git -C "$mempath" config --get remote.origin.url 2>/dev/null || true)
if [ -n "$existing" ] && [ "$existing" != "./.git/gitlore-placeholder" ]; then
  exit 0
fi

wire_and_push() {
  # Args: $1 = remote URL. Adds origin, pushes live, rewrites .gitmodules URL.
  local remote_url="$1"
  git -C "$mempath" remote add origin "$remote_url"
  if ! git -C "$mempath" push -u origin live; then
    echo "gitlore: wired remote but failed to push memory's live branch. Run /gitlore:resolve to retry." >&2
    exit 1
  fi
  git config --file .gitmodules "submodule.${GITLORE_SUBMODULE_NAME}.url" "$remote_url"
  git add .gitmodules
}

local_only_notice() {
  echo "gitlore: installed local-only — memory is versioned in-repo with no remote." >&2
  echo "gitlore: add a remote later by re-running /gitlore:install and supplying a URL." >&2
}

case "$mode" in
  url)
    [ -n "$url_arg" ] || { echo "gitlore: url mode requires a remote URL." >&2; exit 1; }
    wire_and_push "$url_arg"
    ;;

  local)
    local_only_notice
    ;;

  auto)
    # Opportunistic gh: only when present AND authenticated.
    if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
      owner=$(gh api user -q .login)
      repo_name=$(gitlore_memory_remote_name)
      visibility=$(gitlore_parent_visibility)
      full_name="${owner}/${repo_name}"
      if ! gh repo create "$full_name" --"$visibility"; then
        echo "gitlore: gh repo create failed. Run /gitlore:resolve to recover, or re-run install with a remote URL." >&2
        exit 1
      fi
      remote_url=$(gh repo view "$full_name" --json sshUrl -q .sshUrl || true)
      if [ -z "$remote_url" ]; then
        echo "gitlore: created remote $full_name but could not resolve its URL. Run /gitlore:resolve to recover." >&2
        exit 1
      fi
      wire_and_push "$remote_url"
    else
      # No usable gh → local-only (the agent offers the copy-paste URL path
      # interactively in install.md before reaching this non-interactive script).
      local_only_notice
    fi
    ;;

  *)
    echo "gitlore: unknown remote mode '$mode'." >&2
    exit 1
    ;;
esac

exit 0
