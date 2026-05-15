#!/usr/bin/env bats

load helpers/setup
load helpers/fixtures

SESSION_START="$PLUGIN_ROOT/scripts/cc-hooks/session-start.sh"

setup()    { setup_tmp_repo; export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"; }
teardown() { teardown_tmp_repo; }

@test "no-op when gitlore.enabled is missing" {
  run bash "$SESSION_START"
  [ "$status" -eq 0 ]
  [ ! -f .claude/settings.local.json ]
}

@test "no-op when .gitmodules has no gitlore-memory entry" {
  mkdir .claude
  printf '{"gitlore":{"enabled":true}}\n' > .claude/settings.json
  run bash "$SESSION_START"
  [ "$status" -eq 0 ]
  [ ! -f .claude/settings.local.json ]
}

@test "writes autoMemoryDirectory and hooksDir and emits wrappers" {
  make_parent_with_memory
  mkdir -p .claude
  printf '{"gitlore":{"enabled":true}}\n' > .claude/settings.json
  run bash "$SESSION_START"
  [ "$status" -eq 0 ]
  [ -f .claude/settings.local.json ]
  grep -q autoMemoryDirectory .claude/settings.local.json
  [ "$(git config gitlore.hooksDir)" = "$CLAUDE_PLUGIN_ROOT/scripts/git-hooks" ]
  [ -x .git/gitlore-pre-commit ]
  [ -x .git/gitlore-pre-push ]
}
