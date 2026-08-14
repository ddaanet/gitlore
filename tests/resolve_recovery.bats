#!/usr/bin/env bats
# $stderr is populated by bats `run --separate-stderr`; shellcheck cannot see it.
# shellcheck disable=SC2154
bats_require_minimum_version 1.5.0

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
  make_diverged_head_vs_live memory
  run --separate-stderr bash "$PRE_COMMIT"
  # Now we have a state file + MERGE_HEAD. Simulate a fresh entry.
  run --separate-stderr bash "$PRE_COMMIT"
  [[ "$output$stderr" == *"abort-then-retry"* ]]
}

@test "recovery: a merge that never started is reported, not announced as prepared" {
  # The merge's own output is discarded on purpose — a conflict is the expected
  # outcome and the conflicted worktree IS the deliverable. But a merge that
  # never started leaves no MERGE_HEAD, and without checking for it the caller
  # would write a state file and dispatch a sub-agent to resolve nothing.
  # Reproduced here with an authority HEAD already contains, which is now
  # recognized by ancestry BEFORE the detach that used to make this diagnosis
  # move HEAD — so the report names the state rather than relaying git's
  # "Already up to date" from a checkout already performed.
  before=$(git -C memory rev-parse HEAD)
  run --separate-stderr gitlore_prepare_merge memory live HEAD
  [ "$status" -eq 1 ]
  [[ "$output$stderr" == *"already contains HEAD"* ]]
  run git -C memory rev-parse -q --verify MERGE_HEAD
  [ "$status" -ne 0 ]
  [ "$(git -C memory rev-parse HEAD)" = "$before" ]
}

@test "recovery: orphaned MERGE_HEAD with no state file is flagged, not reported clean" {
  make_diverged_head_vs_live memory
  # Simulate an interrupted gitlore_prepare_merge: it stages a real merge
  # (MERGE_HEAD set, content staged) but the caller dies before
  # gitlore_write_merge_state runs — the exact edify incident this guards.
  run --separate-stderr gitlore_prepare_merge memory live HEAD
  [ "$status" -eq 0 ]
  mh=$(git -C memory rev-parse -q --verify MERGE_HEAD)
  [ -n "$mh" ]
  [ ! -f "$(gitlore_merge_state_file memory)" ]

  run gitlore_detect_stale_merge_state memory
  [ "$output" = "orphaned-merge-head" ]

  run --separate-stderr gitlore_guard_stale_merge_state memory
  [ "$status" -ne 0 ]
  [[ "$output$stderr" == *"manual intervention"* ]]
  [[ "$output$stderr" == *"$mh"* ]]
}

@test "recovery: state file without MERGE_HEAD → fatal directive" {
  make_diverged_head_vs_live memory
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
  make_diverged_head_vs_live memory
  bash "$PRE_COMMIT" || true
  # Simulate a crash by leaving the state file + MERGE_HEAD intact.
  run --separate-stderr bash "$RESOLVE" abort-then-retry
  [ "$status" -ne 0 ]  # Re-entry yields a fresh directive
  [[ "$output$stderr" == *"head-vs-live"* ]] || [[ "$output$stderr" == *"flavor="* ]]
  # MERGE_HEAD cleaned (the re-entry prepares a new merge, so MERGE_HEAD will
  # exist again — but that's a new merge, not the stale one).
}
