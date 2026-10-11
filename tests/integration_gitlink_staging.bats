#!/usr/bin/env bats
# `commit-memory.sh` stages the memory gitlink it just moved into the parent
# index (D58), so the next parent commit records the pointer with no hook.
#
# Without the staging the parent records the PRE-commit memory SHA: every parent
# commit would lag one memory commit behind, and a fresh clone at any commit
# would restore stale memory.
#
# The staged set is read straight after `commit-memory.sh`, BEFORE any parent
# commit: the installed wiring must not be what stages it. A "nothing staged"
# assertion is always paired with one that shows the memory commit landed, since
# an absence alone also holds when the script did nothing.
#
# The `index.lock` case forces a failed `git add` the way a concurrent git
# process does. Wording of the staging report is unspecified, so it is matched
# loosely (`*stag*`).

load helpers/setup
load helpers/gh-mock

setup() {
  setup_tmp_repo
  export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
  export CLAUDECODE=1
  install_gh_mock
  export GH_MOCK_STDOUT_API_USER="alice"
  export GH_MOCK_REMOTE_URL="$TMP_REPO/.fake-gh-remote.git"
  git init -q --bare "$GH_MOCK_REMOTE_URL"
  bash "$PLUGIN_ROOT/scripts/install/run.sh" memory
  git commit -q -m "install gitlore"
  bash "$PLUGIN_ROOT/scripts/cc-hooks/session-start.sh"
}
teardown() { teardown_tmp_repo; }

dirty_memory() { echo "fact from this session" >> memory/MEMORY.md; }

@test "commit-memory -m stages the moved gitlink in the parent index" {
  before=$(git -C memory rev-parse HEAD)
  dirty_memory
  run bash "$CLAUDE_PLUGIN_ROOT/scripts/commit-memory.sh" -m "memory: record a fact"
  [ "$status" -eq 0 ]
  [ "$(git -C memory rev-parse HEAD)" != "$before" ]
  run git diff --cached --name-only
  [ "$status" -eq 0 ]
  [ "$output" = "memory" ]
}

@test "a plain parent commit after commit-memory records the memory pointer" {
  dirty_memory
  bash "$CLAUDE_PLUGIN_ROOT/scripts/commit-memory.sh" -m "memory: record a fact"
  run git diff --cached --name-only
  [ "$output" = "memory" ]
  git commit -q -m "record memory only"
  [ "$(git rev-parse HEAD:memory)" = "$(git -C memory rev-parse HEAD)" ]
}

@test "a run with nothing to commit stages nothing, even over a stale index" {
  dirty_memory
  bash "$CLAUDE_PLUGIN_ROOT/scripts/commit-memory.sh" -m "memory: record a fact"
  run git diff --cached --name-only
  [ "$output" = "memory" ]
  git commit -q -m "record memory only"
  # Move memory again, then put the index back on the old pointer: an
  # unconditional `git add` in a no-op run would now change the index.
  dirty_memory
  bash "$CLAUDE_PLUGIN_ROOT/scripts/commit-memory.sh" -m "memory: record another fact"
  git reset -q -- memory
  run git diff --name-only
  [ "$output" = "memory" ]
  [ -z "$(git diff --cached --name-only)" ]
  head=$(git -C memory rev-parse HEAD)

  run bash "$CLAUDE_PLUGIN_ROOT/scripts/commit-memory.sh" -m "memory: nothing new"
  [ "$status" -eq 0 ]
  [ "$(git -C memory rev-parse HEAD)" = "$head" ]
  [ -z "$(git diff --cached --name-only)" ]
}

@test "a failed staging is reported and the script still exits 0, the commit having landed" {
  before=$(git -C memory rev-parse HEAD)
  dirty_memory
  : > "$(git rev-parse --git-path index.lock)"

  run bash "$CLAUDE_PLUGIN_ROOT/scripts/commit-memory.sh" -m "memory: record a fact"
  rm -f "$(git rev-parse --git-path index.lock)"
  [ "$status" -eq 0 ]
  [[ "$output" == *stag* ]]
  # The memory commit landed and live moved; only the pointer floats (D46).
  [ "$(git -C memory rev-parse HEAD)" != "$before" ]
  [ "$(git -C memory rev-parse HEAD)" = "$(git -C memory rev-parse live)" ]
  [ -z "$(git diff --cached --name-only)" ]
}
