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
