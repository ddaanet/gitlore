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

# D20: the standalone push entry point is discovered the same way the standalone
# commit one is -- one git-config lookup, no coupling to gitlore's layout -- so a
# caller (the push skill, or handoff wrapping up) can publish memory on its own.
@test "seeds gitlore.pushCommand pointing at push-memory.sh" {
  bash "$WRITE_SETTINGS" "lefthook run pre-commit"
  [ "$(git config gitlore.pushCommand)" = "$PLUGIN_ROOT/scripts/push-memory.sh" ]
  [ -x "$(git config gitlore.pushCommand)" ]
}

@test "seeds gitlore.hooksDir alongside commitCommand" {
  bash "$WRITE_SETTINGS" "lefthook run pre-commit"
  [ "$(git config gitlore.hooksDir)" = "$PLUGIN_ROOT/scripts/git-hooks" ]
}

@test "seeds gitlore.memoryApprovalClauseFile pointing at the reference clause" {
  bash "$WRITE_SETTINGS" "lefthook run pre-commit"
  [ "$(git config gitlore.memoryApprovalClauseFile)" = "$PLUGIN_ROOT/reference/memory-approval-clause.txt" ]
}
