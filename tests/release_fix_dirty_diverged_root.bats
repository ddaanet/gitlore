#!/usr/bin/env bats
# A memory root with uncommitted changes whose HEAD has forked from its local
# `live` is refused at the tier take, before the take moves any tier, and at
# the yield, before a tier merge the push or the resolve command prepares.
# A tier moved first would sit ahead of its pin, so the memory commit the
# refusal asks for would itself be refused by the pin guard naming the take
# again. A pre-push that takes no tier publishes as it does on any dirty root,
# and /gitlore:resolve moves no tier in this state at all.
bats_require_minimum_version 1.5.0
load helpers/setup
load helpers/fixtures
load helpers/tier-fixtures
load helpers/stub-synth
load helpers/merge-memory
load helpers/take-order

# The Claim 1 start state: tier ddaanet has one upstream commit to fast-forward,
# the memory remote has a commit of its own, memory's HEAD has forked from its
# local `live`, and root holds an uncommitted fact and its index line.
# Leaves the tier's upstream sha in TIER_UP.
dirty_diverged_root_with_tier_news() {
  take_base_store ddaanet
  TIER_UP=$(push_tier_fact ddaanet '- [up](up.md) — published upstream')
  push_memory_fact
  fork_root_from_live
  printf -- '---\nname: dirty\ndescription: ""\n---\n\nbody\n' > memory/dirty.md
  seed_root_bullet dirty.md "an uncommitted root fact"
}

PRE_PUSH="$PLUGIN_ROOT/scripts/git-hooks/pre-push"

# After the refused entry: the tier sits where root records it, the commit the
# refusal asks for goes through, and the next take converges.
assert_refused_then_converges() {
  local pin
  pin=$(git -C memory rev-parse HEAD:ddaanet)
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$pin" ]
  [ "$(git -C memory/ddaanet rev-parse HEAD)" != "$TIER_UP" ]

  run commit_sections "memory: record dirty"
  [ "$status" -eq 0 ]
  git -C memory cat-file -e HEAD:dirty.md

  drive_take_to_rest memory/ddaanet
  [ "$TAKE_STATUS" -eq 0 ]
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$TIER_UP" ]
  [ "$(git -C memory rev-parse HEAD:ddaanet)" = "$TIER_UP" ]
  grep -qF '](ddaanet/up.md)' memory/MEMORY.md
  [ "$(git -C memory rev-parse HEAD)" = "$(git -C memory rev-parse live)" ]
}

# The tier-merge start state: tier ddaanet holds a recorded commit of its own
# and its remote one this checkout lacks, so the tier has diverged from its
# remote; memory's local `live` has forked off HEAD, and root holds an
# uncommitted fact and its index line. Leaves the tier remote's sha in TIER_UP.
dirty_diverged_root_with_tier_merge() {
  take_base_store ddaanet
  local_tier_commit_recorded ddaanet loc.md
  TIER_UP=$(push_tier_fact ddaanet '- [up](up.md) — published upstream')
  git -C memory branch -f live "$(git -C memory commit-tree "HEAD^{tree}" -p HEAD~1 -m elsewhere)"
  printf -- '---\nname: dirty\ndescription: ""\n---\n\nbody\n' > memory/dirty.md
  seed_root_bullet dirty.md "an uncommitted root fact"
}

# After a refused tier merge: nothing moved or was prepared in either store,
# and the tier remote received nothing.
assert_tier_merge_refused() {
  local store
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$(git -C memory rev-parse HEAD:ddaanet)" ]
  for store in memory memory/ddaanet; do
    [ ! -e "$(gitlore_merge_state_file "$store")" ]
    [ -z "$(git -C "$store" rev-parse -q --verify MERGE_HEAD || true)" ]
  done
  [ "$(git -C memory/ddaanet ls-remote origin refs/heads/live | cut -f1)" = "$TIER_UP" ]
}

# The commit the refusal asks for goes through, and entry $1 then prepares the
# tier merge.
assert_commit_then_tier_merge_prepared() {
  run commit_sections "memory: record dirty"
  [ "$status" -eq 0 ]
  git -C memory cat-file -e HEAD:dirty.md

  run bash "$1"
  [ "$status" -ne 0 ]
  [ -f "$(gitlore_merge_state_file memory/ddaanet)" ]
  git -C memory/ddaanet rev-parse -q --verify MERGE_HEAD
}

@test "merge: a dirty root forked from live is refused before the tier moves, and converges after the commit" {
  dirty_diverged_root_with_tier_news
  run bash "$CMD"
  [ "$status" -eq 1 ]
  assert_refused_then_converges
}

@test "push: a dirty root forked from live is refused before the tier moves, and converges after the commit" {
  dirty_diverged_root_with_tier_news
  run bash "$PLUGIN_ROOT/scripts/push-memory.sh"
  [ "$status" -eq 1 ]
  assert_refused_then_converges
}

@test "resolve: moves no tier on a dirty root forked from live, and the commit it asks for converges" {
  dirty_diverged_root_with_tier_news
  run bash "$PLUGIN_ROOT/scripts/resolve.sh"
  [ "$status" -eq 1 ]
  assert_refused_then_converges
}

@test "pre-push: a tier with upstream news on a dirty root forked from live is refused before the tier moves" {
  dirty_diverged_root_with_tier_news
  run bash "$PRE_PUSH"
  [ "$status" -ne 0 ]
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$(git -C memory rev-parse HEAD:ddaanet)" ]
  [ "$(git -C memory/ddaanet rev-parse HEAD)" != "$TIER_UP" ]
}

@test "pre-push: local-only memory with a dirty root forked from live still publishes the tier" {
  take_base_store ddaanet
  git -C memory remote remove origin
  # Fork `live` off HEAD: a commit HEAD lacks, made by another checkout.
  git -C memory branch -f live "$(git -C memory commit-tree "HEAD^{tree}" -p HEAD -m "elsewhere")"
  # A tier commit, recorded by root on HEAD and published nowhere yet.
  seed_tier_bullet ddaanet unpublished.md "a recorded tier fact"
  run commit_sections "a tier fact"
  [ "$status" -eq 0 ]
  tier_head=$(git -C memory/ddaanet rev-parse HEAD)
  [ "$(git -C memory rev-parse HEAD:ddaanet)" = "$tier_head" ]
  [ "$(git -C memory/ddaanet ls-remote origin refs/heads/live | cut -f1)" != "$tier_head" ]
  [ "$(git -C memory merge-base HEAD live)" != "$(git -C memory rev-parse live)" ]
  printf -- '---\nname: dirty\ndescription: ""\n---\n\nbody\n' > memory/dirty.md
  seed_root_bullet dirty.md "an uncommitted root fact"

  run bash "$PRE_PUSH"
  [ "$status" -eq 0 ]
  [ "$(git -C memory/ddaanet ls-remote origin refs/heads/live | cut -f1)" = "$tier_head" ]
}

@test "pre-push: a tier merge on a dirty root forked from live is refused before it is prepared" {
  dirty_diverged_root_with_tier_merge
  CLAUDECODE=1 run bash "$PRE_PUSH"
  [ "$status" -ne 0 ]
  assert_tier_merge_refused
  [[ "$output" == *"gitlore: memory has uncommitted changes and has diverged from 'live', so no merge was prepared. Commit them (approved summary, then a memory commit) and run the command again."* ]]
  assert_commit_then_tier_merge_prepared "$PRE_PUSH"
}

@test "pre-push from a terminal: a tier merge on a dirty root forked from live is refused" {
  dirty_diverged_root_with_tier_merge
  run env -u CLAUDECODE bash "$PRE_PUSH"
  [ "$status" -ne 0 ]
  assert_tier_merge_refused
  [[ "$output" == *"gitlore: memory has uncommitted changes and has diverged from 'live', so no merge was prepared. Commit them and try again."* ]]
  assert_commit_then_tier_merge_prepared "$PRE_PUSH"
}

@test "resolve: a tier merge on a dirty root forked from live is refused before it is prepared" {
  dirty_diverged_root_with_tier_merge
  CLAUDECODE=1 run bash "$PLUGIN_ROOT/scripts/resolve.sh"
  [ "$status" -eq 1 ]
  assert_tier_merge_refused
  [[ "$output" == *"gitlore: memory has uncommitted changes and has diverged from 'live', so no merge was prepared. Commit them (approved summary, then a memory commit) and run the command again."* ]]
  assert_commit_then_tier_merge_prepared "$PLUGIN_ROOT/scripts/resolve.sh"
}
