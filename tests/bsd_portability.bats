#!/usr/bin/env bats
# macOS ships BSD sed and mktemp under bash 3.2, and the suite's own helpers and
# the bats wrapper have to run there too. Each test shadows one tool with a stub
# that enforces the BSD contract (tests/helpers/bsd-stubs.bash), so a GNU-ism
# the Linux run would accept fails here instead of on the next Mac.
#
# The tools under test are the 3.2-era ones; the assertions checking them are
# not. They assume bash >= 4.1, where a failing `[[ ]]` anywhere in a test body
# fails the test. Under 3.2 a failing non-final `[[ ]]` passes silently, while
# a failing `[ ]` or plain command still fails the test (measured with bats
# 1.14.0 on bash 3.2.57 by `plans/macos-check/run.sh`), so a suite asserting
# with `[[ ]]` reports green on a Mac it never checked. A macOS run therefore
# drives bats with a modern bash (Homebrew's) and points what the tests exec at
# the system's through `GITLORE_TEST_BASH_DIR`; on Linux the stubs supply the
# BSD behaviour the system tools would have contributed.
# $status/$output are populated by bats `run`; shellcheck cannot see them.
# shellcheck disable=SC2154
bats_require_minimum_version 1.5.0

load helpers/setup
load helpers/fixtures
load helpers/bsd-stubs

setup()    { setup_tmp_repo; BSD="$TMP_REPO/.bsdtools"; }
teardown() { teardown_tmp_repo; }

@test "fixture path rewrite survives BSD sed (no attached -i extension)" {
  make_bsd_stubs "$BSD" sed
  PATH="$BSD:$PATH" make_parent_with_memory
  # The rewrite is what points the copied submodule at its new home; a
  # template path left behind would resolve the worktree elsewhere.
  [ "$(git -C memory rev-parse --show-toplevel)" = "$(pwd -P)/memory" ]
  run ! grep -rqF "$(_gitlore_fixture_cache_dir)" .gitmodules .git/config .git/modules/gitlore-memory/config memory/.git
}

@test "fixture path rewrite survives a temp dir reached through a symlink" {
  # macOS: `$TMPDIR` is /var/folders/…, and /var is a symlink to /private/var.
  # The template's path is baked in as the builder was handed it, the rewrite
  # searches for its `pwd -P` form, and a copy whose rewrite misses keeps the
  # template's bare remote as its origin — shared with every other test.
  mkdir "$TMP_REPO/.real-run"
  ln -s "$TMP_REPO/.real-run" "$TMP_REPO/.linked-run"
  BATS_RUN_TMPDIR="$TMP_REPO/.linked-run" make_parent_with_memory
  [ "$(git -C memory config --get remote.origin.url)" = "$(pwd -P)/.bare-memory.git" ]
  run ! grep -rqF -e "$TMP_REPO/.linked-run" -e "$TMP_REPO/.real-run" .gitmodules .git/config .git/modules/gitlore-memory/config memory/.git
}

@test "lint-shell.sh shebang discovery survives BSD grep (no \\b word boundary)" {
  make_bsd_stubs "$BSD" grep
  mkdir -p hooks
  printf '#!/usr/bin/env bash\ncd /tmp\n' > hooks/pre-commit
  git add hooks/pre-commit
  PATH="$BSD:$PATH" run "$PLUGIN_ROOT/scripts/lint-shell.sh"
  [ "$status" -ne 0 ]
  # Discovered AND linted — not skipped and then reported as "no shell files".
  [[ "$output" == *SC2164* ]]
}

@test "run-bats.sh log file survives BSD mktemp on a second run (trailing Xs only)" {
  make_bsd_stubs "$BSD" mktemp
  printf '#!/usr/bin/env bats\n@test "ok" { true; }\n' > one.bats
  PATH="$BSD:$PATH" TMPDIR="$TMP_REPO" run "$PLUGIN_ROOT/scripts/run-bats.sh" one.bats
  [ "$status" -eq 0 ]
  [[ "$output" == *"1 passed, 0 failed"* ]]
  PATH="$BSD:$PATH" TMPDIR="$TMP_REPO" run "$PLUGIN_ROOT/scripts/run-bats.sh" one.bats
  [ "$status" -eq 0 ]
  [[ "$output" == *"1 passed, 0 failed"* ]]
}

@test "GITLORE_TEST_BASH_DIR puts the chosen bash ahead for what a test execs" {
  mkdir "$TMP_REPO/.chosen"
  printf '#!/bin/sh\necho chosen-bash\n' > "$TMP_REPO/.chosen/bash"
  chmod +x "$TMP_REPO/.chosen/bash"
  GITLORE_TEST_BASH_DIR="$TMP_REPO/.chosen" use_test_bash
  run bash -c 'echo system-bash'
  [ "$output" = "chosen-bash" ]
}
