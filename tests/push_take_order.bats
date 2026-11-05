#!/usr/bin/env bats
# A tier with uncommitted work is refused only when it has something to take,
# and the same state gets the same answer through the pre-push hook and through
# /gitlore:push. A dirty tier with nothing to take blocks no other tier.
#
# $stderr is populated by bats `run --separate-stderr`; shellcheck cannot see it.
# shellcheck disable=SC2154
bats_require_minimum_version 1.5.0

load helpers/setup
load helpers/fixtures
load helpers/tier-fixtures
load helpers/stub-synth
load helpers/merge-memory
load helpers/take-order
load helpers/push-fixtures

# Tier alpha is behind its remote; tier beta holds an uncommitted fact and its
# remote has nothing for it. Sets $up, the commit alpha has to take.
dirty_tier_with_nothing_to_take() {
  take_base_store alpha beta
  up=$(push_tier_fact alpha '- [a-up](a-up.md) — published upstream')
  seed_tier_bullet beta mine.md "an uncommitted fact"
}

@test "the pre-push hook takes a tier that is behind past a dirty tier with nothing to take" {
  dirty_tier_with_nothing_to_take
  b=$(git -C memory/beta rev-parse HEAD)

  run --separate-stderr bash "$PLUGIN_ROOT/scripts/git-hooks/pre-push"
  [ "$status" -eq 0 ] || { printf '%s\n' "$stderr" >&2; return 1; }
  [[ "$stderr" != *"tier 'beta' has uncommitted changes"* ]]
  [ "$(git -C memory/alpha rev-parse HEAD)" = "$up" ]
  [ "$(git -C memory/beta rev-parse HEAD)" = "$b" ]
  [ -f memory/beta/mine.md ]
}

@test "push-memory takes a tier that is behind past a dirty tier with nothing to take" {
  dirty_tier_with_nothing_to_take
  b=$(git -C memory/beta rev-parse HEAD)

  run --separate-stderr bash "$CMD"
  [[ "$stderr" != *"tier 'beta' has uncommitted changes"* ]]
  [ "$(git -C memory/alpha rev-parse HEAD)" = "$up" ]
  [ "$(git -C memory/beta rev-parse HEAD)" = "$b" ]
  [ -f memory/beta/mine.md ]
}

@test "push-memory refuses a dirty tier with something to take before another tier moves" {
  take_base_store alpha beta
  push_tier_fact alpha '- [a-up](a-up.md) — published upstream' >/dev/null
  push_tier_fact beta '- [b-up](b-up.md) — published upstream' >/dev/null
  seed_tier_bullet beta mine.md "an uncommitted fact"
  a=$(git -C memory/alpha rev-parse HEAD)
  b=$(git -C memory/beta rev-parse HEAD)
  root=$(git -C memory rev-parse HEAD)

  run --separate-stderr bash "$CMD"
  [ "$status" -ne 0 ]
  [[ "$stderr" == *"tier 'beta' has uncommitted changes"* ]]
  [[ "$stderr" == *[Cc]ommit\ * ]]
  [ "$(git -C memory/alpha rev-parse HEAD)" = "$a" ]
  [ "$(git -C memory/beta rev-parse HEAD)" = "$b" ]
  [ "$(git -C memory rev-parse HEAD)" = "$root" ]
}
