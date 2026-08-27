#!/usr/bin/env bats
# $stderr is populated by bats `run --separate-stderr`; shellcheck cannot see it.
# shellcheck disable=SC2154
bats_require_minimum_version 1.5.0

load helpers/setup
load helpers/fixtures
load helpers/divergence-fixtures
load helpers/stub-synth

RESOLVE="$PLUGIN_ROOT/scripts/resolve.sh"

setup() {
  setup_tmp_repo
  export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
  make_parent_with_memory
  # Push live to origin so the early-exit guards in resolve.sh don't fire
  # before reaching the semantic-merge detection logic.
  git -C memory push -q origin live
}
teardown() { teardown_tmp_repo; }

@test "resolve: healthy state still no-ops" {
  run --separate-stderr bash "$RESOLVE"
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"healthy"* ]]
}

@test "resolve: yields head-vs-live directive when the pending commit diverged from live" {
  make_diverged_head_vs_live memory
  run --separate-stderr bash "$RESOLVE"
  [ "$status" -ne 0 ]
  [[ "$output$stderr" == *"flavor=head-vs-live"* ]]
}

@test "resolve: yields head-vs-remote directive when local diverged from origin" {
  make_diverged_head_vs_remote memory
  # The commit path keeps local `live` at HEAD, so the local check is a no-op
  # and only the remote one fires.
  run --separate-stderr bash "$RESOLVE"
  [ "$status" -ne 0 ]
  [[ "$output$stderr" == *"flavor=head-vs-remote"* ]]
}

@test "resolve: both flavors → serial yield (head-vs-live first)" {
  # Remote divergence first (leaves HEAD == local live), then move `live`
  # sideways off the shared parent so it genuinely diverges from HEAD — merely
  # advancing it would be a fast-forward, not a conflict.
  make_diverged_head_vs_remote memory
  advance_branch_with_file memory live SIBLING.md sibling "Sibling live advance" 'live^'
  run --separate-stderr bash "$RESOLVE"
  [ "$status" -ne 0 ]
  [[ "$output$stderr" == *"flavor=head-vs-live"* ]]
  # After stub-synth + first continuation, /gitlore:resolve should be re-invoked
  # to detect the second flavor. The continuation does NOT auto-loop into the
  # second flavor — that's a fresh entry-point invocation.
  run_stub_synth memory
  run --separate-stderr bash "$RESOLVE"
  [ "$status" -ne 0 ]
  [[ "$output$stderr" == *"flavor=head-vs-remote"* ]]
}
