#!/usr/bin/env bash
# WorktreeRemove (advisory) — tear down the memory submodule worktree that
# gitlore created for a parent worktree. CC cannot be blocked by this hook; on
# any failure it warns and exits 0. Input stdin: {worktree_path} (CC 2.1.150 —
# no branch field). See design.md "WorktreeRemove".
set -euo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-}"
# shellcheck disable=SC1091
source "$PLUGIN_ROOT/scripts/lib/util.sh"

input=$(cat)
worktree_path=$(printf '%s' "$input" | jq -r '.worktree_path // empty')
[ -n "$worktree_path" ] || exit 0

gitlore_cd_project_root || exit 0   # the launch repo, never the session cwd (see util.sh)

# Guard: no-op unless this repo registers the gitlore-memory submodule.
gitlore_has_submodule || exit 0
mempath=$(gitlore_memory_path)

common_dir=$(CDPATH='' cd -- "$(git rev-parse --git-common-dir)" && pwd)
mem_gitdir="$common_dir/modules/$GITLORE_SUBMODULE_NAME"
[ -d "$mem_gitdir" ] || exit 0

mem_wt="$worktree_path/$mempath"
if [ -e "$mem_wt" ]; then
  # Capture git's reason instead of discarding it: "(locked or uncommitted)" was
  # a guess appended to every failure, so the actual cause never reached the user.
  if ! rm_err=$(git -C "$mem_gitdir" worktree remove --force "$mem_wt" 2>&1); then
    printf 'gitlore: could not remove memory worktree at %s; it will be pruned. git said:\n%s\n' \
      "$mem_wt" "$rm_err" >&2
  fi
fi
# Prune dangling admin entries whether the dir was removable or already gone.
git -C "$mem_gitdir" worktree prune >/dev/null 2>&1 || true

# Branch retention is a deliberate no-op: CC keeps the parent branch on removal
# (verified 2.1.150), so gitlore keeps the memory branch. Never touch parent branches.
exit 0
