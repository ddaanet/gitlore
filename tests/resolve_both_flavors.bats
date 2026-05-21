#!/usr/bin/env bats

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
  [[ "$output$stderr" == *"healthy"* ]] || [[ -z "$stderr" ]]
}

@test "resolve: yields branch-vs-live directive when worktree diverged from live" {
  make_diverged_branch_vs_live memory
  run --separate-stderr bash "$RESOLVE"
  [ "$status" -ne 0 ]
  [[ "$output$stderr" == *"flavor=branch-vs-live"* ]]
}

@test "resolve: yields local-vs-remote directive when local diverged from origin" {
  make_diverged_local_vs_remote memory
  # make_diverged_local_vs_remote leaves HEAD on live, so branch-vs-live is
  # skipped (condition: HEAD != live is false). Only local-vs-remote fires.
  run --separate-stderr bash "$RESOLVE"
  [ "$status" -ne 0 ]
  [[ "$output$stderr" == *"flavor=local-vs-remote"* ]]
}

@test "resolve: both flavors → serial yield (branch-vs-live first)" {
  make_diverged_branch_vs_live memory
  make_diverged_local_vs_remote memory
  # make_diverged_local_vs_remote leaves HEAD on live; switch to worktree so
  # branch-vs-live detection fires first (condition: HEAD != live).
  git -C memory checkout -q worktree
  run --separate-stderr bash "$RESOLVE"
  [ "$status" -ne 0 ]
  [[ "$output$stderr" == *"flavor=branch-vs-live"* ]]
  # After stub-synth + first continuation, /gitlore:resolve should be re-invoked
  # to detect the second flavor. The continuation does NOT auto-loop into the
  # second flavor — that's a fresh entry-point invocation.
  run_stub_synth memory
  run --separate-stderr bash "$RESOLVE"
  [ "$status" -ne 0 ]
  [[ "$output$stderr" == *"flavor=local-vs-remote"* ]]
}
