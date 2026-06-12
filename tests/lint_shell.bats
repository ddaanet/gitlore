#!/usr/bin/env bats
# $status/$output are populated by bats `run`; shellcheck cannot see them.
# shellcheck disable=SC2154
# The planted scripts below carry literal `$foo` on purpose (to trigger SC2086
# in the *target*); the single-quoted printf is intentional, not a bug.
# shellcheck disable=SC2016

load helpers/setup

setup()    { setup_tmp_repo; }
teardown() { teardown_tmp_repo; }

@test "lint-shell: the repository's own shell files are clean" {
  # setup() leaves us in an empty tmp repo; the script keys off cwd's toplevel,
  # so run it from within the real repo to lint the actual tracked scripts.
  cd "$PLUGIN_ROOT" || return 1
  run "$PLUGIN_ROOT/scripts/lint-shell.sh"
  [ "$status" -eq 0 ]
}

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
