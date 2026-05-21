#!/usr/bin/env bats

load helpers/setup
load helpers/fixtures
load helpers/divergence-fixtures
load helpers/stub-synth

RESOLVE="$PLUGIN_ROOT/scripts/resolve.sh"
PRE_COMMIT="$PLUGIN_ROOT/scripts/git-hooks/pre-commit"

setup() {
  setup_tmp_repo
  export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
  make_parent_with_memory
  git config gitlore.hooksDir "$PLUGIN_ROOT/scripts/git-hooks"
}
teardown() { teardown_tmp_repo; }

@test "recovery: stale state file + MERGE_HEAD → abort-then-retry directive" {
  make_diverged_branch_vs_live memory
  run --separate-stderr bash "$PRE_COMMIT"
  # Now we have a state file + MERGE_HEAD. Simulate a fresh entry.
  run --separate-stderr bash "$PRE_COMMIT"
  [[ "$output$stderr" == *"abort-then-retry"* ]]
}

@test "recovery: state file without MERGE_HEAD → fatal directive" {
  make_diverged_branch_vs_live memory
  bash "$PRE_COMMIT" || true
  # Manually abort the merge but leave the state file behind.
  (cd memory && git merge --abort 2>/dev/null || true)
  run --separate-stderr bash "$PRE_COMMIT"
  [ "$status" -ne 0 ]
  [[ "$output$stderr" == *"manual intervention"* ]]
}

@test "recovery: abort-then-retry continuation cleans state and re-enters loop" {
  # Push live to origin so resolve.sh default mode hits the semantic-merge
  # detection logic rather than the "no live in remote, push it, exit 0" path.
  git -C memory push -q origin live
  make_diverged_branch_vs_live memory
  bash "$PRE_COMMIT" || true
  # Simulate a crash by leaving the state file + MERGE_HEAD intact.
  run --separate-stderr bash "$RESOLVE" abort-then-retry
  [ "$status" -ne 0 ]  # Re-entry yields a fresh directive
  [[ "$output$stderr" == *"branch-vs-live"* ]] || [[ "$output$stderr" == *"flavor="* ]]
  # MERGE_HEAD cleaned (the re-entry prepares a new merge, so MERGE_HEAD will
  # exist again — but that's a new merge, not the stale one).
}
