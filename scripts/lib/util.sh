#!/usr/bin/env bash
# Shared shell utilities. Source; do not exec.

# The canonical submodule name regardless of working-tree path.
GITLORE_SUBMODULE_NAME="gitlore-memory"
readonly GITLORE_SUBMODULE_NAME

# Print the memory submodule's working-tree path (relative to repo root).
# Exit 1 if the submodule is not registered.
gitlore_memory_path() {
  local path
  path=$(git config --file .gitmodules \
    "submodule.${GITLORE_SUBMODULE_NAME}.path" 2>/dev/null) || return 1
  [ -n "$path" ] || return 1
  printf '%s\n' "$path"
}

# Exit 0 if .gitmodules registers the gitlore-memory submodule, 1 otherwise.
gitlore_has_submodule() {
  gitlore_memory_path >/dev/null 2>&1
}

# Print the parent worktree's branch name, or "DETACHED" if not on a branch.
# Exit 1 outside a git repo.
gitlore_parent_branch() {
  local b
  b=$(git symbolic-ref --short -q HEAD 2>/dev/null) || {
    git rev-parse --verify HEAD >/dev/null 2>&1 || return 1
    printf 'DETACHED\n'
    return 0
  }
  printf '%s\n' "$b"
}

# Print abs path to the memory submodule's commit-msg file.
# Resolves through the submodule's gitdir correctly.
# Args: $1 = memory path (must exist as a working tree).
gitlore_commit_msg_file() {
  local mempath="$1"
  git -C "$mempath" rev-parse --git-path gitlore-commit-msg
}

# Print abs path to the memory submodule's merge-state file.
# Resolves through the submodule's gitdir correctly.
# Args: $1 = memory path (working tree).
gitlore_merge_state_file() {
  local mempath="$1"
  git -C "$mempath" rev-parse --git-path gitlore-merge-state
}

# Echo '0' (clean) or '1' (dirty). Convention is string output, NOT exit status —
# callers should compare with `[ "$(gitlore_memory_dirty PATH)" = "1" ]`.
gitlore_memory_dirty() {
  local mempath="$1"
  if [ -z "$(git -C "$mempath" status --porcelain)" ]; then
    printf '0\n'
  else
    printf '1\n'
  fi
}

# Echo "yes" if commit-msg file is fresh (mtime >= newest tracked memory file),
# else "no" or "absent".
gitlore_commit_msg_freshness() {
  local mempath="$1"
  local msgfile
  msgfile=$(gitlore_commit_msg_file "$mempath") || return 1
  [ -f "$msgfile" ] || { printf 'absent\n'; return 0; }
  local newest=0 f m
  while IFS= read -r -d '' f; do
    m=$(stat -c '%Y' "$f" 2>/dev/null || stat -f '%m' "$f")
    [ "$m" -gt "$newest" ] && newest="$m"
  done < <(find "$mempath" -type f -not -path '*/.git/*' -print0)
  local msgmtime
  msgmtime=$(stat -c '%Y' "$msgfile" 2>/dev/null || stat -f '%m' "$msgfile")
  awk -v a="$msgmtime" -v b="${newest:-0}" \
      'BEGIN { print (a+0 >= b+0) ? "yes" : "no" }'
}
