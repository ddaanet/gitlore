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

@test "install resumes cleanly after partial prior run (module store absorbed, .gitmodules missing)" {
  # Simulate the state left by a partial install where steps 1-4 of init-submodule.sh
  # completed (gitdir absorbed, gitfile in place) but step 5 (.gitmodules write) was
  # interrupted (e.g. by a sandbox restriction).
  git init -q memory
  git -C memory config user.email "gitlore@local"
  git -C memory config user.name  "gitlore"
  echo "# Memory" > memory/MEMORY.md
  git -C memory add -A
  git -C memory commit -q -m "Initial memory"
  mkdir -p .git/modules/gitlore-memory
  cp -a memory/.git/. .git/modules/gitlore-memory/
  rm -rf memory/.git
  printf 'gitdir: ../.git/modules/gitlore-memory\n' > memory/.git
  git config -f .git/modules/gitlore-memory/config core.worktree "../../../memory"
  # .gitmodules intentionally absent — this is the partial-install state

  run bash "$RUN_INSTALL" memory "echo precommit"
  [ "$status" -eq 0 ]
  [ -f .gitmodules ]
  git config --file .gitmodules submodule.gitlore-memory.path | grep -qx memory
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

@test "install refuses to run from a linked worktree" {
  git commit -q --allow-empty -m "base"
  wt="$TMP_REPO.wt"
  git worktree add -q "$wt"
  cd "$wt"
  run bash "$RUN_INSTALL" memory "echo precommit"
  [ "$status" -ne 0 ]
  [[ "$output" == *"linked worktree"* ]]
  cd "$TMP_REPO"
  git worktree remove --force "$wt" 2>/dev/null || rm -rf "$wt"
}

@test "init-submodule refuses an unchecked-out registered submodule" {
  bash "$RUN_INSTALL" memory "echo precommit"
  git commit --no-verify -q -m "install gitlore"
  # Registered in .gitmodules but not checked out here: empty dir, no .git.
  # Without the guard, git -C memory ops escape up to the parent repo.
  rm -rf memory && mkdir memory
  run bash "$PLUGIN_ROOT/scripts/install/init-submodule.sh" memory
  [ "$status" -ne 0 ]
  [[ "$output" == *"not checked out"* ]]
  # Escape-to-parent symptom: a 'live' branch leaking into the parent repo.
  run git show-ref --verify --quiet refs/heads/live
  [ "$status" -ne 0 ]
}

@test "install migrates pre-existing CC auto-memory at the mangled path" {
  fake_home="$TMP_REPO/.fake-home"
  encoded=$(printf '%s' "$TMP_REPO" | LC_ALL=C sed 's/[^A-Za-z0-9]/-/g')
  mkdir -p "$fake_home/.claude/projects/$encoded/memory"
  printf 'User is a senior engineer working on distributed systems.\n' > "$fake_home/.claude/projects/$encoded/memory/MEMORY.md"
  printf 'fact\n' > "$fake_home/.claude/projects/$encoded/memory/user_role.md"

  HOME="$fake_home" bash "$RUN_INSTALL" memory "echo precommit"
  [ -f memory/MEMORY.md ]
  grep -q "senior engineer" memory/MEMORY.md
  [ -f memory/user_role.md ]
  # migrated content removed from source, replaced by a stub MEMORY.md
  src="$fake_home/.claude/projects/$encoded/memory"
  [ ! -f "$src/user_role.md" ]
  ! grep -q "senior engineer" "$src/MEMORY.md"
  grep -q 'migrated in-tree by `/gitlore:install`' "$src/MEMORY.md"
}

@test "install leaves no stub when there was no auto-memory to migrate" {
  fake_home="$TMP_REPO/.fake-home"
  encoded=$(printf '%s' "$TMP_REPO" | LC_ALL=C sed 's/[^A-Za-z0-9]/-/g')

  # No ~/.claude/projects/<encoded>/memory exists. Install must NOT fabricate a
  # stub dir under the user's real home — there was nothing to migrate.
  HOME="$fake_home" bash "$RUN_INSTALL" memory "echo precommit"
  [ ! -d "$fake_home/.claude/projects/$encoded/memory" ]
}

@test "install migration stub is idempotent across re-runs" {
  fake_home="$TMP_REPO/.fake-home"
  encoded=$(printf '%s' "$TMP_REPO" | LC_ALL=C sed 's/[^A-Za-z0-9]/-/g')
  src="$fake_home/.claude/projects/$encoded/memory"
  stub="$src/MEMORY.md"
  mkdir -p "$src"
  printf 'some migrated fact\n' > "$stub"

  HOME="$fake_home" bash "$RUN_INSTALL" memory "echo precommit"
  grep -q 'migrated in-tree by `/gitlore:install`' "$stub"
  mtime1=$(stat -c '%Y' "$stub" 2>/dev/null || stat -f '%m' "$stub")
  HOME="$fake_home" bash "$RUN_INSTALL" memory "echo precommit"
  mtime2=$(stat -c '%Y' "$stub" 2>/dev/null || stat -f '%m' "$stub")
  # second run recognizes the existing stub and leaves it untouched
  [ "$mtime1" = "$mtime2" ]
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

@test "run.sh self-locates CLAUDE_PLUGIN_ROOT when unset in env" {
  unset CLAUDE_PLUGIN_ROOT
  run --separate-stderr bash "$RUN_INSTALL" memory "echo pc"
  [ "$status" -eq 0 ]
  [ -f .claude/settings.json ]
  [ -d memory ]
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
