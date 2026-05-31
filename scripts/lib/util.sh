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

# Print the CC project-scoped auto-memory dir for a repo root.
# CC encodes the project dir name by replacing every non-[A-Za-z0-9] byte with
# `-` (verified empirically against ~/.claude/projects/ entries). The >200-char
# truncate+hash fallback is out of scope — repo abs paths that long are
# vanishingly rare. Args: $1 = repo root abs path.
gitlore_cc_memory_dir() {
  local root="$1" encoded
  encoded=$(printf '%s' "$root" | LC_ALL=C sed 's/[^A-Za-z0-9]/-/g')
  printf '%s\n' "$HOME/.claude/projects/$encoded/memory"
}

# Replace a CC auto-memory dir with a stub MEMORY.md recording that gitlore
# migrated memory in-tree. Idempotent: if the dir already holds only our stub,
# leave it untouched. Args: $1 = the auto-memory dir.
gitlore_mark_migrated() {
  local dir="$1" stub="$1/MEMORY.md"
  # shellcheck disable=SC2016  # literal marker string, no expansion intended
  if [ -f "$stub" ] && grep -q 'migrated in-tree by `/gitlore:install`' "$stub" 2>/dev/null; then
    return 0
  fi
  rm -rf "$dir"
  mkdir -p "$dir"
  cat > "$stub" <<'EOF'
# Memory migrated in-tree

This project's auto-memory was migrated in-tree by `/gitlore:install`. It now
lives in the `gitlore-memory` submodule, versioned in git alongside the code.

Do not add memory here. Launch Claude Code through the gitlore `claude` shim so
memory is redirected into the submodule. New files appearing in this directory
mean a session was started without the launcher — see the gitlore SessionStart
warning for how to activate it.
EOF
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

# Exit 0 if $1 is a writable directory, 1 otherwise. Used to detect a sandboxed
# install before it dies mid-mutation with a raw "Permission denied".
# Args: $1 = directory to test.
gitlore_probe_writable() {
  local dir="$1" probe="$1/.gitlore-write-probe.$$"
  if ( : > "$probe" ) 2>/dev/null; then
    rm -f "$probe"
    return 0
  fi
  return 1
}
