#!/usr/bin/env bats

load helpers/setup
load helpers/fixtures

POST="$PLUGIN_ROOT/scripts/cc-hooks/post-tool-use.sh"

setup() {
  setup_tmp_repo
  export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
  make_parent_with_memory
  mkdir -p .claude
  jq -n --arg pc "lefthook run pre-commit" \
     '{gitlore: {enabled:true, precommitCommand:$pc}}' > .claude/settings.json
}
teardown() { teardown_tmp_repo; }

stdin() { printf '%s' "$1" | bash "$POST"; }

@test "no-op when tool_name is not Bash" {
  payload='{"tool_name":"Read","tool_input":{},"tool_response":{"exit_code":0}}'
  run stdin "$payload"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "no-op when command does not match precommit prefix" {
  payload='{"tool_name":"Bash","tool_input":{"command":"echo unrelated"},"tool_response":{"exit_code":0}}'
  run stdin "$payload"
  [ -z "$output" ]
}

@test "no-op when memory is clean" {
  payload='{"tool_name":"Bash","tool_input":{"command":"lefthook run pre-commit"},"tool_response":{"exit_code":0}}'
  run stdin "$payload"
  [ -z "$output" ]
}

@test "emits additionalContext when memory is dirty and matched" {
  echo dirty > memory/notes.md
  payload='{"tool_name":"Bash","tool_input":{"command":"lefthook run pre-commit"},"tool_response":{"exit_code":0}}'
  run stdin "$payload"
  [ "$status" -eq 0 ]
  [[ "$output" == *additionalContext* ]]
  [[ "$output" == *"Summarize pending memory changes"* ]]
}

@test "no-op when commit-msg file is fresh" {
  echo dirty > memory/notes.md
  msgfile=$(git -C memory rev-parse --git-path gitlore-commit-msg)
  printf 'pre-approved\n' > "$msgfile"
  touch "$msgfile"
  payload='{"tool_name":"Bash","tool_input":{"command":"lefthook run pre-commit"},"tool_response":{"exit_code":0}}'
  run stdin "$payload"
  [ -z "$output" ]
}
