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
# 1.14.0 on bash 3.2.57 by `plans/2026-09-21-macos-check/run.sh`), so a suite asserting
# with `[[ ]]` reports green on a Mac it never checked. `helpers/setup.bash`
# refuses such a bash when a suite loads it. A macOS run therefore
# drives bats with a modern bash (Homebrew's) and points what the tests exec at
# the system's through `GITLORE_TEST_BASH_DIR`; on Linux the stubs supply the
# BSD behaviour the system tools would have contributed.
# $status/$output are populated by bats `run`; shellcheck cannot see them.
# shellcheck disable=SC2154
bats_require_minimum_version 1.5.0

load helpers/setup
load helpers/fixtures
load helpers/bsd-stubs
load helpers/run-asserts

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
  PATH="$BSD:$PATH" run "$PLUGIN_ROOT/tools/lint-shell.sh"
  [ "$status" -ne 0 ]
  # Discovered AND linted — not skipped and then reported as "no shell files".
  [[ "$output" == *SC2164* ]]
}

@test "run-bats.sh log file survives BSD mktemp on a second run (trailing Xs only)" {
  make_bsd_stubs "$BSD" mktemp
  printf '#!/usr/bin/env bats\n@test "ok" { true; }\n' > one.bats
  PATH="$BSD:$PATH" TMPDIR="$TMP_REPO" run "$PLUGIN_ROOT/plugin-dev/run-bats.sh" one.bats
  [ "$status" -eq 0 ]
  [[ "$output" == *"1 passed, 0 failed"* ]]
  PATH="$BSD:$PATH" TMPDIR="$TMP_REPO" run "$PLUGIN_ROOT/plugin-dev/run-bats.sh" one.bats
  [ "$status" -eq 0 ]
  [[ "$output" == *"1 passed, 0 failed"* ]]
}

@test "a file reaching for GNU stat also carries the BSD spelling" {
  # `stat -c` is GNU-only — BSD spells the same fields `-f '%Lp'` / `-f '%m'` —
  # and no stub reaches the calls that live in test bodies rather than in a
  # script a test execs, so a Linux run cannot fail on the GNU-ism. Checked per
  # file rather than per line: the portable wrappers (`file_mode`,
  # `gitlore_file_mtime`) probe with a bare `stat -c` on a line of their own.
  cd "$PLUGIN_ROOT"
  gnu=$(grep -rl -e 'stat -c' -e 'stat --format' \
        --include='*.sh' --include='*.bats' --include='*.bash' scripts tests)
  while IFS= read -r f || [ -n "$f" ]; do
    [ -n "$f" ] || continue
    grep -q 'stat -f' "$f" || {
      echo "GNU-only stat with no BSD spelling in $f" >&2
      return 1
    }
  done <<< "$gnu"
}

@test "GITLORE_TEST_BASH_DIR puts the chosen bash ahead for what a test execs" {
  mkdir "$TMP_REPO/.chosen"
  printf '#!/bin/sh\necho chosen-bash\n' > "$TMP_REPO/.chosen/bash"
  chmod +x "$TMP_REPO/.chosen/bash"
  GITLORE_TEST_BASH_DIR="$TMP_REPO/.chosen" use_test_bash
  run bash -c 'echo system-bash'
  [ "$output" = "chosen-bash" ]
}

@test "a bash whose failing non-final [[ ]] passes silently is refused at load" {
  # The suite asserts with `[[ … == *glob* ]]` throughout, which `[ ]` cannot
  # express, so the version is what gets checked rather than each assertion.
  run require_assertion_bash 3 2
  assert_fails "bash 3.2" "[[ ]]" "tools/test-macos.sh"
  run require_assertion_bash 4 0
  assert_fails "bash 4.0"
  run require_assertion_bash 4 1
  assert_ok
  run require_assertion_bash 5 2
  assert_ok
  # The guard runs when a suite loads the helper, on the bash running the test.
  # shellcheck disable=SC2016 # the literal source line is what is matched
  assert_grep -qxF 'require_assertion_bash "${BASH_VERSINFO[0]}" "${BASH_VERSINFO[1]}"' \
    "$PLUGIN_ROOT/tests/helpers/setup.bash"
}

@test "a bats that leaves \$stderr set across a merged run is refused at load" {
  # Below 1.13 a merged `run` leaves `$stderr` holding an earlier
  # `--separate-stderr` capture, so a suite asserting on it there passes
  # against stale text and fails wherever bats is current.
  run require_bats_version 1.11.1
  assert_fails "1.11.1" ">= 1.13"
  run require_bats_version 1.12.0
  assert_fails "1.12.0"
  run require_bats_version 1.13.0
  assert_ok
  run require_bats_version 2.0.0
  assert_ok
  # An unreadable version is refused, not waved through as "probably fine".
  run require_bats_version ""
  assert_fails ">= 1.13"
  # shellcheck disable=SC2016 # the literal source line is what is matched
  assert_grep -qxF 'require_bats_version "${BATS_VERSION:-}"' \
    "$PLUGIN_ROOT/tests/helpers/setup.bash"
}

@test "a load-time refusal fails the run, rather than printing and reporting green" {
  # What makes the two guards above worth their wording: a refusal that only
  # prints is a refusal the run walks past, which is what bats 1.11 did with a
  # returned one. The assertion is the run's status, not the message. It cannot
  # discriminate `exit` from `return` here — from 1.13 bats acts on both — so
  # the reason each guard exits is stated where it exits, not pinned here.
  # The real helper, refusing through a real bats load: a planted suite loads
  # it and calls the guard with a version below the floor at file scope, which
  # is where bats gathers tests. `helpers` is linked beside the suite because
  # `setup.bash` finds its siblings relative to the suite that loads it.
  mkdir -p "$TMP_REPO/t"
  ln -s "$PLUGIN_ROOT/tests/helpers" "$TMP_REPO/t/helpers"
  # `@``test` split: bats rewrites every line of this file that opens with its
  # own keyword, so the planted suite is assembled rather than quoted.
  printf '%s\n' 'load helpers/setup' 'require_bats_version 1.11.1' \
    "@""test \"never runs\" { true; }" > "$TMP_REPO/t/planted.bats"
  # `$BASH` ahead of PATH: under tools/test-macos.sh a bare `bash` is the
  # system's 3.2, and this nested bats should meet the one driving this test.
  run env PATH="$(dirname "$BASH"):$PATH" bats "$TMP_REPO/t/planted.bats"
  assert_fails "1.11.1" ">= 1.13"
}

# --- shell behaviour gitlore_batch_hook_guard depends on ---------------------
# scripts/lib/hook-guard.sh is an ERR/EXIT trap pair around a stderr redirect.
# These pin the three behaviours it leans on in the bash a Mac execs (3.2) and
# in a modern one, each in a tiny script run by bare `bash` so that
# GITLORE_TEST_BASH_DIR chooses which. They hold today; a failure here means
# the guard's design no longer stands on this shell.

@test "an exit inside an EXIT trap replaces the dying status" {
  cat > "$TMP_REPO/remap.sh" <<'SCRIPT'
set -e
trap 'rc=$?; case $rc in 2) exit 1 ;; 5) exit 5 ;; *) exit 0 ;; esac' EXIT
sh -c "exit $1"
SCRIPT
  run bash "$TMP_REPO/remap.sh" 7   # replaced by 0: the trap swallows the death
  [ "$status" -eq 0 ]
  run bash "$TMP_REPO/remap.sh" 2   # remapped
  [ "$status" -eq 1 ]
  run bash "$TMP_REPO/remap.sh" 5   # passed through
  [ "$status" -eq 5 ]
}

@test "stderr sent to a file with exec 3>&2 2>file is restored inside the EXIT trap" {
  cat > "$TMP_REPO/redirect.sh" <<'SCRIPT'
set -e
exec 3>&2 2>"$1"
trap 'exec 2>&3 3>&-; echo trap-stderr >&2' EXIT
sh -c 'echo child-err >&2; exit 5'
SCRIPT
  run --separate-stderr bash "$TMP_REPO/redirect.sh" "$TMP_REPO/captured"
  [ "$status" -eq 5 ]
  [ "$(cat "$TMP_REPO/captured")" = "child-err" ]   # the dying command's stderr, and only it
  [ "$stderr" = "trap-stderr" ]                     # written after the restore: the real stderr
}

@test "an ERR trap under set -E hands BASH_COMMAND and LINENO to the EXIT trap" {
  # BASH_COMMAND is the failing command's text on every bash, at top level and
  # inside a function. LINENO is the failing command's own line for a simple
  # command at top level everywhere. Inside a function it is the command's line
  # on bash >= 4, and a line inside the function on 3.x (a GNU 3.2.57 build
  # reports the line of the opening `check_it() {`; the guard needs only a line
  # within the function), so there the expectation is that closed range.
  cat > "$TMP_REPO/top.sh" <<'SCRIPT'
set -eE
trap 'cmd=$BASH_COMMAND; ln=$LINENO' ERR
trap 'printf "%s|%s\n" "$cmd" "$ln"' EXIT
cmp -s /nonexistent-a /nonexistent-b
SCRIPT
  run bash "$TMP_REPO/top.sh"
  [ "$status" -eq 2 ]
  [ "$output" = "cmp -s /nonexistent-a /nonexistent-b|4" ]

  cat > "$TMP_REPO/func.sh" <<'SCRIPT'
set -eE
trap 'cmd=$BASH_COMMAND; ln=$LINENO' ERR
trap 'printf "%s|%s\n" "$cmd" "$ln"' EXIT
check_it() {
  local note=1
  [ -f /nonexistent-a ]
}
check_it
SCRIPT
  major=$(bash -c 'echo "${BASH_VERSINFO[0]}"')
  run bash "$TMP_REPO/func.sh"
  [ "$status" -eq 1 ]
  [ "${output%|*}" = "[ -f /nonexistent-a ]" ]
  reported=${output##*|}
  if [ "$major" -ge 4 ]; then
    [ "$reported" = 6 ]
  else
    [ "$reported" -ge 4 ] && [ "$reported" -le 6 ]
  fi
}
