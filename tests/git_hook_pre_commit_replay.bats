#!/usr/bin/env bats
# Replay-in-progress detection in pre-commit: a rebase, cherry-pick or revert
# marker present in .git must skip the memory sync so the replayed commit
# keeps the memory pointer it recorded (see the comment block in the hook).
# $stderr is populated by bats `run --separate-stderr`; shellcheck cannot see it.
# shellcheck disable=SC2154
bats_require_minimum_version 1.5.0

load helpers/setup
load helpers/fixtures
load helpers/divergence-fixtures
load helpers/tier-fixtures
load helpers/git-hook-pre-commit

# Dirty memory, so a sync (if not skipped) would create a new memory commit —
# that new commit is what would prove the skip failed to short-circuit before
# the sync ran; its absence is what proves the skip held.
_dirty_memory() {
  echo dirty > memory/notes.md
}

@test "a rebase-merge marker skips the memory sync" {
  make_parent_with_memory
  _dirty_memory
  mkdir .git/rebase-merge
  head_before="$(git -C memory rev-parse HEAD)"
  CLAUDECODE=1 run --separate-stderr bash "$HOOK"
  [ "$status" -eq 0 ]
  [[ "${output}${stderr}" == *"rebase is in progress"* ]]
  [ "$(git -C memory rev-parse HEAD)" = "$head_before" ]
}

@test "a rebase-apply marker skips the memory sync" {
  make_parent_with_memory
  _dirty_memory
  mkdir .git/rebase-apply
  head_before="$(git -C memory rev-parse HEAD)"
  CLAUDECODE=1 run --separate-stderr bash "$HOOK"
  [ "$status" -eq 0 ]
  [[ "${output}${stderr}" == *"rebase is in progress"* ]]
  [ "$(git -C memory rev-parse HEAD)" = "$head_before" ]
}

@test "a CHERRY_PICK_HEAD marker skips the memory sync" {
  make_parent_with_memory
  _dirty_memory
  git rev-parse HEAD > .git/CHERRY_PICK_HEAD
  head_before="$(git -C memory rev-parse HEAD)"
  CLAUDECODE=1 run --separate-stderr bash "$HOOK"
  [ "$status" -eq 0 ]
  [[ "${output}${stderr}" == *"cherry-pick is in progress"* ]]
  [ "$(git -C memory rev-parse HEAD)" = "$head_before" ]
}

@test "a REVERT_HEAD marker skips the memory sync" {
  make_parent_with_memory
  _dirty_memory
  git rev-parse HEAD > .git/REVERT_HEAD
  head_before="$(git -C memory rev-parse HEAD)"
  CLAUDECODE=1 run --separate-stderr bash "$HOOK"
  [ "$status" -eq 0 ]
  [[ "${output}${stderr}" == *"revert is in progress"* ]]
  [ "$(git -C memory rev-parse HEAD)" = "$head_before" ]
}

@test "replay detection still fires with a parent repo path containing a space" {
  # See tests/fixture_template.bats for the same TMP_REPO relocation pattern.
  local orig="$TMP_REPO"
  TMP_REPO="$orig/dir with space"
  export TMP_REPO
  mkdir -p "$TMP_REPO"
  cd "$TMP_REPO"
  git init -q -b main
  git config user.email "test@example.com"
  git config user.name  "Test"

  make_parent_with_memory
  _dirty_memory
  git rev-parse HEAD > .git/REVERT_HEAD
  head_before="$(git -C memory rev-parse HEAD)"
  CLAUDECODE=1 run --separate-stderr bash "$HOOK"
  [ "$status" -eq 0 ]
  [[ "${output}${stderr}" == *"revert is in progress"* ]]
  [ "$(git -C memory rev-parse HEAD)" = "$head_before" ]

  TMP_REPO="$orig"
  export TMP_REPO
}
