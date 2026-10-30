#!/usr/bin/env bats
# $stderr is populated by bats `run --separate-stderr`; shellcheck cannot see it.
# shellcheck disable=SC2154
bats_require_minimum_version 1.5.0

load helpers/setup
load helpers/fixtures
load helpers/divergence-fixtures
load helpers/tier-fixtures
load helpers/push-fixtures

# D70: the commit path never takes a merge, so a store's checked-out branch and
# its local `live` can part after a commit. /gitlore:push reconciles them after
# its remote step and before it publishes: a prepared merge routed to
# /gitlore:resolve, with nothing published. (The fast-forward direction is
# pinned in push_behind_vs_diverged.bats.)

wire_memory_remote() {
  git init -q --bare "$MEMORY_REMOTE"
  make_parent_with_memory
  publish_memory
}

commit_on_head() {
  local store="$1" file="$2"
  printf '%s\n' "$file" > "$store/$file"
  git -C "$store" add "$file"
  git -C "$store" -c user.email=t@t -c user.name=t commit -q -m "head: $file"
}

# $1 is a store holding a prepared head-vs-live merge that publishes nothing.
assert_prepared_head_vs_live() {
  local store="$1" statefile
  [ -n "$(git -C "$store" rev-parse -q --verify MERGE_HEAD)" ]
  statefile=$(git -C "$store" rev-parse --git-path gitlore-merge-state)
  [ -f "$statefile" ]
  [ "$(jq -r .flavor "$statefile")" = "head-vs-live" ]
  [[ "$output$stderr" == *"memory merge prepared"* ]]
  [[ "$output$stderr" == *"resolve.sh"* ]]
}

@test "push prepares a merge when root HEAD and live have each moved, publishing nothing" {
  wire_memory_remote
  commit_on_head memory HEAD_SIDE.md
  advance_branch_with_file memory live LIVE.md live-side "Live commit" live
  head=$(git -C memory rev-parse HEAD)
  live=$(git -C memory rev-parse live)
  remote_before=$(git --git-dir="$MEMORY_REMOTE" rev-parse live)

  run --separate-stderr bash "$CMD"
  [ "$status" -eq 1 ]
  assert_prepared_head_vs_live memory
  # The preparation checks out the authority (`live`); the pending HEAD is the merge side.
  [ "$(git -C memory rev-parse MERGE_HEAD)" = "$head" ]
  [ "$(git -C memory rev-parse live)" = "$live" ]
  [ "$(git --git-dir="$MEMORY_REMOTE" rev-parse live)" = "$remote_before" ]
}

@test "push routes a root HEAD/live conflict to the resolver" {
  wire_memory_remote
  commit_on_head memory CONF.md
  advance_branch_with_file memory live CONF.md live-version "Live edit" live

  run --separate-stderr bash "$CMD"
  [ "$status" -eq 1 ]
  assert_prepared_head_vs_live memory
  statefile=$(git -C memory rev-parse --git-path gitlore-merge-state)
  [ "$(jq -r '.conflicted_files[]' "$statefile")" = "CONF.md" ]
}

@test "push prepares a merge in the tier when its HEAD and live have each moved" {
  wire_memory_remote
  mount_tier_at_live ddaanet
  commit_on_head memory/ddaanet HEAD_SIDE.md
  advance_branch_with_file memory/ddaanet live LIVE.md live-side "Live commit" live
  head=$(git -C memory/ddaanet rev-parse HEAD)
  live=$(git -C memory/ddaanet rev-parse live)
  tier_remote_before=$(git --git-dir="$TMP_REPO/.bare-ddaanet.git" rev-parse live)

  run --separate-stderr bash "$CMD"
  [ "$status" -eq 1 ]
  assert_prepared_head_vs_live memory/ddaanet
  # The preparation checks out the authority (`live`); the pending HEAD is the merge side.
  [ "$(git -C memory/ddaanet rev-parse MERGE_HEAD)" = "$head" ]
  [ "$(git -C memory/ddaanet rev-parse live)" = "$live" ]
  [ "$(git --git-dir="$TMP_REPO/.bare-ddaanet.git" rev-parse live)" = "$tier_remote_before" ]
  [ -z "$(git -C memory rev-parse -q --verify MERGE_HEAD)" ]
}
