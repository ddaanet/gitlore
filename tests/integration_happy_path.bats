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

@test "install + edit memory + commit-msg + parent commit → memory committed and ff-pushed" {
  # 1. Install.
  bash "$PLUGIN_ROOT/scripts/install/run.sh" memory "echo precommit"

  # 2. SessionStart fires (simulated).
  bash "$PLUGIN_ROOT/scripts/cc-hooks/session-start.sh"

  # 3. Claude edits memory.
  echo "added during session" >> memory/MEMORY.md

  # 4. Claude runs the configured pre-commit command (echo precommit). PostToolUse fires.
  payload='{"tool_name":"Bash","tool_input":{"command":"echo precommit"},"tool_response":{"exit_code":0}}'
  out=$(printf '%s' "$payload" | bash "$PLUGIN_ROOT/scripts/cc-hooks/post-tool-use.sh")
  [[ "$out" == *additionalContext* ]]

  # 5. Claude writes the commit-msg file (simulating user approval).
  msgfile=$(git -C memory rev-parse --git-path gitlore-commit-msg)
  printf 'memory: record session edits\n' > "$msgfile"

  # 6. Parent's pre-commit hook fires (driven by the wrapper).
  bash .git/gitlore-pre-commit

  # Assertions.
  [ ! -f "$msgfile" ]
  wt=$(git -C memory rev-parse HEAD)
  live=$(git -C memory rev-parse live)
  [ "$wt" = "$live" ]
  run git -C memory log --oneline
  [[ "$output" == *"record session edits"* ]]
}
