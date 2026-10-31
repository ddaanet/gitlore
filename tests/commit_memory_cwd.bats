#!/usr/bin/env bats
# $stderr is populated by bats `run --separate-stderr`; shellcheck cannot see it.
# shellcheck disable=SC2154
bats_require_minimum_version 1.5.0

load helpers/setup
load helpers/fixtures
load helpers/divergence-fixtures
load helpers/tier-fixtures
load helpers/commit-memory

# Where the launch repo is found when gitlore-commit runs from another cwd.
# Agent Bash carries no CLAUDE_PROJECT_DIR and its cwd persists between calls,
# so the script resolves the repo from wherever the shell sits.

@test "run from a subdirectory of the project it commits the memory store" {
  make_parent_with_memory
  echo dirty > memory/notes.md
  mkdir -p src/deep
  cd src/deep

  unset CLAUDE_PROJECT_DIR
  run commit_sections "memory: add notes from a subdirectory"
  [ "$status" -eq 0 ]
  [ "$(git -C "$TMP_REPO/memory" log -1 --pretty=%s)" = "memory: add notes from a subdirectory" ]
  [ -z "$(git -C "$TMP_REPO/memory" status --porcelain)" ]
}

# Agent Bash carries no CLAUDE_PROJECT_DIR, and its cwd persists into memory/.
@test "run from inside the memory store it commits the memory store" {
  make_parent_with_memory
  echo dirty > memory/notes.md
  cd memory
  unset CLAUDE_PROJECT_DIR

  run commit_sections "memory: add notes from inside the store"
  [ "$status" -eq 0 ]
  [ "$(git -C "$TMP_REPO/memory" log -1 --pretty=%s)" = "memory: add notes from inside the store" ]
}

# A gitlore project that is itself a submodule of an outer repo with no memory.
@test "run from a subdirectory of a project nested in an outer repo commits the project's store" {
  make_parent_with_memory
  mkdir -p subdir
  : > subdir/.keep
  git add subdir
  git commit -q -m "subdir"
  inner="$TMP_REPO"
  outer="$BATS_TEST_TMPDIR/outer"
  git init -q -b main "$outer"
  git -C "$outer" config user.email "test@example.com"
  git -C "$outer" config user.name "Test"
  git -C "$outer" -c protocol.file.allow=always submodule add -q "$inner" proj >/dev/null 2>&1
  git -C "$outer/proj" -c protocol.file.allow=always submodule update -q --init >/dev/null 2>&1
  [ -e "$outer/proj/memory/.git" ]
  [ -n "$(git -C "$outer/proj" rev-parse --show-superproject-working-tree)" ]
  echo dirty > "$outer/proj/memory/notes.md"
  cd "$outer/proj/subdir"
  unset CLAUDE_PROJECT_DIR

  run commit_sections "memory: add notes from a nested project"
  [ "$status" -eq 0 ]
  [ "$(git -C "$outer/proj/memory" log -1 --pretty=%s)" = "memory: add notes from a nested project" ]
}

# A hook-spawned or `!`-mode shell carries CLAUDE_PROJECT_DIR: it names the
# launch repo, whatever directory the shell sits in.
@test "a set CLAUDE_PROJECT_DIR wins over a cwd outside any worktree" {
  make_parent_with_memory
  echo dirty > memory/notes.md
  elsewhere="$BATS_TEST_TMPDIR/elsewhere"
  mkdir -p "$elsewhere"
  cd "$elsewhere"
  run ! git rev-parse --show-toplevel

  CLAUDE_PROJECT_DIR="$TMP_REPO" run --separate-stderr commit_with "== memory ==
memory: add notes via the project dir"
  [ "$status" -eq 0 ]
  [ "$(git -C "$TMP_REPO/memory" log -1 --pretty=%s)" = "memory: add notes via the project dir" ]
}

@test "a CLAUDE_PROJECT_DIR that cannot be entered commits nothing and says so" {
  make_parent_with_memory
  echo dirty > memory/notes.md
  head_before=$(git -C memory rev-parse HEAD)

  CLAUDE_PROJECT_DIR="$BATS_TEST_TMPDIR/no-such-project" run --separate-stderr commit_with "== memory ==
memory: add notes"
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"nothing was committed: the project directory '$BATS_TEST_TMPDIR/no-such-project' cannot be entered"* ]]
  [ "$(git -C memory rev-parse HEAD)" = "$head_before" ]
}
