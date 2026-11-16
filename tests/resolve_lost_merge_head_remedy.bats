#!/usr/bin/env bats
# $stderr is populated by bats `run --separate-stderr`; shellcheck cannot see it.
# shellcheck disable=SC2154
bats_require_minimum_version 1.5.0

# continue-after-merge on a merge state file whose MERGE_HEAD is gone names the
# command that repairs the state without a surprise: /gitlore:merge when the
# merge was prepared by it (publish: no), /gitlore:resolve otherwise.

load helpers/setup
load helpers/commit-summary
load helpers/fixtures
load helpers/divergence-fixtures
load helpers/stub-synth
load helpers/tier-fixtures
load helpers/resolve-recovery

RESOLVE="$PLUGIN_ROOT/scripts/resolve.sh"

@test "lost MERGE_HEAD: a merge prepared by merge-memory.sh names /gitlore:merge" {
  make_diverged_head_vs_remote memory
  run --separate-stderr merge_gate
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"continue-after-merge"* ]]
  git -C memory merge --abort

  run --separate-stderr bash "$RESOLVE" continue-after-merge
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"holds a merge state file but no MERGE_HEAD"* ]]
  [[ "$stderr" == *"Run /gitlore:merge"* ]]
  [[ "$stderr" != *"/gitlore:resolve"* ]]
}

@test "lost MERGE_HEAD: a merge prepared by a bare resolve.sh names /gitlore:resolve" {
  git -C memory push -q origin live
  make_diverged_head_vs_live memory
  run --separate-stderr resolve_gate
  [ "$status" -ne 0 ]
  [[ "$stderr" == *"continue-after-merge"* ]]
  git -C memory merge --abort

  run --separate-stderr bash "$RESOLVE" continue-after-merge
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"holds a merge state file but no MERGE_HEAD"* ]]
  [[ "$stderr" == *"Run /gitlore:resolve"* ]]
  [[ "$stderr" != *"/gitlore:merge"* ]]
}
