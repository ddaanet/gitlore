#!/usr/bin/env bats

load helpers/setup
load helpers/gh-mock

setup() {
  setup_tmp_repo
  install_gh_mock
}
teardown() { teardown_tmp_repo; }

@test "gh mock: returns success by default" {
  run gh --version
  [ "$status" -eq 0 ]
  [[ "$output" == *"gh version mock"* ]]
}

@test "gh mock: GH_MOCK_EXIT scripts exit code" {
  GH_MOCK_EXIT=2 run gh auth status
  [ "$status" -eq 2 ]
}

@test "gh mock: GH_MOCK_STDOUT_API_USER scripts per-subcommand stdout" {
  GH_MOCK_STDOUT_API_USER="alice" run gh api user -q .login
  [ "$status" -eq 0 ]
  [ "$output" = "alice" ]
}

@test "gh mock: records calls to GH_MOCK_LOG" {
  log="$TMP_REPO/calls.log"
  GH_MOCK_LOG="$log" gh repo create foo --private
  grep -q 'repo create foo --private' "$log"
}
