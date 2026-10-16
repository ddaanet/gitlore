#!/usr/bin/env bats
# $stderr is populated by bats `run --separate-stderr`; shellcheck cannot see it.
# shellcheck disable=SC2154
bats_require_minimum_version 1.5.0

# The install's migration of a pre-existing Claude Code auto-memory dir, split
# from install_run.bats; each test points HOME at its own fake home.

load helpers/setup
load helpers/gh-mock

RUN_INSTALL="$PLUGIN_ROOT/scripts/install/run.sh"

setup() {
  setup_tmp_repo
  isolate_home
  export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
  install_gh_mock
  export GH_MOCK_STDOUT_API_USER="alice"
  export GH_MOCK_REMOTE_URL="$TMP_REPO/.fake-gh-remote.git"
  git init -q --bare "$GH_MOCK_REMOTE_URL"
}
teardown() { teardown_tmp_repo; }

@test "install migrates pre-existing CC auto-memory at the mangled path" {
  fake_home="$TMP_REPO/.fake-home"
  encoded=$(printf '%s' "$TMP_REPO" | LC_ALL=C sed 's/[^A-Za-z0-9]/-/g')
  mkdir -p "$fake_home/.claude/projects/$encoded/memory"
  printf '[user]\n\tname = Test\n\temail = test@example.com\n' > "$fake_home/.gitconfig"
  printf 'User is a senior engineer working on distributed systems.\n' > "$fake_home/.claude/projects/$encoded/memory/MEMORY.md"
  printf 'fact\n' > "$fake_home/.claude/projects/$encoded/memory/user_role.md"

  run env HOME="$fake_home" bash "$RUN_INSTALL" memory
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
  HOME="$fake_home" bash "$RUN_INSTALL" memory
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

  run env HOME="$fake_home" bash "$RUN_INSTALL" memory
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

@test "install scaffolds the root index when the migrated auto-memory carried none" {
  # An auto-memory dir holding facts but no MEMORY.md — a session interrupted
  # before Claude Code wrote the index, or a dir whose index was deleted. The
  # emptiness guard passes it to the copy, and the copy brings no index: every
  # later compose, check and merge path keys on a file that would not be there.
  fake_home="$TMP_REPO/.fake-home"
  encoded=$(printf '%s' "$TMP_REPO" | LC_ALL=C sed 's/[^A-Za-z0-9]/-/g')
  src="$fake_home/.claude/projects/$encoded/memory"
  mkdir -p "$src"
  printf '[user]\n\tname = Test\n\temail = test@example.com\n' > "$fake_home/.gitconfig"
  printf 'fact\n' > "$src/user_role.md"

  run env HOME="$fake_home" bash "$RUN_INSTALL" memory
  [ "$status" -eq 0 ]
  # The facts migrated, and the announcement still fires: this is the migration
  # branch with a scaffold added, not a fall-through to the scaffold branch.
  [[ "$output" == *"migrated auto-memory from"* ]]
  [ -f memory/user_role.md ]
  grep -qx '# Memory Index' memory/MEMORY.md
  git -C memory cat-file -e HEAD:MEMORY.md
}

@test "install migration stub is idempotent across re-runs" {
  fake_home="$TMP_REPO/.fake-home"
  encoded=$(printf '%s' "$TMP_REPO" | LC_ALL=C sed 's/[^A-Za-z0-9]/-/g')
  src="$fake_home/.claude/projects/$encoded/memory"
  stub="$src/MEMORY.md"
  mkdir -p "$src"
  printf '[user]\n\tname = Test\n\temail = test@example.com\n' > "$fake_home/.gitconfig"
  printf 'some migrated fact\n' > "$stub"

  HOME="$fake_home" bash "$RUN_INSTALL" memory
  # backticks are literal text in the stub; single quotes are intentional.
  # shellcheck disable=SC2016
  grep -q 'migrated in-tree by `/gitlore:install`' "$stub"
  mtime1=$(stat -c '%Y' "$stub" 2>/dev/null || stat -f '%m' "$stub")
  HOME="$fake_home" bash "$RUN_INSTALL" memory
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

  HOME="$fake_home" bash "$RUN_INSTALL" memory
  [ -f memory/MEMORY.md ]
  grep -q '# Memory Index' memory/MEMORY.md
  run grep -q 'migrated in-tree' memory/MEMORY.md
  [ "$status" -ne 0 ]
  run grep -q 'Do not add memory here' memory/MEMORY.md
  [ "$status" -ne 0 ]
}
