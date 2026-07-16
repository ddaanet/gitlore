#!/usr/bin/env bats

load helpers/setup
load helpers/fixtures

BATCH="$PLUGIN_ROOT/scripts/cc-hooks/memory-commit-batch.sh"

setup() {
  setup_tmp_repo
  export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
}
teardown() { teardown_tmp_repo; }

# The batch payload is unused (the trigger file is the signal), so any JSON works.
run_batch() { printf '{"hook_event_name":"PostToolBatch","tool_calls":[]}' | bash "$BATCH"; }

@test "no-op (exit 0, silent) when gitlore is not configured" {
  run run_batch
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "no-op when no trigger file is present" {
  make_parent_with_memory
  echo dirty > memory/notes.md   # dirty, but nobody asked us to commit
  run run_batch
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ -n "$(git -C memory status --porcelain)" ]   # memory untouched
}

@test "trigger + approved summary commits memory, advances live, consumes both files" {
  make_parent_with_memory
  echo dirty > memory/notes.md
  printf 'memory: record notes\n' > "$(gitlore_commit_msg_file memory)"
  : > "$(gitlore_commit_trigger_file memory)"

  run run_batch
  [ "$status" -eq 0 ]
  [[ "$output" == *"memory committed"* ]]

  # Memory committed and live advanced.
  [ -z "$(git -C memory status --porcelain)" ]
  [ "$(git -C memory rev-parse HEAD)" = "$(git -C memory rev-parse live)" ]
  [ "$(git -C memory log -1 --pretty=%s)" = "memory: record notes" ]
  # Both IPC files consumed.
  [ ! -f "$(gitlore_commit_trigger_file memory)" ]
  [ ! -f "$(gitlore_commit_msg_file memory)" ]
}

@test "trigger without an approved summary keeps the trigger so it self-heals" {
  make_parent_with_memory
  echo dirty > memory/notes.md
  : > "$(gitlore_commit_trigger_file memory)"

  run run_batch
  [ "$status" -eq 0 ]
  [[ "$output" == *"no approved summary"* ]]
  [[ "$output" == *"$(gitlore_commit_msg_file memory)"* ]]
  # Nothing committed, and the trigger is KEPT: the moment the summary is
  # written, the next batch commits transparently (no re-trigger needed).
  [ -n "$(git -C memory status --porcelain)" ]
  [ -f "$(gitlore_commit_trigger_file memory)" ]
}

@test "a locked repo keeps both IPC files so the next batch retries transparently" {
  make_parent_with_memory
  echo dirty > memory/notes.md
  printf 'memory: record notes\n' > "$(gitlore_commit_msg_file memory)"
  : > "$(gitlore_commit_trigger_file memory)"

  # Simulate a held index lock — an expected transient. Don't actually sleep out
  # the retry backoff.
  export GITLORE_GIT_RETRY_SCHEDULE="0 0"
  : > "$(git -C memory rev-parse --git-dir)/index.lock"

  run run_batch
  [ "$status" -eq 0 ]
  [[ "$output" == *"retry"* ]]
  # Nothing committed, and BOTH files survive for the next attempt — no lost
  # approval, no agent action required.
  [ -n "$(git -C memory status --porcelain)" ]
  [ -f "$(gitlore_commit_trigger_file memory)" ]
  [ -f "$(gitlore_commit_msg_file memory)" ]
}

@test "trigger on clean memory reports nothing to commit and consumes the trigger" {
  make_parent_with_memory
  : > "$(gitlore_commit_trigger_file memory)"

  run run_batch
  [ "$status" -eq 0 ]
  [[ "$output" == *"already clean"* ]]
  [ ! -f "$(gitlore_commit_trigger_file memory)" ]
}

@test "no-op in a session-less worktree where the memory worktree is absent" {
  make_parent_with_memory
  WT="$TMP_REPO-wt"
  git worktree add -q -b feat "$WT" >/dev/null 2>&1
  [ ! -e "$WT/memory/.git" ]
  cd "$WT"
  # A trigger is present, yet the guard must fire first: no memory worktree here.
  mkdir -p "$(dirname "$(gitlore_commit_trigger_file memory)")"
  : > "$(gitlore_commit_trigger_file memory)"
  run run_batch
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  rm -rf "$WT"
}
