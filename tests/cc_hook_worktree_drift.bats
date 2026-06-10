#!/usr/bin/env bats
bats_require_minimum_version 1.5.0

load helpers/setup
load helpers/fixtures

DRIFT="$PLUGIN_ROOT/scripts/cc-hooks/worktree-drift.sh"

setup()    { setup_tmp_repo; export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"; }
teardown() {
  [ -n "${WT:-}" ] && rm -rf "$WT"
  teardown_tmp_repo
}

enable_gitlore() {
  mkdir -p .claude
  printf '{"gitlore":{"enabled":true}}\n' > .claude/settings.json
}

add_linked_worktree() {
  WT="$TMP_REPO-wt"
  git worktree add -q -b feat-x "$WT" >/dev/null 2>&1
}

@test "EnterWorktree into a linked worktree of a gitlore repo warns of memory drift (D15)" {
  make_parent_with_memory
  enable_gitlore
  add_linked_worktree
  payload=$(jq -nc --arg cwd "$WT" '{tool_name:"EnterWorktree", cwd:$cwd}')
  CLAUDE_PROJECT_DIR="$TMP_REPO" run bash "$DRIFT" <<<"$payload"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.systemMessage | test("worktree")'
  echo "$output" | jq -e '.systemMessage | test("memory")'
}

@test "ExitWorktree back in the launch repo is silent (D15)" {
  make_parent_with_memory
  enable_gitlore
  payload=$(jq -nc --arg cwd "$TMP_REPO" '{tool_name:"ExitWorktree", cwd:$cwd}')
  CLAUDE_PROJECT_DIR="$TMP_REPO" run bash "$DRIFT" <<<"$payload"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "no warning when gitlore is not enabled" {
  make_parent_with_memory
  add_linked_worktree
  payload=$(jq -nc --arg cwd "$WT" '{tool_name:"EnterWorktree", cwd:$cwd}')
  CLAUDE_PROJECT_DIR="$TMP_REPO" run bash "$DRIFT" <<<"$payload"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "no warning when CLAUDE_PROJECT_DIR is unset" {
  make_parent_with_memory
  enable_gitlore
  add_linked_worktree
  payload=$(jq -nc --arg cwd "$WT" '{tool_name:"EnterWorktree", cwd:$cwd}')
  run env -u CLAUDE_PROJECT_DIR bash "$DRIFT" <<<"$payload"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "ignores non-worktree tools" {
  enable_gitlore
  payload=$(jq -nc '{tool_name:"Bash", cwd:"/tmp"}')
  CLAUDE_PROJECT_DIR="$TMP_REPO" run bash "$DRIFT" <<<"$payload"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
