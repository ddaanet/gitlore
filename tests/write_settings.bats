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

@test "seeds gitlore.mergeCommand pointing at merge-memory.sh" {

  bash "$WRITE_SETTINGS" "lefthook run pre-commit"
  [ "$(git config gitlore.mergeCommand)" = "$PLUGIN_ROOT/scripts/merge-memory.sh" ]
  [ -x "$(git config gitlore.mergeCommand)" ]
}

@test "seeds gitlore.hooksDir alongside commitCommand" {
  bash "$WRITE_SETTINGS" "lefthook run pre-commit"
  [ "$(git config gitlore.hooksDir)" = "$PLUGIN_ROOT/scripts/git-hooks" ]
}

@test "seeds gitlore.memoryApprovalClauseFile pointing at the reference clause" {
  bash "$WRITE_SETTINGS" "lefthook run pre-commit"
  [ "$(git config gitlore.memoryApprovalClauseFile)" = "$PLUGIN_ROOT/reference/memory-approval-clause.txt" ]
}

@test "merging into an existing settings.json keeps its file mode" {
  mkdir -p .claude
  printf '{"a":1}\n' > .claude/settings.json
  chmod 644 .claude/settings.json
  bash "$WRITE_SETTINGS" "just precommit"
  [ "$(find .claude/settings.json -perm 644)" = ".claude/settings.json" ]
  [ "$(jq -r .a .claude/settings.json)" = "1" ]
  [ "$(jq -r .gitlore.enabled .claude/settings.json)" = "true" ]
}

# D58: a memory commit is the agent's own act, so there is no precommit command
# to nudge toward. The argument is passed anyway: a script that still accepts it
# must not record it. The exact key set is asserted, so any stray key fails.
@test "a fresh settings.json carries exactly the enabled key under gitlore" {
  bash "$WRITE_SETTINGS" "just precommit"
  [ "$(jq -c '.gitlore | keys' .claude/settings.json)" = '["enabled"]' ]
  [ "$(jq -r .gitlore.enabled .claude/settings.json)" = "true" ]
}

@test "merging into an existing settings.json leaves exactly the enabled key under gitlore" {
  mkdir -p .claude
  printf '{"a":1}\n' > .claude/settings.json
  bash "$WRITE_SETTINGS" "just precommit"
  [ "$(jq -c '.gitlore | keys' .claude/settings.json)" = '["enabled"]' ]
  [ "$(jq -r .a .claude/settings.json)" = "1" ]
}

@test "an existing settings.json holding a stale gitlore key loses it and keeps the others" {
  mkdir -p .claude
  printf '{"a":1,"gitlore":{"enabled":false,"%s":"just precommit","other":"kept"}}\n' "$(printf 'precommit%s' Command)" > .claude/settings.json
  bash "$WRITE_SETTINGS" "just precommit"
  [ "$(jq -c '.gitlore | keys' .claude/settings.json)" = '["enabled","other"]' ]
  [ "$(jq -r .gitlore.enabled .claude/settings.json)" = "true" ]
  [ "$(jq -r .gitlore.other .claude/settings.json)" = "kept" ]
  [ "$(jq -r .a .claude/settings.json)" = "1" ]
}

@test "the .gitignore entry is matched literally, not as a regex" {
  printf 'Xclaude/settings.local.json\n' > .gitignore
  bash "$WRITE_SETTINGS" "just precommit"
  grep -qxF '.claude/settings.local.json' .gitignore
}
