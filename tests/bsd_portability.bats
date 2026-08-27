#!/usr/bin/env bats
# macOS ships BSD sed and mktemp under bash 3.2, and the suite's own helpers and
# the bats wrapper have to run there too. Each test shadows one tool with a stub
# that enforces the BSD contract (tests/helpers/bsd-stubs.bash), so a GNU-ism
# the Linux run would accept fails here instead of on the next Mac.
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
