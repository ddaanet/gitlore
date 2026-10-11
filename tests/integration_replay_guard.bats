#!/usr/bin/env bats
# While a rebase, cherry-pick or revert is replaying in the superproject,
# `commit-memory.sh` commits memory but does not stage the gitlink, and says so.
#
# Staging is right for a commit being authored now and wrong for one being
# replayed: the memory worktree does not move when the parent's HEAD does, so a
# replayed commit would be re-pinned to memory's CURRENT SHA instead of the one
# it originally recorded (D58).
#
# MERGE_HEAD is deliberately NOT a replay marker: a merge commit is authored now
# and must pin current memory, so a script run mid-merge stages the pointer.
#
# The assertion that fails without the guard is the OUTPUT: the operation name
# plus a word matching `*skip*`. Absence of staging alone would also hold for a
# script that never stages. The wording is unspecified, so it is matched loosely.
#
# The staged set is read straight after the script, before any parent commit, and
# each replay case then commits by hand at the stop (`rebase --continue` does not
# run pre-commit hooks, so it proves nothing about them). The gitlink the
# replayed commit records must be the one it had.

load helpers/setup
load helpers/gh-mock

setup() {
  setup_tmp_repo
  export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
  export CLAUDECODE=1
  export GIT_EDITOR=true
  install_gh_mock
  export GH_MOCK_STDOUT_API_USER="alice"
  export GH_MOCK_REMOTE_URL="$TMP_REPO/.fake-gh-remote.git"
  git init -q --bare "$GH_MOCK_REMOTE_URL"
  bash "$PLUGIN_ROOT/scripts/install/run.sh" memory
  git commit -q -m "install gitlore"
  bash "$PLUGIN_ROOT/scripts/cc-hooks/session-start.sh"
}
teardown() { teardown_tmp_repo; }

commit_memory() {
  echo "fact from this session" >> memory/MEMORY.md
  bash "$CLAUDE_PLUGIN_ROOT/scripts/commit-memory.sh" -m "memory: record a fact"
}

# Two branches whose tips conflict, so replaying one onto the other stops.
setup_conflicting_history() {
  echo base > f.txt
  git add f.txt
  git commit -q -m "base"
  git checkout -q -b topic
  echo topic > f.txt
  git commit -q -a -m "topic change"
  git checkout -q main
  echo main > f.txt
  git commit -q -a -m "main change"
}

resolve_conflict() {
  echo resolved > f.txt
  git add f.txt
}

# The memory commit landed, the gitlink was left alone, and the output says why.
assert_replay_skipped() {
  local op="$1" before="$2"
  [ "$status" -eq 0 ]
  [[ "$output" == *"$op"* ]]
  [[ "$output" == *skip* ]]
  [ "$(git -C memory rev-parse HEAD)" != "$before" ]
  [ "$(git -C memory rev-parse HEAD)" = "$(git -C memory rev-parse live)" ]
  run git diff --cached --name-only
  [[ "$output" != *memory* ]]
}

@test "a rebase stopped on a conflict: memory is committed, not staged, and the skip is reported" {
  setup_conflicting_history
  git checkout -q topic
  recorded_before=$(git rev-parse HEAD:memory)
  memory_before=$(git -C memory rev-parse HEAD)

  run git rebase main
  [ -d "$(git rev-parse --git-path rebase-merge)" ]
  resolve_conflict
  run commit_memory
  assert_replay_skipped rebase "$memory_before"

  git commit -q -m "replayed topic change"
  [ "$(git rev-parse HEAD:memory)" = "$recorded_before" ]
}

@test "a rebase using the apply backend reports the skip too" {
  setup_conflicting_history
  git checkout -q topic
  memory_before=$(git -C memory rev-parse HEAD)

  run git rebase --apply main
  [ -d "$(git rev-parse --git-path rebase-apply)" ]
  resolve_conflict
  run commit_memory
  assert_replay_skipped rebase "$memory_before"
}

@test "a conflicted cherry-pick: memory is committed, not staged, and the skip is reported" {
  setup_conflicting_history
  recorded_before=$(git rev-parse HEAD:memory)
  memory_before=$(git -C memory rev-parse HEAD)

  run git cherry-pick topic
  [ -e "$(git rev-parse --git-path CHERRY_PICK_HEAD)" ]
  resolve_conflict
  run commit_memory
  assert_replay_skipped cherry-pick "$memory_before"

  run git cherry-pick --continue
  [ "$status" -eq 0 ]
  [ "$(git rev-parse HEAD:memory)" = "$recorded_before" ]
}

@test "a conflicted revert: memory is committed, not staged, and the skip is reported" {
  setup_conflicting_history
  echo later > f.txt
  git commit -q -a -m "later change"
  recorded_before=$(git rev-parse HEAD:memory)
  memory_before=$(git -C memory rev-parse HEAD)

  run git revert HEAD~1
  [ -e "$(git rev-parse --git-path REVERT_HEAD)" ]
  resolve_conflict
  run commit_memory
  assert_replay_skipped revert "$memory_before"

  run git revert --continue
  [ "$status" -eq 0 ]
  [ "$(git rev-parse HEAD:memory)" = "$recorded_before" ]
}

@test "a conflicted merge is authored now, so the script stages the current pointer" {
  # MERGE_HEAD is present but this is not a replay: the commit is new.
  setup_conflicting_history
  run git merge topic
  resolve_conflict
  run commit_memory
  [ "$status" -eq 0 ]
  [[ "$output" != *skip* ]]
  run git diff --cached --name-only
  [[ "$output" == *memory* ]]

  git commit -q -m "merge topic"
  [ "$(git rev-parse HEAD:memory)" = "$(git -C memory rev-parse HEAD)" ]
}
