#!/usr/bin/env bats
bats_require_minimum_version 1.5.0

load helpers/setup

WRITE_SETTINGS="$PLUGIN_ROOT/scripts/install/write-settings.sh"

setup() {
  setup_tmp_repo
  export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
  # The script pins its own tree, canonical; $PLUGIN_ROOT carries `..`.
  OWN_ROOT=$(cd "$PLUGIN_ROOT" && pwd)
}
teardown() { teardown_tmp_repo; }

# D70: the entry points are the plugin's bin/ names, so install seeds no
# discovery key for them and no approval-clause file key; only hooksDir remains.
@test "seeds gitlore.hooksDir" {
  bash "$WRITE_SETTINGS" "lefthook run pre-commit"
  [ "$(git config gitlore.hooksDir)" = "$OWN_ROOT/scripts/git-hooks" ]
}

@test "seeds no discovery key and no approval-clause key" {
  bash "$WRITE_SETTINGS" "lefthook run pre-commit"
  run git config --local --get-regexp '^gitlore\.(commit|push|merge)command$|^gitlore\.memoryapprovalclausefile$'
  [ "$status" -eq 1 ]
  [ -z "$output" ]
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
