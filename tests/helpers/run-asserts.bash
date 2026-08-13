#!/usr/bin/env bash
# Assertions on the last `run`, reporting the evidence when they fail.
#
# A bare `[ "$status" -eq 0 ]` reports a line number and nothing else. The
# scripts under test exit with a *different* message for each way they can
# reject — the eval assertions carry five to eight apiece — so a bare status
# check throws away the one thing that says which check fired, exactly when
# that is the thing being asked for. Same for `run grep -q`: `-q` empties
# `$output` by construction, so a failure says only "no match", never what the
# file did contain.
#
# Each helper prints its evidence to stderr and returns 1. bats shows a failed
# test's stderr under the `not ok` line, which is what `scripts/run-bats.sh`
# surfaces.

# `status` and `output` are set by bats' own `run`, in the caller's scope.
# shellcheck disable=SC2154

# Assert the last `run` exited 0.
assert_ok() {
  if [ "$status" -eq 0 ]; then return 0; fi
  _report_run "expected exit 0, got $status" "$output"
}

# Assert the last `run` exited with exactly $1, and that its output contains
# each further argument as a literal substring.
assert_status() {
  _assert_exit "$@"
}

# Assert the last `run` exited non-zero, and that its output contains each
# argument as a literal substring. The substring is not decoration: a non-zero
# exit alone is satisfied by every rejection the script can make, including the
# ones the test is not about.
assert_fails() {
  if [ "$status" -eq 0 ]; then
    _report_run "expected a non-zero exit, got 0" "$output"
    return 1
  fi
  _assert_output "$@"
}

# Assert `grep "$@"` matches. The last argument is the file, and its contents
# are what gets reported on failure.
assert_grep() {
  if grep "$@" >/dev/null; then return 0; fi
  _report_run "no match for: $*" "$(cat "${*: -1}")"
}

# Assert `grep "$@"` does not match — the file is reported when it does.
refute_grep() {
  if ! grep "$@" >/dev/null; then return 0; fi
  _report_run "unwanted match for: $*" "$(cat "${*: -1}")"
}

_assert_exit() {
  local want="$1"; shift
  if [ "$status" -ne "$want" ]; then
    _report_run "expected exit $want, got $status" "$output"
    return 1
  fi
  _assert_output "$@"
}

_assert_output() {
  local want
  for want in "$@"; do
    case "$output" in
      *"$want"*) ;;
      *) _report_run "exit $status, but the output is missing: $want" "$output"; return 1 ;;
    esac
  done
}

_report_run() {
  printf '%s\n--- evidence ---\n%s\n--- end ---\n' "$1" "$2" >&2
  return 1
}
