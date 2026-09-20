#!/usr/bin/env bats
# $stderr is populated by bats `run --separate-stderr`; shellcheck cannot see it.
# shellcheck disable=SC2154
bats_require_minimum_version 1.5.0

load helpers/setup
load helpers/fixtures

setup() {
  # Point the template cache at this test's own tmpdir so the suite's real
  # run-wide template is neither read nor disturbed.
  BATS_RUN_TMPDIR="$BATS_TEST_TMPDIR/run"
  mkdir -p "$BATS_RUN_TMPDIR"
  CACHE="$(_gitlore_fixture_cache_dir)"
  TEMPLATE="$CACHE/parent-with-memory"
  READY="$TEMPLATE.ready"
  LOCK="$TEMPLATE.building"
  BUILDS="$BATS_TEST_TMPDIR/builds"
  : > "$BUILDS"
  setup_tmp_repo
}
teardown() { teardown_tmp_repo; }

# Stand-in for the 13-git-subprocess builder: records each call and keeps the
# real one's first, destructive act, so a spurious rebuild wrecks an existing
# template here exactly as it would in the suite.
# shellcheck disable=SC2317  # invoked indirectly, through the function under test
_gitlore_build_parent_with_memory() {
  rm -rf "$1"
  echo "build" >> "$BUILDS"
  mkdir -p "$1/memory"
  : > "$1/marker"
}

# Pairs with the no-rebuild test below: without this, a stub that was never
# wired in would leave $BUILDS empty and let that test pass vacuously.
@test "the first caller builds the template once and publishes it" {
  run -0 _gitlore_ensure_parent_with_memory_template
  [ "$output" = "$TEMPLATE" ]
  [ "$(wc -l < "$BUILDS")" -eq 1 ]
  [ -f "$READY" ]
  [ ! -d "$LOCK" ]
}

@test "a caller that takes the lock after the winner published does not rebuild" {
  # The race, reproduced exactly: the winning caller publishes .ready and
  # releases the lock inside the window between this caller's `[ ! -f $ready ]`
  # check and its `mkdir "$lock"`. Shadowing mkdir places us in that window and
  # changes nothing else about the function under test.
  mkdir() {
    if [ "${1:-}" = "$LOCK" ]; then
      command mkdir -p "$TEMPLATE/memory"
      : > "$TEMPLATE/marker"
      command touch "$READY"
    fi
    command mkdir "$@"
  }

  run -0 _gitlore_ensure_parent_with_memory_template

  [ "$output" = "$TEMPLATE" ]
  [ ! -s "$BUILDS" ]
  [ -f "$TEMPLATE/marker" ]
  [ ! -d "$LOCK" ]
}

@test "a template build that fails says so instead of returning silently" {
  # shellcheck disable=SC2317  # invoked indirectly, through the function under test
  _gitlore_build_parent_with_memory() { return 1; }

  run --separate-stderr _gitlore_ensure_parent_with_memory_template

  [ "$status" -ne 0 ]
  [[ "$stderr" == *"failed to build the fixture template"* ]]
}

@test "a template copy that fails is reported as a copy failure" {
  cp() { return 1; }

  run --separate-stderr make_parent_with_memory

  [ "$status" -ne 0 ]
  [[ "$stderr" == *"failed to copy the fixture template"* ]]
}

# Uses the real builder (this file's stub only replaces it inside individual
# test bodies above, and bats runs each @test in its own process) so the
# template genuinely carries its own absolute path, exercising the real
# rewrite rather than a stand-in.
@test "the copy rewrites the template's absolute path out of every carrier file" {
  # An earlier test in this file replaces _gitlore_build_parent_with_memory
  # with a stub; bats runs the whole file's tests in one shell, so the
  # redefinition otherwise leaks forward. Reload the real one.
  unset -f _gitlore_build_parent_with_memory
  # shellcheck source=tests/helpers/fixtures.bash
  source "${BATS_TEST_DIRNAME}/helpers/fixtures.bash"

  run -0 make_parent_with_memory
  local old_root
  old_root="$(_gitlore_fixture_cache_dir)/parent-with-memory"

  local f
  for f in .gitmodules .git/config .git/modules/gitlore-memory/config memory/.git; do
    [ -f "$TMP_REPO/$f" ] || continue
    run grep -F -- "$old_root" "$TMP_REPO/$f"
    [ "$status" -ne 0 ]
  done

  run -0 git -C "$TMP_REPO/memory" rev-parse HEAD
  run -0 git -C "$TMP_REPO" submodule status
}

@test "the copy handles a TMP_REPO path with a space and an ampersand" {
  # See the reload note in the previous test — a prior test's stub otherwise leaks forward.
  unset -f _gitlore_build_parent_with_memory
  # shellcheck source=tests/helpers/fixtures.bash
  source "${BATS_TEST_DIRNAME}/helpers/fixtures.bash"

  local orig="$TMP_REPO"
  TMP_REPO="$orig/dir with space & amp"
  export TMP_REPO
  mkdir -p "$TMP_REPO"
  cd "$TMP_REPO"
  git init -q -b main
  git config user.email "test@example.com"
  git config user.name  "Test"

  run -0 make_parent_with_memory
  run -0 git -C "$TMP_REPO/memory" rev-parse HEAD
  run -0 git -C "$TMP_REPO" submodule status

  # The rewrite must land $TMP_REPO's literal path — space, ampersand and all —
  # in the carrier files, not a sed replacement-text expansion of it (an
  # unescaped `&` in the new path would splice in the whole match instead).
  run -0 git config --file "$TMP_REPO/.git/config" submodule.gitlore-memory.url
  [ "$output" = "$TMP_REPO/.bare-memory.git" ]

  # Hand the original path back so teardown_tmp_repo cleans up the nested one too.
  TMP_REPO="$orig"
  export TMP_REPO
}

@test "a copy of a template that lacks memory/ fails loudly" {
  # shellcheck disable=SC2317  # invoked indirectly, through the function under test
  _gitlore_build_parent_with_memory() {
    rm -rf "$1"
    mkdir -p "$1"
  }

  run --separate-stderr make_parent_with_memory

  [ "$status" -ne 0 ]
  [[ "$stderr" == *"memory"* ]]
}

# The race this fixture guards against leaves the submodule directory PRESENT
# but empty (no gitlink), not absent — `git -C memory rev-parse HEAD` walks up
# past an empty `memory/` to the parent's own `.git` and happily resolves the
# parent's HEAD instead, so that check alone does not notice.
@test "a copy whose submodule directory is present but empty is rejected, not silently accepted" {
  # shellcheck disable=SC2317  # invoked indirectly, through the function under test
  _gitlore_build_parent_with_memory() {
    rm -rf "$1"
    mkdir -p "$1"
    (
      cd "$1" || exit 1
      git init -q -b main
      git config user.email "test@example.com"
      git config user.name  "Test"
      mkdir -p "$2"
      git add -A
      git commit -q -m x --allow-empty
    )
  }

  run --separate-stderr make_parent_with_memory

  [ "$status" -ne 0 ]
}
