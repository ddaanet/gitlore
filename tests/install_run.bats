#!/usr/bin/env bats
# $stderr is populated by bats `run --separate-stderr`; shellcheck cannot see it.
# shellcheck disable=SC2154
bats_require_minimum_version 1.5.0

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

@test "install works with a multi-component mempath (.claude/memory is a documented, supported layout)" {
  # The gitfile's "gitdir:" target is relative to the gitfile's own location, so
  # it depends on how many path components mempath has — a fixed one-component
  # "../" breaks for a nested path.
  run bash "$RUN_INSTALL" .claude/memory "echo precommit"
  [ "$status" -eq 0 ]
  [ -f .claude/memory/.git ]
  [[ "$(cat .claude/memory/.git)" == "gitdir: ../../.git/modules/gitlore-memory" ]]
  # The gitfile resolves: an ordinary git command in the submodule must not error.
  git -C .claude/memory rev-parse HEAD
  [ "$(git -C .claude/memory rev-parse HEAD)" = "$(git -C .claude/memory rev-parse live)" ]
}

@test "install creates the live trunk and leaves memory detached at it" {
  bash "$RUN_INSTALL" memory "echo precommit"
  run git -C memory branch --list live
  [[ "$output" == *live* ]]
  # Branch model (D17): no per-parent-branch working branch is created, and HEAD
  # is detached at live rather than attached to any branch.
  run git -C memory symbolic-ref -q HEAD
  [ "$status" -ne 0 ]
  [ "$(git -C memory rev-parse HEAD)" = "$(git -C memory rev-parse live)" ]
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

@test "the already-registered check treats mempath as a literal, not a regex" {
  # `grep -qx "$mempath"` (no -F) reads mempath as a pattern: a `.` matches any
  # character, so once "memory" is registered, a DIFFERENT, unrelated,
  # non-empty path like "mem.ry" is misread as "already our submodule" and the
  # non-empty-path refusal is skipped — the confusing "not checked out here"
  # error fires instead of the correct one.
  bash "$RUN_INSTALL" memory "echo precommit"
  mkdir -p "mem.ry" && echo unrelated > "mem.ry/file.txt"
  run bash "$RUN_INSTALL" "mem.ry" "echo precommit"
  [ "$status" -ne 0 ]
  [[ "$output" == *"exists and is not empty"* ]]
  [[ "$output" != *"not checked out here"* ]]
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
  # Paired over one fixture. The advice is git's, not gitlore's, so the only
  # way to pin that the refuted string is still live — and that a nested store
  # in THIS repo reaches the producer at all — is to stage one the plain way
  # first. Install then differs in exactly one thing, registering the store as a
  # gitlink, and must come out silent.
  git init -q -b main nested
  git -C nested config user.email test@example.com
  git -C nested config user.name Test
  printf 'x\n' > nested/f
  git -C nested add f
  git -C nested commit -qm x
  run --separate-stderr git add nested
  [[ "$output$stderr" == *"$GITLORE_T_EMBEDDED_REPO"* ]]
  git rm -q --cached -rf nested   # -f: the repo has no HEAD to compare against
  rm -rf nested

  output=$(bash "$RUN_INSTALL" memory "echo precommit" 2>&1)
  [[ "$output" != *"$GITLORE_T_EMBEDDED_REPO"* ]]
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
  printf '[user]\n\tname = Test\n\temail = test@example.com\n' > "$fake_home/.gitconfig"
  printf 'User is a senior engineer working on distributed systems.\n' > "$fake_home/.claude/projects/$encoded/memory/MEMORY.md"
  printf 'fact\n' > "$fake_home/.claude/projects/$encoded/memory/user_role.md"

  run env HOME="$fake_home" bash "$RUN_INSTALL" memory "echo precommit"
  [ "$status" -eq 0 ]
  # The announcement commands/install.md keys its review step on: without it,
  # an install that seeded real facts is indistinguishable from a scaffold.
  [[ "$output" == *"migrated auto-memory from"* ]]
  [ -f memory/MEMORY.md ]
  grep -q "senior engineer" memory/MEMORY.md
  [ -f memory/user_role.md ]
  # migrated content removed from source, replaced by a stub MEMORY.md
  src="$fake_home/.claude/projects/$encoded/memory"
  [ ! -f "$src/user_role.md" ]
  run grep -q "senior engineer" "$src/MEMORY.md"
  [ "$status" -ne 0 ]
  # backticks are literal text in the stub; single quotes are intentional.
  # shellcheck disable=SC2016
  grep -q 'migrated in-tree by `/gitlore:install`' "$src/MEMORY.md"
}

@test "install leaves no stub when there was no auto-memory to migrate" {
  fake_home="$TMP_REPO/.fake-home"
  encoded=$(printf '%s' "$TMP_REPO" | LC_ALL=C sed 's/[^A-Za-z0-9]/-/g')
  mkdir -p "$fake_home"
  printf '[user]\n\tname = Test\n\temail = test@example.com\n' > "$fake_home/.gitconfig"

  # No ~/.claude/projects/<encoded>/memory exists. Install must NOT fabricate a
  # stub dir under the user's real home — there was nothing to migrate.
  HOME="$fake_home" bash "$RUN_INSTALL" memory "echo precommit"
  [ ! -d "$fake_home/.claude/projects/$encoded/memory" ]
}

@test "install seeds the scaffold when the auto-memory dir exists but is empty" {
  fake_home="$TMP_REPO/.fake-home"
  encoded=$(printf '%s' "$TMP_REPO" | LC_ALL=C sed 's/[^A-Za-z0-9]/-/g')
  # Dir exists (e.g. from a prior failed install) but holds nothing. There is
  # no memory to migrate, so this is the scaffold branch: a store seeded from
  # an empty dir has no root index, and every later compose and merge path
  # assumes one — the continuation used to die on `add -- MEMORY.md` there.
  src="$fake_home/.claude/projects/$encoded/memory"
  mkdir -p "$src"
  printf '[user]\n\tname = Test\n\temail = test@example.com\n' > "$fake_home/.gitconfig"

  run env HOME="$fake_home" bash "$RUN_INSTALL" memory "echo precommit"
  [ "$status" -eq 0 ]
  # Scaffolded, so there is nothing for the review step to hold against the
  # skill — and no announcement to trigger it.
  [[ "$output" != *"migrated auto-memory from"* ]]
  grep -qx '# Memory Index' memory/MEMORY.md
  git -C memory cat-file -e HEAD:MEMORY.md
  # The breadcrumb still lands, so a shimless session finds it rather than
  # writing into the empty dir; nothing was migrated, so it is not announced.
  # shellcheck disable=SC2016  # backticks are literal text in the stub
  grep -q 'migrated in-tree by `/gitlore:install`' "$src/MEMORY.md"
}

@test "install migration stub is idempotent across re-runs" {
  fake_home="$TMP_REPO/.fake-home"
  encoded=$(printf '%s' "$TMP_REPO" | LC_ALL=C sed 's/[^A-Za-z0-9]/-/g')
  src="$fake_home/.claude/projects/$encoded/memory"
  stub="$src/MEMORY.md"
  mkdir -p "$src"
  printf '[user]\n\tname = Test\n\temail = test@example.com\n' > "$fake_home/.gitconfig"
  printf 'some migrated fact\n' > "$stub"

  HOME="$fake_home" bash "$RUN_INSTALL" memory "echo precommit"
  # backticks are literal text in the stub; single quotes are intentional.
  # shellcheck disable=SC2016
  grep -q 'migrated in-tree by `/gitlore:install`' "$stub"
  mtime1=$(stat -c '%Y' "$stub" 2>/dev/null || stat -f '%m' "$stub")
  HOME="$fake_home" bash "$RUN_INSTALL" memory "echo precommit"
  mtime2=$(stat -c '%Y' "$stub" 2>/dev/null || stat -f '%m' "$stub")
  # second run recognizes the existing stub and leaves it untouched
  [ "$mtime1" = "$mtime2" ]
}

@test "install seeds the scaffold, not the migration stub, when the source is an already-migrated stub" {
  fake_home="$TMP_REPO/.fake-home"
  encoded=$(printf '%s' "$TMP_REPO" | LC_ALL=C sed 's/[^A-Za-z0-9]/-/g')
  src="$fake_home/.claude/projects/$encoded/memory"
  mkdir -p "$src"
  printf '[user]\n\tname = Test\n\temail = test@example.com\n' > "$fake_home/.gitconfig"
  # A prior install/run left the migration breadcrumb at the source. It is NOT
  # real memory — install must fall through to the scaffold, never seed the
  # submodule with "Do not add memory here".
  cat > "$src/MEMORY.md" <<'EOF'
# Memory migrated in-tree

This project's auto-memory was migrated in-tree by `/gitlore:install`. It now
lives in the `gitlore-memory` submodule, versioned in git alongside the code.

Do not add memory here.
EOF

  HOME="$fake_home" bash "$RUN_INSTALL" memory "echo precommit"
  [ -f memory/MEMORY.md ]
  grep -q '# Memory Index' memory/MEMORY.md
  run grep -q 'migrated in-tree' memory/MEMORY.md
  [ "$status" -ne 0 ]
  run grep -q 'Do not add memory here' memory/MEMORY.md
  [ "$status" -ne 0 ]
}

@test "install removes .gitmodules from .gitignore when present" {
  printf '.bash_profile\n.gitmodules\n.mcp.json\n' > .gitignore
  git add .gitignore
  git commit -q -m "Ignore sandbox artifacts"
  run bash "$RUN_INSTALL" memory "echo precommit"
  [ "$status" -eq 0 ]
  run grep -qx '\.gitmodules' .gitignore
  [ "$status" -ne 0 ]
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
  # The exact name the silent case refutes. A disjunction here would let the
  # warning drop the variable name and still satisfy this, leaving the negative
  # below watching a string nothing emits.
  [[ "$output$stderr" == *"CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS"* ]]
}

@test "preflight is silent when CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1" {
  export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1
  run --separate-stderr bash "$PLUGIN_ROOT/scripts/install/preflight.sh"
  [ "$status" -eq 0 ]
  [[ "$output$stderr" != *"AGENT_TEAMS"* ]]
}

@test "install does not leave a stray blank line in .gitignore" {
  printf 'node_modules\n' > .gitignore
  bash "$RUN_INSTALL" memory "echo pc"
  # Verify the entries we expect are present
  grep -qx '.claude/settings.local.json' .gitignore
  grep -qx 'node_modules' .gitignore
  # Verify there are no empty lines (lines matching nothing — a line with only whitespace)
  run grep -qE '^\s*$' .gitignore
  [ "$status" -ne 0 ]
}

@test "run.sh fails loudly with a paste-able command when repo root is unwritable" {
  # Make the git common dir unwritable so the probe trips before any mutation.
  chmod 555 .git
  run --separate-stderr bash "$RUN_INSTALL" memory "echo pc"
  chmod 755 .git   # restore for teardown
  [ "$status" -ne 0 ]
  [[ "$stderr" == *"sandbox"* ]]
  [[ "$stderr" == *"$RUN_INSTALL"* ]]
  # Nothing was created before the loud failure.
  [ ! -d memory ]
  [ ! -f .claude/settings.json ]
}
