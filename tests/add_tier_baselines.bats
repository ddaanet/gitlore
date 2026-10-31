#!/usr/bin/env bats
# scripts/add-tier.sh — D71: the mount composes and reports on its own stdout,
# so the PostToolBatch hooks must not report it a second time. They key on
# per-agent baselines (compose stamp, MEMORY.md pre-image) that
# index-sync-pre.sh took before the Bash call; the script cannot know the agent
# id, so it moves every baseline equal to the pre-run state to the post-run one
# and leaves a baseline that differs (a batch that changed something else).
# Each @test is its own subshell; per-test exports are consumed within that same
# test, so SC2030/SC2031 are false positives here.
# shellcheck disable=SC2030,SC2031,SC2119,SC2120
bats_require_minimum_version 1.5.0

load helpers/setup
load helpers/fixtures
load helpers/tier-fixtures
load helpers/cc-hook-index-compose   # pre/feed/sync_feed/drain_feed; its setup is replaced below
load helpers/add-tier

# Push a fact FILE and its index line onto a tier remote's `live`. index-sync-post
# skips an index line whose target is not a file, and rewrites a file whose
# frontmatter description differs from the line's hook, so only a real file
# gives the post hook something to write if its pre-image is left stale.
push_tier_fact_file() {
  local tier="$1" bare work
  bare="$TMP_REPO/.bare-$tier.git"
  work="$(mktemp -d "${TMPDIR:-/tmp}/gitlore-tier-work.XXXXXX")"
  git clone -q "$bare" "$work"
  (
    cd "$work" || exit 1
    git config user.email "test@example.com"
    git config user.name  "Test"
    git checkout -q -B live origin/live
    printf -- '---\nname: x\ndescription: ""\ntype: reference\n---\n\nbody\n' > x.md
    printf -- '- [x](x.md) — from live\n' >> MEMORY.md
    git add -A
    git commit -qm "remote tier fact file"
    git push -q origin live
  )
  rm -rf "$work"
}

# A mount whose tier carries a fact on `live`, so the compose has a report.
mount_with_facts() {
  make_parent_with_memory
  bare=$(make_tier_remote ddaanet)
  push_tier_fact_file ddaanet
  write_intent "mode=mount" "name=ddaanet" "url=$bare"
}

# The compose stamp as index-sync-pre.sh takes it, from the project root.
current_stamp() {
  gitlore_compose_stamp memory/MEMORY.md memory/.gitlore-tiers
}

# One Bash call of the batch: pre hook, the script, then the two PostToolBatch
# hooks. $1 = agent id, optional. Leaves the compose hook's output in
# $feed_out and the sync hook's in $sync_out.
mount_in_batch() {
  local agent="${1:-}"
  pre Bash "$agent"
  run bash "$ADD_TIER" < "$INTENT"
  [ "$status" -eq 0 ]
  [ -e memory/ddaanet/.git ]
  run feed "$agent"
  [ "$status" -eq 0 ]
  feed_out="$output"
  run sync_feed "$agent"
  [ "$status" -eq 0 ]
  sync_out="$output"
}

# --- the hooks stay quiet after the mount ------------------------------------

@test "add-tier baselines: the mount's compose is reported once on the main thread" {
  mount_with_facts
  # The script is the one reporter; the hook beside it has nothing to add.
  mount_in_batch
  [ -z "$feed_out" ]
  [ -z "$sync_out" ]
  # Not silent for want of anything to say: the compose ran and the facts landed.
  grep -qF -- '- [x](ddaanet/x.md) — from live' memory/MEMORY.md
}

@test "add-tier baselines: the script's stdout, not the hook's, carries the compose report" {
  mount_with_facts
  pre Bash
  run bash "$ADD_TIER" < "$INTENT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"recomposed tier pointers"* ]]
}

@test "add-tier baselines: the mount's compose is reported once from a subagent" {
  mount_with_facts
  mount_in_batch agent-a1
  [ -z "$feed_out" ]
  [ -z "$sync_out" ]
  # The compose hook relays a subagent's report through a marker for the
  # parent's drain; a quiet hook leaves none.
  [ -z "$(find "$(git -C memory rev-parse --absolute-git-dir)" -maxdepth 1 -name 'gitlore-relay-*-agent-a1-*')" ]
  run drain_feed
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "add-tier baselines: a parent batch in flight beside a subagent mount stays quiet too" {
  mount_with_facts
  pre Bash
  pre Bash agent-a1
  run bash "$ADD_TIER" < "$INTENT"
  [ "$status" -eq 0 ]
  run feed agent-a1
  [ -z "$output" ]
  run sync_feed agent-a1
  [ -z "$output" ]
  run feed
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  run sync_feed
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "add-tier baselines: the sync hook writes nothing into the store after the mount" {
  mount_with_facts
  pre Bash
  run bash "$ADD_TIER" < "$INTENT"
  [ "$status" -eq 0 ]
  [ -z "$(git -C memory status --porcelain)" ]
  head=$(git -C memory rev-parse HEAD)
  tier_head=$(git -C memory/ddaanet rev-parse HEAD)

  run sync_feed
  [ "$status" -eq 0 ]
  [ -z "$(git -C memory status --porcelain)" ]
  [ -z "$(git -C memory/ddaanet status --porcelain)" ]
  [ "$(git -C memory rev-parse HEAD)" = "$head" ]
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$tier_head" ]
}

@test "add-tier baselines: a mount into a store with pending work stays quiet in the hooks" {
  mount_with_facts
  printf -- '---\nname: orphan\ndescription: ""\n---\n\nbody\n' > memory/orphan.md
  mount_in_batch
  [ -z "$feed_out" ]
  [ -z "$sync_out" ]
  [ -f memory/orphan.md ]
}

# --- the baseline rule itself ------------------------------------------------

@test "add-tier baselines: only a baseline equal to the pre-run state moves; none is deleted" {
  mount_with_facts
  pre_stamp=$(current_stamp)
  pre_index=$(cat memory/MEMORY.md)
  stamp_main=$(gitlore_compose_stamp_file memory)
  stamp_eq=$(gitlore_compose_stamp_file memory agent-eq)
  stamp_ne=$(gitlore_compose_stamp_file memory agent-ne)
  pre_main=$(gitlore_index_preimage_file memory)
  pre_eq=$(gitlore_index_preimage_file memory agent-eq)
  pre_ne=$(gitlore_index_preimage_file memory agent-ne)

  printf '%s\n' "$pre_stamp" > "$stamp_main"
  printf '%s\n' "$pre_stamp" > "$stamp_eq"
  printf '%s\nindex\tdeadbeef\n' "$pre_stamp" > "$stamp_ne"
  cp memory/MEMORY.md "$pre_main"
  cp memory/MEMORY.md "$pre_eq"
  printf '%s\n- [other](other.md) — a batch edit\n' "$pre_index" > "$pre_ne"
  ne_stamp_before=$(cat "$stamp_ne")
  ne_index_before=$(cat "$pre_ne")

  run bash "$ADD_TIER" < "$INTENT"
  [ "$status" -eq 0 ]

  post_stamp=$(current_stamp)
  # The mount moved the state, so "equal to post-run" is not "unchanged".
  [ "$post_stamp" != "$pre_stamp" ]
  [ "$(cat memory/MEMORY.md)" != "$pre_index" ]

  [ "$(cat "$stamp_main")" = "$post_stamp" ]
  [ "$(cat "$stamp_eq")" = "$post_stamp" ]
  [ "$(cat "$stamp_ne")" = "$ne_stamp_before" ]
  cmp -s "$pre_main" memory/MEMORY.md
  cmp -s "$pre_eq" memory/MEMORY.md
  [ "$(cat "$pre_ne")" = "$ne_index_before" ]
  [ -f "$stamp_ne" ]
  [ -f "$pre_ne" ]
}

@test "add-tier baselines: a store with no baselines gains none" {
  mount_with_facts
  run bash "$ADD_TIER" < "$INTENT"
  [ "$status" -eq 0 ]
  [ ! -e "$(gitlore_compose_stamp_file memory)" ]
  [ ! -e "$(gitlore_index_preimage_file memory)" ]
}
