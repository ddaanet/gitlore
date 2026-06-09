#!/usr/bin/env bats
bats_require_minimum_version 1.5.0

load helpers/setup

GATE="$PLUGIN_ROOT/scripts/git-hooks/memory-pre-commit"

setup() {
  setup_tmp_repo
  export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
}
teardown() { teardown_tmp_repo; }

@test "gate passes (exit 0) when GITLORE_MEMORY_COMMIT is set" {
  GITLORE_MEMORY_COMMIT=1 run bash "$GATE"
  [ "$status" -eq 0 ]
}

@test "gate blocks (exit 1) with agent hint when sentinel unset and CLAUDECODE set" {
  CLAUDECODE=1 run --separate-stderr bash "$GATE"
  [ "$status" -eq 1 ]
  [[ "${output}${stderr}" == *"bypass"* ]]
  [[ "${output}${stderr}" == *"commit the PARENT"* ]]
}

@test "gate blocks (exit 1) with user hint when sentinel unset and CLAUDECODE unset" {
  unset CLAUDECODE
  run --separate-stderr bash "$GATE"
  [ "$status" -eq 1 ]
  [[ "${output}${stderr}" == *"Open this project in Claude Code"* ]]
}
