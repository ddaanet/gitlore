#!/usr/bin/env bats
# D62 detection at the yield: a divergence whose local side holds a recorded old
# commit is refused (nothing prepared, nothing left to continue); the same shape
# without a mapped old id proceeds as before. Fixture: tests/helpers/rewrite-fixtures.bash.
#
# $stderr is populated by bats `run --separate-stderr`; shellcheck cannot see it.
# shellcheck disable=SC2154
bats_require_minimum_version 1.5.0

load helpers/setup
load helpers/fixtures
load helpers/tier-fixtures
load helpers/divergence-fixtures
load helpers/tier-divergence
load helpers/rewrite-fixtures

MEM_BARE() { printf '%s' "$TMP_REPO/.bare-memory.git"; }

mem_setup() {
  make_parent_with_memory
  git config gitlore.hooksDir "$PLUGIN_ROOT/scripts/git-hooks"
  rewrite_remote_history memory "$(MEM_BARE)"
  rewrite_position_clone memory "$1"
}

tier_setup() {
  make_parent_with_memory
  mount_tier_at_live ddaanet
  git config gitlore.hooksDir "$PLUGIN_ROOT/scripts/git-hooks"
  rewrite_remote_history memory/ddaanet "$TMP_REPO/.bare-ddaanet.git"
  rewrite_position_clone memory/ddaanet "$1"
}

tier_state_file_memory() { git -C memory rev-parse --git-path gitlore-merge-state; }

# Fragments a refusal must carry: no directive, the crossing script, the record.
refusal_fragments() {
  [[ "$output$stderr" != *"memory merge prepared"* ]]
  [[ "$output$stderr" == *"cross-rewrite.sh"* ]]
  [[ "$output$stderr" == *"gitlore/rewrites"* ]]
}

# --- the memory store, through pre-push ---

@test "rewrite guard: no record on the remote — the yield proceeds (control)" {
  make_parent_with_memory
  git config gitlore.hooksDir "$PLUGIN_ROOT/scripts/git-hooks"
  make_diverged_head_vs_remote memory
  run --separate-stderr bash "$PRE_PUSH"
  [ "$status" -ne 0 ]
  [[ "$output$stderr" == *"memory merge prepared"* ]]
  [ -f "$(tier_state_file_memory)" ]
}

@test "rewrite guard: memory HEAD on a recorded old commit is refused, nothing prepared" {
  mem_setup old
  head_before=$(git -C memory rev-parse HEAD)
  live_before=$(git -C memory rev-parse live)
  run --separate-stderr bash "$PRE_PUSH"
  [ "$status" -ne 0 ]
  refusal_fragments
  assert_yield_left_nothing memory "$head_before" "$live_before"
}

@test "rewrite guard: record present, no recorded old commit locally — yield proceeds (control)" {
  mem_setup fresh
  run --separate-stderr bash "$PRE_PUSH"
  [ "$status" -ne 0 ]
  [[ "$output$stderr" == *"memory merge prepared"* ]]
  [ -f "$(tier_state_file_memory)" ]
}

@test "rewrite guard: the same refusal comes from /gitlore:resolve's entry point" {
  mem_setup old
  head_before=$(git -C memory rev-parse HEAD)
  live_before=$(git -C memory rev-parse live)
  run --separate-stderr bash "$RESOLVE"
  [ "$status" -ne 0 ]
  refusal_fragments
  assert_yield_left_nothing memory "$head_before" "$live_before"
}

@test "rewrite guard: /gitlore:merge (no-publish, pending=HEAD) is refused on old history" {
  mem_setup old
  head_before=$(git -C memory rev-parse HEAD)
  live_before=$(git -C memory rev-parse live)
  run --separate-stderr bash "$PLUGIN_ROOT/scripts/merge-memory.sh"
  [ "$status" -ne 0 ]
  refusal_fragments
  assert_yield_left_nothing memory "$head_before" "$live_before"
}

@test "rewrite guard: same old-history position, record absent — yield proceeds (matched control)" {
  mem_setup old
  git --git-dir="$(MEM_BARE)" update-ref -d refs/heads/gitlore/rewrites
  [ -z "$(git -C memory ls-remote origin refs/heads/gitlore/rewrites)" ]
  run --separate-stderr bash "$PRE_PUSH"
  [ "$status" -ne 0 ]
  [[ "$output$stderr" == *"memory merge prepared"* ]]
  [ -f "$(tier_state_file_memory)" ]
}

@test "rewrite guard: a record that exists but cannot be fetched refuses" {
  mem_setup fresh
  rewrite_break_record "$(MEM_BARE)"
  # Premise: the ref is advertised, and fetching it fails for a reason other
  # than "couldn't find remote ref".
  [ -n "$(git -C memory ls-remote origin refs/heads/gitlore/rewrites)" ]
  run git -C memory fetch -q origin refs/heads/gitlore/rewrites:refs/gitlore-fixture/probe
  [ "$status" -ne 0 ]
  [[ "$output" != *"couldn't find remote ref"* ]]
  head_before=$(git -C memory rev-parse HEAD)
  live_before=$(git -C memory rev-parse live)
  run --separate-stderr bash "$PRE_PUSH"
  [ "$status" -ne 0 ]
  [[ "$output$stderr" != *"memory merge prepared"* ]]
  [[ "$output$stderr" == *"gitlore/rewrites"* ]]
  assert_yield_left_nothing memory "$head_before" "$live_before"
}

# git's text can carry remote-chosen lines: the agent's copy of the refusal
# omits it, the user's keeps it.
@test "rewrite guard: a fetch failure puts git's text in the user's copy only" {
  mem_setup fresh
  rewrite_break_record "$(MEM_BARE)"
  CLAUDECODE=1 run --separate-stderr bash "$PRE_PUSH"
  [ "$status" -ne 0 ]
  [[ "$output$stderr" == *"gitlore/rewrites"* ]]
  [[ "$output$stderr" != *"git said:"* ]]
  CLAUDECODE='' run --separate-stderr bash "$PRE_PUSH"
  [ "$status" -ne 0 ]
  [[ "$output$stderr" == *"git said:"* ]]
}

@test "rewrite guard: the record fetch brings no archive branch (refused)" {
  mem_setup old
  run --separate-stderr bash "$PRE_PUSH"
  [ "$status" -ne 0 ]
  [ -n "$(git -C memory ls-remote origin 'refs/heads/gitlore/archive/*')" ]
  assert_no_archive_fetched memory
}

@test "rewrite guard: the record fetch brings no archive branch (proceeding)" {
  mem_setup fresh
  run --separate-stderr bash "$PRE_PUSH"
  [ "$status" -ne 0 ]
  [ -n "$(git -C memory ls-remote origin 'refs/heads/gitlore/archive/*')" ]
  assert_no_archive_fetched memory
}

# --- a tier ---

# A rewrite that changed the root leaves the whole history in authority..pending.
# Its ids must reach the comparison without passing through the environment, or
# exec fails (E2BIG) and a failed comparison reads as "no recorded commit".
@test "rewrite guard: thousands of local commits on old history are still refused" {
  mem_setup old
  awk -v base="$RW_LOCAL" 'BEGIN {
    for (i = 0; i < 4000; i++) {
      print "commit refs/heads/live"
      print "committer t <t@t> " (1700000000 + i) " +0000"
      print "data 2\nx\n"
      if (i == 0) print "from " base
    }
  }' | git -C memory fast-import --quiet
  git -C memory checkout -q --detach live
  [ "$(git -C memory rev-list --count origin/live..live)" -gt 3500 ]
  head_before=$(git -C memory rev-parse HEAD)
  live_before=$(git -C memory rev-parse live)
  run --separate-stderr bash "$PRE_PUSH"
  [ "$status" -ne 0 ]
  refusal_fragments
  assert_yield_left_nothing memory "$head_before" "$live_before"
}

@test "rewrite guard: a tier on a recorded old commit is refused, nothing prepared" {
  tier_setup old
  head_before=$(git -C memory/ddaanet rev-parse HEAD)
  live_before=$(git -C memory/ddaanet rev-parse live)
  run --separate-stderr bash "$PRE_PUSH"
  [ "$status" -ne 0 ]
  refusal_fragments
  assert_yield_left_nothing memory/ddaanet "$head_before" "$live_before"
}

@test "rewrite guard: a tier with a record but no recorded old commit proceeds (control)" {
  tier_setup fresh
  run --separate-stderr bash "$PRE_PUSH"
  [ "$status" -ne 0 ]
  [[ "$output$stderr" == *"memory merge prepared"* ]]
  [ -f "$(tier_state_file ddaanet)" ]
}

@test "rewrite guard: a tier record that exists but cannot be fetched refuses" {
  tier_setup fresh
  rewrite_break_record "$TMP_REPO/.bare-ddaanet.git"
  # Premise: advertised, and the fetch fails for a reason other than absence.
  [ -n "$(git -C memory/ddaanet ls-remote origin refs/heads/gitlore/rewrites)" ]
  run git -C memory/ddaanet fetch -q origin refs/heads/gitlore/rewrites:refs/gitlore-fixture/probe
  [ "$status" -ne 0 ]
  [[ "$output" != *"couldn't find remote ref"* ]]
  head_before=$(git -C memory/ddaanet rev-parse HEAD)
  live_before=$(git -C memory/ddaanet rev-parse live)
  run --separate-stderr bash "$PRE_PUSH"
  [ "$status" -ne 0 ]
  [[ "$output$stderr" != *"memory merge prepared"* ]]
  [[ "$output$stderr" == *"gitlore/rewrites"* ]]
  assert_yield_left_nothing memory/ddaanet "$head_before" "$live_before"
  [ -n "$(git -C memory/ddaanet ls-remote origin 'refs/heads/gitlore/archive/*')" ]
  assert_no_archive_fetched memory/ddaanet
}
