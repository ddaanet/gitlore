#!/usr/bin/env bats
# gitlore_batch_hook_guard (scripts/lib/hook-guard.sh): a PostToolBatch hook
# that dies reports on both channels and exits 0. Every test drives a fixture
# hook script (tests/helpers/hook-guard.bash) run as `bash script`, the way CC
# runs a hook: the guard is an ERR/EXIT trap pair plus a stderr redirect, which
# only a real process exit exercises. The cannot-report paths, the clean exit
# and the owned files are in tests/hook_guard_fallback.bats.
#
# The capture file is assumed to sit directly in the memory worktree's git dir,
# named `gitlore-hook-*` (`git -C "$mempath" rev-parse --git-path`). The
# "nothing left behind" tests list the whole git dir before and after, so they
# hold for any name there.
#
# A reported line number is asserted exactly only for a simple command at the
# fixture's top level. `$LINENO` in an ERR trap is exact on bash >= 4, but on
# 3.2 it is the first line of the enclosing function or compound command, so
# inside a function the line must fall between the function's opening and the
# command. Deaths are forced by real failing commands: `( exit N )` does not
# kill a 3.2 script under errexit.
# shellcheck disable=SC2016,SC2034,SC2154  # fixture bodies are literal; $status/$output come from `run`

bats_require_minimum_version 1.5.0   # `run --separate-stderr`

load helpers/setup
load helpers/fixtures
load helpers/hook-guard

setup()    { hook_guard_setup; }
teardown() { hook_guard_teardown; }

# --- a death reports and exits 0 --------------------------------------------

@test "guard: a death with status 1 exits 0 with one report carrying name, status and stderr" {
  cmd=$(death_cmd 1)
  write_fixture '' "$cmd"
  before=$(gitdir_listing)
  run_fixture
  assert_death_report 1 boom-from-child "$cmd"
  [ "$(gitdir_listing)" = "$before" ]
}

@test "guard: a death with status 2 exits 0, not 2, with one report carrying name, status and stderr" {
  cmd=$(death_cmd 2)
  write_fixture '' "$cmd"
  run_fixture
  assert_death_report 2 boom-from-child "$cmd"
}

@test "guard: a death with status 5 exits 0 with one report carrying name, status and stderr" {
  cmd=$(death_cmd 5)
  write_fixture '' "$cmd"
  run_fixture
  assert_death_report 5 boom-from-child "$cmd"
}

@test "guard: a death in a store whose memory path contains a space still reports" {
  # The non-default builder rebuilds the repo, removing the cwd it was called in.
  make_parent_with_memory "mem ory"
  cd "$TMP_REPO"
  GITDIR=$(git -C "mem ory" rev-parse --absolute-git-dir)
  cmd=$(death_cmd 5)
  write_fixture '' "$cmd"
  before=$(gitdir_listing)
  run_fixture
  assert_death_report 5 boom-from-child "$cmd"
  [ "$(gitdir_listing)" = "$before" ]
}

@test "guard: the consequence sentence is in additionalContext and not in systemMessage" {
  write_fixture '' "$(death_cmd 5)"
  run_fixture
  [ "$status" -eq 0 ]
  assert_one_object
  [[ "$(ctx_msg)" == *"CONSEQUENCE-MARK the fixture did not finish."* ]]
  [[ "$(sys_msg)" != *CONSEQUENCE-MARK* ]]
}

# --- a death that writes no stderr still names its command ------------------

@test "guard: cmp -s on a missing file at top level reports the command and its exact line" {
  cmd='cmp -s "$mempath/nope-a" "$mempath/nope-b"'
  write_fixture '' "$cmd"
  want_line=$(fixture_line "$cmd")
  [ -n "$want_line" ]
  run_fixture
  [ "$status" -eq 0 ]
  assert_one_object
  for channel in sys_msg ctx_msg; do
    msg=$("$channel")
    [[ "$msg" == *"$cmd"* ]]
    msg_has_status "$msg" 2
    msg_has_line "$msg" "$want_line"
  done
}

@test "guard: a bare [ test ] at top level reports the command and its exact line" {
  cmd='[ -f "$mempath/does-not-exist" ]'
  write_fixture '' "$cmd"
  want_line=$(fixture_line "$cmd")
  [ -n "$want_line" ]
  run_fixture
  [ "$status" -eq 0 ]
  assert_one_object
  for channel in sys_msg ctx_msg; do
    msg=$("$channel")
    [[ "$msg" == *"$cmd"* ]]
    msg_has_status "$msg" 1
    msg_has_line "$msg" "$want_line"
  done
}

@test "guard: cmp -s on a missing file inside a function reports the command and a line within it" {
  cmd='cmp -s "$mempath/nope-a" "$mempath/nope-b"'
  write_fixture '' "check_it() {
  local note=1
  $cmd
}
check_it"
  first=$(fixture_line 'check_it() {')
  last=$(fixture_line "$cmd")
  run_fixture
  [ "$status" -eq 0 ]
  assert_one_object
  for channel in sys_msg ctx_msg; do
    msg=$("$channel")
    [[ "$msg" == *"$cmd"* ]]
    msg_has_status "$msg" 2
    msg_line_in_range "$msg" "$first" "$last"
  done
}

@test "guard: a bare [ test ] inside a function reports the command and a line within it" {
  cmd='[ -f "$mempath/does-not-exist" ]'
  write_fixture '' "check_it() {
  local note=1
  $cmd
}
check_it"
  first=$(fixture_line 'check_it() {')
  last=$(fixture_line "$cmd")
  run_fixture
  [ "$status" -eq 0 ]
  assert_one_object
  for channel in sys_msg ctx_msg; do
    msg=$("$channel")
    [[ "$msg" == *"$cmd"* ]]
    msg_has_status "$msg" 1
    msg_line_in_range "$msg" "$first" "$last"
  done
}

# --- before the call nothing is created -------------------------------------

# These two pass against any guard that installs nothing until it is called.
# They go red only if sourcing the library, or the guard file, starts capturing.
@test "guard: an exit before the guard call creates no file" {
  write_fixture 'exit 0' 'echo unreached'
  before=$(gitdir_listing)
  run_fixture
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ "$(gitdir_listing)" = "$before" ]
}

@test "guard: a death before the guard call is a plain exit with no report and no file" {
  write_fixture "sh -c 'echo early-boom >&2; exit 5'" 'echo unreached'
  before=$(gitdir_listing)
  run_fixture
  [ "$status" -eq 5 ]
  [ -z "$output" ]
  [[ "$stderr" == *early-boom* ]]
  [ "$(gitdir_listing)" = "$before" ]
}
