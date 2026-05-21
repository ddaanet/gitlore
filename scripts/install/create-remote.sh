#!/usr/bin/env bash
# Create the memory submodule's GitHub remote and rewire .gitmodules.
# Idempotent: no-op when remote.origin.url is already a real URL.
# Args: $1 = mempath (relative to repo root)
set -euo pipefail

mempath="$1"

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:?CLAUDE_PLUGIN_ROOT must be set}"
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

(
  cd "$mempath"
  git checkout -q live
  if ! gh repo create "$full_name" --private --source=. --push 2>&1; then
    echo "gitlore: gh repo create failed. Run /gitlore:resolve to recover." >&2
    exit 1
  fi
)

new_url=$(git -C "$mempath" config --get remote.origin.url 2>/dev/null || true)
if [ -z "$new_url" ]; then
  echo "gitlore: gh repo create succeeded but remote.origin.url is empty. Run /gitlore:resolve." >&2
  exit 1
fi

git config --file .gitmodules "submodule.${GITLORE_SUBMODULE_NAME}.url" "$new_url"
git add .gitmodules

exit 0
