#!/usr/bin/env bats
# scripts/cross-rewrite.sh (D62), the parent side: a tier's gitlink staged in
# the memory store, the memory store's own crossing with its gitlinks (mapped,
# chained, unmapped, stray), children first, and the tier-then-memory sequence.
# The tier crossing itself is cross_rewrite.bats. Fixtures:
# helpers/rewrite-fixtures.bash and helpers/cross-fixtures.bash.
#
# $stderr is populated by bats `run --separate-stderr`; shellcheck cannot see it.
# shellcheck disable=SC2154,SC2153,SC2030,SC2031
bats_require_minimum_version 1.5.0

load helpers/setup
load helpers/fixtures
load helpers/tier-fixtures
load helpers/rewrite-fixtures
load helpers/cross-fixtures

CROSS="$PLUGIN_ROOT/scripts/cross-rewrite.sh"
TIER=memory/ddaanet

setup() {
  setup_tmp_repo
  export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
  BARE_TIER="$TMP_REPO/.bare-ddaanet.git"
}
teardown() { teardown_tmp_repo; }

# --- a tier: the parent ---

@test "cross tier: the tier's gitlink is staged in the memory store" {
  tier_old
  [ "$(git -C memory ls-files -s ddaanet | awk '{print $2}')" = "$RW_P" ]
  run --separate-stderr "$CROSS" "$TIER"
  [ "$status" -eq 0 ]
  [ "$(git -C memory ls-files -s ddaanet | awk '{print $2}')" = "$RW_N2" ]
  [ "$(git -C memory status --porcelain)" = "M  ddaanet" ]
}

# --- the memory store: gitlinks ---

# The tier crossed by hand, its gitlink staged, memory still on M2.
memory_ready() {
  cx_memory_setup "$1"
  cx_fixture_cross_tier "$2"
  [ "$(git -C memory status --porcelain)" = "M  ddaanet" ]
}

@test "cross memory: a mapped gitlink crosses; the staged tier gitlink is not dirt" {
  cx_tier_setup single
  memory_ready mapped "$RW_N2"
  run --separate-stderr "$CROSS" memory
  [ "$status" -eq 0 ]
  [ "$(git -C memory rev-parse HEAD)" = "$CX_M2N" ]
  cx_detached memory
  [ "$(git -C memory rev-parse live)" = "$CX_M2N" ]
  [ -z "$(git -C memory status --porcelain)" ]
  [ "$(git -C memory ls-files -s ddaanet | awk '{print $2}')" = "$RW_N2" ]
  cx_assert_no_archive memory "$CX_M2"
}

@test "cross memory: the project stages memory at its new HEAD" {
  cx_tier_setup single
  memory_ready mapped "$RW_N2"
  project_before=$(git ls-files -s memory | awk '{print $2}')
  run --separate-stderr "$CROSS" memory
  [ "$status" -eq 0 ]
  [ "$(git ls-files -s memory | awk '{print $2}')" = "$CX_M2N" ]
  [ "$(git ls-files -s memory | awk '{print $2}')" != "$project_before" ]
  [ "$(git status --porcelain memory)" = "M  memory" ]
}

@test "cross memory: a gitlink the child's record does not map must be unchanged, and crosses" {
  cx_tier_setup single
  cx_memory_setup unmapped
  run --separate-stderr "$CROSS" memory
  [ "$status" -eq 0 ]
  [ "$(git -C memory rev-parse HEAD)" = "$CX_M2N" ]
  [ "$(git -C memory rev-parse live)" = "$CX_M2N" ]
}

@test "cross memory: a gitlink mapped through a chain in the child's record crosses" {
  cx_tier_setup chain
  memory_ready chain "$CX_X2"
  run --separate-stderr "$CROSS" memory
  [ "$status" -eq 0 ]
  [ "$(git -C memory rev-parse HEAD)" = "$CX_M2N" ]
}

@test "cross memory: a new gitlink other than the child's mapped id refuses" {
  cx_tier_setup single
  memory_ready wrong "$RW_N2"
  before=$(rewrite_store_snapshot memory)
  project_before=$(git ls-files -s memory)
  run --separate-stderr "$CROSS" memory
  refused
  [[ "$output$stderr" == *"${CX_M2:0:7}"* ]]
  [[ "$output$stderr" == *"${CX_M2N:0:7}"* ]]
  [ "$(rewrite_store_snapshot memory)" = "$before" ]
  [ "$(git ls-files -s memory)" = "$project_before" ]
}

@test "cross memory: a gitlink the child's record does not map, yet changed, refuses" {
  cx_tier_setup single
  cx_memory_setup moved
  before=$(rewrite_store_snapshot memory)
  project_before=$(git ls-files -s memory)
  run --separate-stderr "$CROSS" memory
  refused
  [[ "$output$stderr" == *"${CX_M2:0:7}"* ]]
  [[ "$output$stderr" == *"${CX_M2N:0:7}"* ]]
  [ "$(rewrite_store_snapshot memory)" = "$before" ]
  [ "$(git ls-files -s memory)" = "$project_before" ]
}

@test "cross memory: a new tree that differs outside its mapped gitlink refuses" {
  cx_tier_setup single
  memory_ready extra "$RW_N2"
  before=$(rewrite_store_snapshot memory)
  project_before=$(git ls-files -s memory)
  run --separate-stderr "$CROSS" memory
  refused
  [[ "$output$stderr" == *"${CX_M2:0:7}"* ]]
  [[ "$output$stderr" == *"${CX_M2N:0:7}"* ]]
  [ "$(rewrite_store_snapshot memory)" = "$before" ]
  [ "$(git ls-files -s memory)" = "$project_before" ]
}

@test "cross memory: a mapped-gitlink fixture with a stray file in memory refuses as dirty" {
  cx_tier_setup single
  memory_ready mapped "$RW_N2"
  echo stray > memory/stray.md
  before=$(cx_snapshot memory)
  run --separate-stderr "$CROSS" memory
  refused
  [[ "$output$stderr" == *"uncommitted"* ]]
  [ "$(cx_snapshot memory)" = "$before" ]
}

@test "cross memory: a tier still on a recorded commit must be crossed first" {
  cx_tier_setup single
  cx_memory_setup mapped
  [ "$(git -C "$TIER" rev-parse HEAD)" = "$RW_O2" ]
  before=$(rewrite_store_snapshot memory)
  tier_before=$(rewrite_store_snapshot "$TIER")
  project_before=$(git ls-files -s memory)
  run --separate-stderr "$CROSS" memory
  refused
  [[ "$output$stderr" == *"ddaanet"* ]]
  [[ "$output$stderr" == *"cross-rewrite.sh"* ]]
  [ "$(rewrite_store_snapshot memory)" = "$before" ]
  [ "$(rewrite_store_snapshot "$TIER")" = "$tier_before" ]
  [ "$(git ls-files -s memory)" = "$project_before" ]
}

# --- the full sequence ---

@test "cross: tier then memory leaves the project with memory staged at its new HEAD" {
  cx_tier_setup single
  cx_memory_setup mapped
  run --separate-stderr "$CROSS" "$TIER"
  [ "$status" -eq 0 ]
  # Before the memory crossing the memory store shows only the staged tier.
  [ "$(git -C memory status --porcelain)" = "M  ddaanet" ]
  [ "$(git -C memory rev-parse HEAD)" = "$CX_M2" ]
  run --separate-stderr "$CROSS" memory
  [ "$status" -eq 0 ]
  [ "$(git -C memory rev-parse HEAD)" = "$CX_M2N" ]
  [ -z "$(git -C memory status --porcelain)" ]
  [ "$(git ls-files -s memory | awk '{print $2}')" = "$CX_M2N" ]
  [ "$(git status --porcelain memory)" = "M  memory" ]
}

@test "cross memory: a tier record that is advertised but cannot be fetched refuses" {
  cx_tier_setup single
  memory_ready mapped "$RW_N2"
  rewrite_break_record "$BARE_TIER"
  # Premise: advertised, and the fetch fails for a reason other than absence.
  [ -n "$(git -C "$TIER" ls-remote origin refs/heads/gitlore/rewrites)" ]
  run git -C "$TIER" fetch -q origin refs/heads/gitlore/rewrites:refs/gitlore-fixture/probe
  [ "$status" -ne 0 ]
  [[ "$output" != *"couldn't find remote ref"* ]]
  before=$(rewrite_store_snapshot memory)
  project_before=$(git status --porcelain; git ls-files -s memory)
  run --separate-stderr "$CROSS" memory
  refused
  [[ "$output$stderr" == *"gitlore/rewrites"* ]]
  [[ "$output$stderr" == *"ddaanet"* ]]
  [ "$(rewrite_store_snapshot memory)" = "$before" ]
  [ "$(git status --porcelain; git ls-files -s memory)" = "$project_before" ]
}
