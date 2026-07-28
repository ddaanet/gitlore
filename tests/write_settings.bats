#!/usr/bin/env bats
bats_require_minimum_version 1.5.0

load helpers/setup

WRITE_SETTINGS="$PLUGIN_ROOT/scripts/install/write-settings.sh"

setup() {
  setup_tmp_repo
  export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
}
teardown() { teardown_tmp_repo; }

@test "seeds gitlore.commitCommand pointing at commit-memory.sh" {
  bash "$WRITE_SETTINGS" "lefthook run pre-commit"
  [ "$(git config gitlore.commitCommand)" = "$PLUGIN_ROOT/scripts/commit-memory.sh" ]
}

@test "seeds gitlore.hooksDir alongside commitCommand" {
  bash "$WRITE_SETTINGS" "lefthook run pre-commit"
  [ "$(git config gitlore.hooksDir)" = "$PLUGIN_ROOT/scripts/git-hooks" ]
}

@test "seeds gitlore.memoryApprovalClauseFile pointing at the reference clause" {
  bash "$WRITE_SETTINGS" "lefthook run pre-commit"
  [ "$(git config gitlore.memoryApprovalClauseFile)" = "$PLUGIN_ROOT/reference/memory-approval-clause.txt" ]
}
