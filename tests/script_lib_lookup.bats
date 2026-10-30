#!/usr/bin/env bats
# shellcheck disable=SC2154  # $output/$status are populated by bats `run`
bats_require_minimum_version 1.5.0

# A script sources the libraries shipped beside itself. `gitlore.hooksDir` is a
# per-repo pin that lags a plugin upgrade, so a script reached by path (the
# blessed entry points are the plugin's bin/ names, which exec them)
# must not follow it to a different tree's libraries. Each case builds a second
# plugin tree whose libraries are wrong in a way that shows, pins the repo's
# `gitlore.hooksDir` into it, and runs the script of THIS tree.

load helpers/setup
load helpers/fixtures

setup() {
  setup_tmp_repo
  unset CLAUDE_PLUGIN_ROOT
}
teardown() {
  teardown_tmp_repo
}

# A plugin tree standing for an older cache: this tree's libraries, minus the
# one function the older release did not have. Prints its root.
# Args: $1 = directory to build under.
make_old_cache() {
  local root="$1"
  mkdir -p "$root/scripts/git-hooks"
  cp -R "$PLUGIN_ROOT/scripts/lib" "$root/scripts/lib"
  # Range delete of the function body; the closing brace is the first column-0 `}`.
  sed '/^gitlore_memory_dirty() {/,/^}/d' "$root/scripts/lib/util.sh" > "$root/util.tmp"
  mv "$root/util.tmp" "$root/scripts/lib/util.sh"
  ! grep -q '^gitlore_memory_dirty' "$root/scripts/lib/util.sh"
  # The simulation is only meaningful while the script under test calls the
  # function the older cache lacks.
  grep -q 'gitlore_memory_dirty' "$PLUGIN_ROOT/scripts/commit-memory.sh"
}

# A plugin tree whose libraries announce themselves and abort when sourced, for
# the scripts that reach no particular function on the path a test can drive.
make_poisoned_cache() {
  local root="$1" lib
  mkdir -p "$root/scripts/git-hooks" "$root/scripts/lib"
  for lib in util log resolve; do
    printf '%s\n' 'echo "STALE-LIB sourced" >&2' 'exit 97' > "$root/scripts/lib/$lib.sh"
  done
}

# Assert the script ran without touching the other tree's libraries.
assert_own_libs() {
  [ "$status" -ne 97 ]
  [[ "$output" != *"STALE-LIB"* ]]
  [[ "$output" != *"command not found"* ]]
}

@test "commit-memory.sh run by path commits with its own libraries when hooksDir pins an older cache" {
  make_parent_with_memory
  make_old_cache "$BATS_TEST_TMPDIR/old"
  git config gitlore.hooksDir "$BATS_TEST_TMPDIR/old/scripts/git-hooks"
  echo dirty > memory/notes.md

  run commit_sections "memory: add notes"
  [ "$status" -eq 0 ]
  [[ "$output" != *"command not found"* ]]
  [ -z "$(git -C memory status --porcelain)" ]
  [ "$(git -C memory log -1 --pretty=%s)" = "memory: add notes" ]
}

@test "commit-memory.sh ignores a CLAUDE_PLUGIN_ROOT pointing at another tree" {
  make_parent_with_memory
  make_poisoned_cache "$BATS_TEST_TMPDIR/old"
  echo dirty > memory/notes.md

  CLAUDE_PLUGIN_ROOT="$BATS_TEST_TMPDIR/old" run commit_sections "memory: add notes"
  assert_own_libs
  [ "$status" -eq 0 ]
  [ "$(git -C memory log -1 --pretty=%s)" = "memory: add notes" ]
}

@test "push-memory.sh sources its own libraries when hooksDir pins another tree" {
  make_parent_with_memory
  make_poisoned_cache "$BATS_TEST_TMPDIR/old"
  git config gitlore.hooksDir "$BATS_TEST_TMPDIR/old/scripts/git-hooks"

  run bash "$PLUGIN_ROOT/scripts/push-memory.sh"
  assert_own_libs
}

@test "merge-memory.sh sources its own libraries when hooksDir pins another tree" {
  make_parent_with_memory
  make_poisoned_cache "$BATS_TEST_TMPDIR/old"
  git config gitlore.hooksDir "$BATS_TEST_TMPDIR/old/scripts/git-hooks"

  run bash "$PLUGIN_ROOT/scripts/merge-memory.sh"
  assert_own_libs
}

@test "git-hooks/pre-push sources its own libraries when hooksDir pins another tree" {
  make_parent_with_memory
  make_poisoned_cache "$BATS_TEST_TMPDIR/old"
  git config gitlore.hooksDir "$BATS_TEST_TMPDIR/old/scripts/git-hooks"

  run bash "$PLUGIN_ROOT/scripts/git-hooks/pre-push" origin "$TMP_REPO" </dev/null
  assert_own_libs
}

# The scripts that used to prefer CLAUDE_PLUGIN_ROOT. A session that froze at an
# older plugin root can leave it naming another tree, and a script run by path
# must still be its own tree's script.

@test "add-tier.sh sources its own libraries when CLAUDE_PLUGIN_ROOT names another tree" {
  make_parent_with_memory
  make_poisoned_cache "$BATS_TEST_TMPDIR/old"

  CLAUDE_PLUGIN_ROOT="$BATS_TEST_TMPDIR/old" run bash "$PLUGIN_ROOT/scripts/add-tier.sh"
  assert_own_libs
}

@test "emit-wrappers.sh sources its own libraries when CLAUDE_PLUGIN_ROOT names another tree" {
  make_parent_with_memory
  make_poisoned_cache "$BATS_TEST_TMPDIR/old"

  CLAUDE_PLUGIN_ROOT="$BATS_TEST_TMPDIR/old" run bash "$PLUGIN_ROOT/scripts/emit-wrappers.sh"
  assert_own_libs
  [ "$status" -eq 0 ]
}

@test "install/create-remote.sh sources its own libraries when CLAUDE_PLUGIN_ROOT names another tree" {
  make_parent_with_memory
  make_poisoned_cache "$BATS_TEST_TMPDIR/old"

  CLAUDE_PLUGIN_ROOT="$BATS_TEST_TMPDIR/old" run bash "$PLUGIN_ROOT/scripts/install/create-remote.sh" memory local
  assert_own_libs
}

@test "install/run.sh sources its own libraries when CLAUDE_PLUGIN_ROOT names another tree" {
  make_poisoned_cache "$BATS_TEST_TMPDIR/old"

  # Once the script is its own tree's, this is a complete install, and its last
  # step writes outside the fixture: `direnv allow` records under XDG_DATA_HOME
  # (default $HOME/.local/share), and without direnv the global shim goes under
  # GITLORE_HOME. Keep every one of them off the real home.
  export HOME="$BATS_TEST_TMPDIR/home"
  export XDG_DATA_HOME="$HOME/.local/share" XDG_CONFIG_HOME="$HOME/.config"
  export GITLORE_HOME="$HOME/.gitlore"
  mkdir -p "$HOME"
  printf '[user]\n\tname = Test\n\temail = test@example.com\n' > "$HOME/.gitconfig"
  CLAUDE_PLUGIN_ROOT="$BATS_TEST_TMPDIR/old" run bash "$PLUGIN_ROOT/scripts/install/run.sh" memory local
  assert_own_libs
  # The install ran to its end (the step that leaves the fixture), not just past the sourcing.
  [ "$status" -eq 0 ]
}

@test "install/write-settings.sh pins the keys at its own tree when CLAUDE_PLUGIN_ROOT names another" {
  make_poisoned_cache "$BATS_TEST_TMPDIR/old"
  own_root=$(cd "$PLUGIN_ROOT" && pwd)

  CLAUDE_PLUGIN_ROOT="$BATS_TEST_TMPDIR/old" run bash "$PLUGIN_ROOT/scripts/install/write-settings.sh"
  [ "$status" -eq 0 ]
  [ "$(git config gitlore.hooksDir)" = "$own_root/scripts/git-hooks" ]
}

@test "install/emit-launcher.sh copies its own tree's shim when CLAUDE_PLUGIN_ROOT names another" {
  make_poisoned_cache "$BATS_TEST_TMPDIR/old"
  mkdir -p "$BATS_TEST_TMPDIR/old/scripts/install"
  echo '# not the shim' > "$BATS_TEST_TMPDIR/old/scripts/install/launcher-shim"

  CLAUDE_PLUGIN_ROOT="$BATS_TEST_TMPDIR/old" run bash "$PLUGIN_ROOT/scripts/install/emit-launcher.sh"
  [ "$status" -eq 0 ]
  diff .gitlore/bin/claude "$PLUGIN_ROOT/scripts/install/launcher-shim"
}

@test "resolve.sh sources its own libraries when CLAUDE_PLUGIN_ROOT names another tree" {
  make_parent_with_memory
  make_poisoned_cache "$BATS_TEST_TMPDIR/old"

  CLAUDE_PLUGIN_ROOT="$BATS_TEST_TMPDIR/old" run bash "$PLUGIN_ROOT/scripts/resolve.sh"
  assert_own_libs
}
