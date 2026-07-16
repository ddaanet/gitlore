#!/usr/bin/env bash
# Factories for common test fixtures.

# Create a parent repo with a memory submodule pointing at a local bare repo.
# Args: $1 = memory subpath (default "memory")
make_parent_with_memory() {
  cd "$TMP_REPO" || return 1
  local subpath="${1:-memory}"
  local bare="$TMP_REPO/.bare-memory.git"

  # Seed the bare repo via a temporary clone so it has a valid HEAD.
  local seed_dir
  seed_dir="$(mktemp -d "${TMPDIR:-/tmp}/gitlore-seed.XXXXXX")"
  git init -q -b main "$seed_dir"
  (
    cd "$seed_dir" || exit 1
    git config user.email "test@example.com"
    git config user.name  "Test"
    echo "# memory" > MEMORY.md
    git add MEMORY.md
    git commit -q -m "Initial memory"
  )
  git clone -q --bare "$seed_dir" "$bare"
  rm -rf "$seed_dir"

  git -c protocol.file.allow=always submodule add --name gitlore-memory "$bare" "$subpath" >/dev/null 2>&1
  (
    cd "$subpath" || exit 1
    git config user.email "test@example.com"
    git config user.name  "Test"
    git branch live
    git branch worktree
    git checkout -q worktree
  )
  # The memory commit-message IPC file lives in the parent tree under .claude/
  # (relocated 2026-07-16 from the submodule gitdir). Mirror production: create
  # the dir and gitignore the file so an untracked message never pollutes a
  # parent `git add -A`.
  mkdir -p .claude
  printf '/.claude/gitlore-memory-message\n/.claude/gitlore-commit-memory\n' > .gitignore
  git add .gitmodules "$subpath" .gitignore
  git commit -q -m "Add memory submodule"
}
