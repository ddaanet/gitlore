#!/usr/bin/env bats

load helpers/setup
load helpers/gh-mock

RUN_INSTALL="$PLUGIN_ROOT/scripts/install/run.sh"

setup() {
  setup_tmp_repo
  export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
  install_gh_mock
  export GH_MOCK_STDOUT_API_USER="alice"
  export GH_MOCK_REMOTE_URL="$TMP_REPO/.fake-gh-remote.git"
  git init -q --bare "$GH_MOCK_REMOTE_URL"
}
teardown() { teardown_tmp_repo; }

@test "install creates gitlore-memory submodule at requested path" {
  run bash "$RUN_INSTALL" memory "echo precommit"
  [ "$status" -eq 0 ]
  [ -d memory ]
  run git config --file .gitmodules submodule.gitlore-memory.path
  [ "$output" = "memory" ]
}

@test "install creates live and worktree branches inside memory" {
  bash "$RUN_INSTALL" memory "echo precommit"
  run git -C memory branch --list live
  [[ "$output" == *live* ]]
  run git -C memory branch --list main  # parent branch is main from setup
  [[ "$output" == *main* ]]
}

@test "install writes settings.json keys" {
  bash "$RUN_INSTALL" memory "lefthook run pre-commit"
  [ "$(jq -r '.gitlore.enabled' .claude/settings.json)" = "true" ]
  [ "$(jq -r '.gitlore.precommitCommand' .claude/settings.json)" = "lefthook run pre-commit" ]
}

@test "install writes wrappers and sentinel" {
  bash "$RUN_INSTALL" memory "echo precommit"
  [ -x .git/gitlore-pre-commit ]
  [ -f .claude/gitlore-hook-setup ]
}

@test "install refuses when memory path exists with content" {
  mkdir memory && touch memory/unrelated.txt
  run bash "$RUN_INSTALL" memory "echo precommit"
  [ "$status" -ne 0 ]
}

@test "install stages all artifacts it claims to leave staged" {
  bash "$RUN_INSTALL" memory "echo precommit"
  staged=$(git diff --cached --name-only)
  [[ "$staged" == *".gitmodules"* ]]
  [[ "$staged" == *"memory"* ]]
  [[ "$staged" == *".claude/settings.json"* ]]
  [[ "$staged" == *".claude/gitlore-hook-setup"* ]]
  [[ "$staged" == *".gitignore"* ]]
  [[ "$staged" == *".gitlore/bin/claude"* ]]
  [[ "$staged" == *".envrc"* ]]
  [ -x .gitlore/bin/claude ]
}

@test "install stages memory as gitlink (mode 160000)" {
  bash "$RUN_INSTALL" memory "echo precommit"
  run git ls-files --stage memory
  [[ "$output" == 160000\ * ]]
}

@test "install does not emit the embedded-git-repository advice" {
  output=$(bash "$RUN_INSTALL" memory "echo precommit" 2>&1)
  [[ "$output" != *"embedded git repository"* ]]
}

@test "install is idempotent" {
  bash "$RUN_INSTALL" memory "echo precommit"
  run bash "$RUN_INSTALL" memory "echo precommit"
  [ "$status" -eq 0 ]
}

@test "install migrates pre-existing CC auto-memory at the mangled path" {
  fake_home="$TMP_REPO/.fake-home"
  encoded=$(printf '%s' "$TMP_REPO" | LC_ALL=C sed 's/[^A-Za-z0-9]/-/g')
  mkdir -p "$fake_home/.claude/projects/$encoded/memory"
  printf 'migrated content\n' > "$fake_home/.claude/projects/$encoded/memory/MEMORY.md"
  printf 'fact\n' > "$fake_home/.claude/projects/$encoded/memory/user_role.md"

  HOME="$fake_home" bash "$RUN_INSTALL" memory "echo precommit"
  [ -f memory/MEMORY.md ]
  [ "$(cat memory/MEMORY.md)" = "migrated content" ]
  [ -f memory/user_role.md ]
}

@test "install removes .gitmodules from .gitignore when present" {
  printf '.bash_profile\n.gitmodules\n.mcp.json\n' > .gitignore
  git add .gitignore
  git commit -q -m "Ignore sandbox artifacts"
  run bash "$RUN_INSTALL" memory "echo precommit"
  [ "$status" -eq 0 ]
  ! grep -qx '\.gitmodules' .gitignore
  grep -qx '\.bash_profile' .gitignore  # other entries preserved
  staged=$(git diff --cached --name-only)
  [[ "$staged" == *".gitmodules"* ]]
}

@test "preflight warns when CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS is unset" {
  unset CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS
  run --separate-stderr bash "$PLUGIN_ROOT/scripts/install/preflight.sh"
  [ "$status" -eq 0 ]
  [[ "$output$stderr" == *"AGENT_TEAMS"* ]] || [[ "$output$stderr" == *"experimental"* ]]
}

@test "preflight is silent when CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1" {
  export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1
  run --separate-stderr bash "$PLUGIN_ROOT/scripts/install/preflight.sh"
  [ "$status" -eq 0 ]
  [[ "$output$stderr" != *"AGENT_TEAMS"* ]]
}
