#!/usr/bin/env bats
# $stderr is populated by bats `run --separate-stderr`; shellcheck cannot see it.
# shellcheck disable=SC2154
bats_require_minimum_version 1.5.0

load helpers/setup
load helpers/fixtures
load helpers/divergence-fixtures
load helpers/tier-fixtures
load helpers/merge-memory

# D70: the commit path never takes a merge, so a store's checked-out branch and
# its local `live` can part after a commit. /gitlore:merge reconciles them after
# its remote step: fast-forward when one contains the other, else a prepared
# merge routed to /gitlore:resolve, as a diverged remote is. The fast-forward
# direction (HEAD contains `live`) is pinned in merge_memory.bats.

# A commit on the store's detached HEAD that `live` does not have.
commit_on_head() {
  local store="$1" file="$2"
  printf '%s\n' "$file" > "$store/$file"
  git -C "$store" add "$file"
  git -C "$store" -c user.email=t@t -c user.name=t commit -q -m "head: $file"
}

# Root store wired to a published remote, then HEAD and `live` parted.
diverged_root() {
  wire_memory_remote
  commit_on_head memory HEAD_SIDE.md
  advance_branch_with_file memory live LIVE.md live-side "Live commit" live
}

# The same for a mounted tier.
diverged_tier() {
  wire_memory_remote
  mount_tier_at_live ddaanet
  commit_on_head memory/ddaanet HEAD_SIDE.md
  advance_branch_with_file memory/ddaanet live LIVE.md live-side "Live commit" live
}

# $1 is a store holding a prepared head-vs-live merge for the resolver.
assert_prepared_head_vs_live() {
  local store="$1" statefile
  [ -n "$(git -C "$store" rev-parse -q --verify MERGE_HEAD)" ]
  statefile=$(git -C "$store" rev-parse --git-path gitlore-merge-state)
  [ -f "$statefile" ]
  [ "$(jq -r .flavor "$statefile")" = "head-vs-live" ]
  [ "$(jq -r .publish "$statefile")" = "no" ]
  [[ "$output$stderr" == *"memory merge prepared"* ]]
  [[ "$output$stderr" == *"resolve.sh"* ]]
}

@test "merge prepares a merge when root HEAD and live have each moved" {
  diverged_root
  head=$(git -C memory rev-parse HEAD)
  live=$(git -C memory rev-parse live)

  run --separate-stderr bash "$CMD"
  [ "$status" -eq 1 ]
  assert_prepared_head_vs_live memory
  # The preparation checks out the authority (`live`); the pending HEAD is the merge side.
  [ "$(git -C memory rev-parse MERGE_HEAD)" = "$head" ]
  [ "$(git -C memory rev-parse live)" = "$live" ]
}

@test "merge routes a root HEAD/live conflict to the resolver" {
  wire_memory_remote
  commit_on_head memory CONF.md
  advance_branch_with_file memory live CONF.md live-version "Live edit" live
  # Same path, different bytes on each side.
  git -C memory show live:CONF.md | grep -qx live-version

  run --separate-stderr bash "$CMD"
  [ "$status" -eq 1 ]
  assert_prepared_head_vs_live memory
  statefile=$(git -C memory rev-parse --git-path gitlore-merge-state)
  [ "$(jq -r '.conflicted_files[]' "$statefile")" = "CONF.md" ]
}

@test "merge prepares a merge in the tier when its HEAD and live have each moved" {
  diverged_tier
  head=$(git -C memory/ddaanet rev-parse HEAD)
  live=$(git -C memory/ddaanet rev-parse live)

  run --separate-stderr bash "$CMD"
  [ "$status" -eq 1 ]
  assert_prepared_head_vs_live memory/ddaanet
  # The preparation checks out the authority (`live`); the pending HEAD is the merge side.
  [ "$(git -C memory/ddaanet rev-parse MERGE_HEAD)" = "$head" ]
  [ "$(git -C memory/ddaanet rev-parse live)" = "$live" ]
  # The merge lives in the tier; memory is not mid-merge.
  [ -z "$(git -C memory rev-parse -q --verify MERGE_HEAD)" ]
}

@test "merge prepares a diverged root while a tier sits ahead of the gitlink root records, staging the tier's HEAD" {
  wire_memory_remote
  mount_tier_at_live ddaanet
  # Root records the tier at its current HEAD, so only the commit below moves it.
  git -C memory add ddaanet
  git -C memory -c user.email=t@t -c user.name=t commit -q --allow-empty -m "pin ddaanet"
  git -C memory branch -f live HEAD
  commit_on_head memory HEAD_SIDE.md
  advance_branch_with_file memory live LIVE.md live-side "Live commit" live
  commit_on_head memory/ddaanet MOVED.md
  [ -n "$(git -C memory status --porcelain -- ddaanet)" ]

  run --separate-stderr bash "$CMD"
  [ "$status" -eq 1 ]
  [[ "$stderr" != *"uncommitted changes"* ]]
  # The tier moves first, so the root merge is prepared with its HEAD staged.
  [ -n "$(git -C memory rev-parse -q --verify MERGE_HEAD)" ]
  [ "$(git -C memory rev-parse :ddaanet)" = "$(git -C memory/ddaanet rev-parse HEAD)" ]
}
