#!/usr/bin/env bats
# $stderr is populated by bats `run --separate-stderr`; shellcheck cannot see it.
# shellcheck disable=SC2154
bats_require_minimum_version 1.5.0

load helpers/setup
load helpers/fixtures
load helpers/tier-fixtures
load helpers/stub-synth
load helpers/merge-memory
load helpers/take-order

# The reconcile of memory's HEAD against its local `live` prepares a root merge
# through the same function as the take's, so it follows the take's order: each
# tier moves before any root merge is prepared. A root merge prepared without
# visiting a tier (/gitlore:resolve) meets the same check.

RESOLVE="$PLUGIN_ROOT/scripts/resolve.sh"

@test "a take over a root HEAD/live fork takes the tier first, and root records the tier's HEAD" {
  take_base_store ddaanet
  tier_sha=$(upstream_moves_pin ddaanet up.md)
  fork_root_from_live

  drive_take_to_rest memory/ddaanet
  [ "$TAKE_STATUS" -eq 0 ] || { cat "$BATS_TEST_TMPDIR"/take.*.err >&2; return 1; }
  # The reconcile prepared root's merge with the tier already taken.
  assert_root_yields_at_tier_head "$tier_sha"
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$tier_sha" ]
  [ "$(git -C memory rev-parse HEAD:ddaanet)" = "$tier_sha" ]
  [ ! -f "$(store_state_file memory)" ]
}

@test "a push over a root HEAD/live fork takes the tier before it prepares root's merge" {
  take_base_store ddaanet
  tier_sha=$(upstream_moves_pin ddaanet up.md)
  fork_root_from_live
  # shellcheck disable=SC2034  # drive_take_to_rest runs $CMD
  CMD="$PLUGIN_ROOT/scripts/push-memory.sh"

  drive_take_to_rest memory/ddaanet
  [ "$TAKE_STATUS" -eq 0 ] || { cat "$BATS_TEST_TMPDIR"/take.*.err >&2; return 1; }
  # The prepare was reached with the tier already where the take put it, not
  # stopped on the ancestry check.
  assert_root_yields_at_tier_head "$tier_sha"
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$tier_sha" ]
  [ "$(git -C memory rev-parse HEAD:ddaanet)" = "$tier_sha" ]
}

@test "resolve, root fork whose live records a commit the tier lacks but its remote holds: stops naming the tier and /gitlore:merge" {
  take_base_store ddaanet
  upstream_moves_pin ddaanet up.md >/dev/null
  fork_root_from_live
  head_before=$(git -C memory rev-parse HEAD)

  run --separate-stderr bash "$RESOLVE"
  [ "$status" -eq 1 ]
  err="$stderr"
  # The merger was not briefed: no directive, no state file, no merge pending.
  [[ "$output$err" != *"dispatch sub-agent"* ]]
  [ ! -f "$(store_state_file memory)" ]
  run ! git -C memory rev-parse -q --verify MERGE_HEAD
  [ "$(git -C memory rev-parse HEAD)" = "$head_before" ]
  [[ "$err" == *"tier 'ddaanet'"* ]]
  [[ "$err" == *"/gitlore:merge"* ]]
  # The commit exists on the tier's remote, so the push remedy for a lost
  # commit is the wrong report.
  [[ "$err" != *"/gitlore:push"* ]]
}

@test "resolve, root fork whose live records a commit on no remote: stops naming the commit, the tier, the remote and /gitlore:push" {
  take_base_store ddaanet
  lost=$(unpublished_tier_commit ddaanet)
  memory_remote_records ddaanet "$lost" "- [lost](ddaanet/lost.md) — recorded where the tier lacks it" >/dev/null
  fork_root_from_live
  head_before=$(git -C memory rev-parse HEAD)

  # The user's run: the remote's url is on the user channel only.
  CLAUDECODE='' run --separate-stderr bash "$RESOLVE"
  [ "$status" -eq 1 ]
  err="$stderr"
  [[ "$output$err" != *"dispatch sub-agent"* ]]
  [ ! -f "$(store_state_file memory)" ]
  run ! git -C memory rev-parse -q --verify MERGE_HEAD
  [ "$(git -C memory rev-parse HEAD)" = "$head_before" ]
  [[ "$err" == *"${lost:0:7}"* ]]
  [[ "$err" == *"tier 'ddaanet'"* ]]
  [[ "$err" == *"$TMP_REPO/.bare-ddaanet.git"* ]]
  [[ "$err" == *"/gitlore:push"* ]]
}
