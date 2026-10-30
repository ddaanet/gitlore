#!/usr/bin/env bats

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
}
teardown() { teardown_tmp_repo; }

@test "install + edit memory + commit-memory + parent commit → memory committed, staged and recorded" {
  # 1. Install, and a parent commit so the index starts clean.
  bash "$PLUGIN_ROOT/scripts/install/run.sh" memory
  git commit -q -m "install gitlore"

  # 2. SessionStart fires (simulated).
  bash "$PLUGIN_ROOT/scripts/cc-hooks/session-start.sh"

  # 3. Claude edits memory.
  echo "added during session" >> memory/MEMORY.md

  # The install and SessionStart write files under .claude; the commit adds none.
  claude_before=$(claude_files)

  # 4. Claude commits memory with the approved summary (D58): its own act.
  run bash -c "printf '== memory ==\nmemory: record session edits\n' | '$PLUGIN_ROOT/bin/gitlore-commit'"
  [ "$status" -eq 0 ]
  wt=$(git -C memory rev-parse HEAD)
  live=$(git -C memory rev-parse live)
  [ "$wt" = "$live" ]
  run git -C memory log --oneline
  [[ "$output" == *"record session edits"* ]]
  [ "$(claude_files)" = "$claude_before" ]

  # 5. The script staged the moved gitlink: the parent index is checked BEFORE
  # any parent commit, because nothing else may do it for the script.
  run git diff --cached --name-only
  [[ "$output" == *memory* ]]

  # 6. The next parent commit records it, with no hook involved.
  echo change > tracked.txt
  git add tracked.txt
  git commit -q -m "parent change"
  [ "$(git rev-parse HEAD:memory)" = "$wt" ]
}
