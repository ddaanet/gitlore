#!/usr/bin/env bats
# A memory root with uncommitted changes whose HEAD has forked from its local
# `live` is refused before any tier moves, by every entry that takes tiers. A
# tier moved first would sit ahead of its pin, so the memory commit the refusal
# asks for would itself be refused by the pin guard naming the take again.
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

@test "resolve: a dirty root forked from live is refused with the tier unmoved, and converges after the commit" {
  dirty_diverged_root_with_tier_news
  run bash "$PLUGIN_ROOT/scripts/resolve.sh"
  [ "$status" -eq 1 ]
  assert_refused_then_converges
}
