#!/usr/bin/env bash
# Factories for common test fixtures.

# Create a parent repo with a memory submodule pointing at a local bare repo.
# Args: $1 = memory subpath (default "memory")
make_parent_with_memory() {
  local subpath="${1:-memory}"
  local bare="$TMP_REPO/.bare-memory.git"

  # Seed the bare repo via a temporary clone so it has a valid HEAD.
  local seed_dir
  seed_dir="$(mktemp -d "${TMPDIR:-/tmp}/gitlore-seed.XXXXXX")"
  git init -q -b main "$seed_dir"
  (
    cd "$seed_dir"
    git config user.email "test@example.com"
    git config user.name  "Test"
    echo "# memory" > MEMORY.md
    git add MEMORY.md
    git commit -q -m "Initial memory"
  )
  git clone -q --bare "$seed_dir" "$bare"
  rm -rf "$seed_dir"

  git -c protocol.file.allow=always submodule add "$bare" "$subpath" >/dev/null 2>&1
  (
    cd "$subpath"
    git config user.email "test@example.com"
    git config user.name  "Test"
    git branch live
    git branch worktree
    git checkout -q worktree
  )
  git add .gitmodules "$subpath"
  git commit -q -m "Add memory submodule"
}
