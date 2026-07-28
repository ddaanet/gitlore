#!/usr/bin/env bats
# $status/$output are populated by bats `run`; shellcheck cannot see them.
# shellcheck disable=SC2154
# The planted scripts below carry literal `$foo` on purpose (to trigger SC2086
# in the *target*); the single-quoted printf is intentional, not a bug.
# shellcheck disable=SC2016
#
# No test here runs this script against the real repo — `just lint`, a
# sibling precommit step (`justfile`'s `precommit: check-version lint test`),
# already asserts that. Doing it again here doubled shellcheck's ~64s repo-wide
# cost inside `test-unit` for no added coverage in the gate that matters.

load helpers/setup

setup()    { setup_tmp_repo; }
teardown() { teardown_tmp_repo; }

@test "lint-shell: catches a shellcheck violation in a tracked .sh file" {
  printf '#!/usr/bin/env bash\nfoo=$(echo hi)\necho $foo\n' > bad.sh
  git add bad.sh
  run "$PLUGIN_ROOT/scripts/lint-shell.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *SC2086* ]]
}

@test "lint-shell: discovers extensionless tracked scripts by shebang" {
  mkdir -p hooks
  printf '#!/usr/bin/env bash\ncd /tmp\n' > hooks/pre-commit
  git add hooks/pre-commit
  run "$PLUGIN_ROOT/scripts/lint-shell.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *SC2164* ]]
}

@test "lint-shell: ignores untracked shell files" {
  printf '#!/usr/bin/env bash\necho clean\n' > good.sh
  git add good.sh
  printf '#!/usr/bin/env bash\nfoo=$(echo hi)\necho $foo\n' > untracked.sh
  run "$PLUGIN_ROOT/scripts/lint-shell.sh"
  [ "$status" -eq 0 ]
}
