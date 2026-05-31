#!/usr/bin/env bash
# Create the memory submodule's GitHub remote and rewire .gitmodules.
# Idempotent: no-op when remote.origin.url is already a real URL.
# Args: $1 = mempath (relative to repo root)
set -euo pipefail

mempath="$1"

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
# shellcheck disable=SC1091
source "$PLUGIN_ROOT/scripts/lib/util.sh"

existing=$(git -C "$mempath" config --get remote.origin.url 2>/dev/null || true)
if [ -n "$existing" ] && [ "$existing" != "./.git/gitlore-placeholder" ]; then
  exit 0
fi

owner=$(gh api user -q .login)
repo_basename=$(basename "$(git rev-parse --show-toplevel)")
repo_name="${repo_basename}-gitlore-memory"
full_name="${owner}/${repo_name}"

# Avoid `gh repo create --source=. --push` — gh's --source handling rejects
# gitfile-pointed submodule worktrees with "current directory is not a git
# repository" (verified against gh 2.88.1). Create the empty remote and wire
# it up by hand instead.
if ! gh repo create "$full_name" --private; then
  echo "gitlore: gh repo create failed. Run /gitlore:resolve to recover." >&2
  exit 1
fi

remote_url=$(gh repo view "$full_name" --json sshUrl -q .sshUrl || true)
if [ -z "$remote_url" ]; then
  echo "gitlore: created remote $full_name but could not resolve its URL. Run /gitlore:resolve to recover." >&2
  exit 1
fi

git -C "$mempath" remote add origin "$remote_url"
if ! git -C "$mempath" push -u origin live; then
  echo "gitlore: created remote but failed to push memory's live branch. Run /gitlore:resolve to retry." >&2
  exit 1
fi

git config --file .gitmodules "submodule.${GITLORE_SUBMODULE_NAME}.url" "$remote_url"
git add .gitmodules

exit 0
