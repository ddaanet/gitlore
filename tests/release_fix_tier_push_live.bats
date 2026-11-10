#!/usr/bin/env bats
# A tier with no local `live` — every checkout that did not itself mount the
# tier, since `submodule update --init` creates no branch — still publishes the
# commit memory's pin names. A missing local `live` is made from `HEAD`
# (docs/references/publishing-divergence.md), for a tier as for memory.
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

# The published store of take_base_store, with the tier's local `live` removed:
# the state a fresh clone's tier is in.
tier_without_live() {
  take_base_store ddaanet
  git -C memory/ddaanet update-ref -d refs/heads/live
  run git -C memory/ddaanet rev-parse -q --verify live
  [ "$status" -ne 0 ]
}

@test "a tier commit landed without a local live reaches the tier's remote before memory's pin does" {
  tier_without_live
  seed_tier_bullet ddaanet fresh.md "committed from a fresh clone"
  run --separate-stderr commit_sections "memory: a fact from a fresh clone"
  [ "$status" -eq 0 ] || { printf '%s\n' "$stderr" >&2; return 1; }
  pin=$(git -C memory rev-parse HEAD:ddaanet)
  [ "$pin" = "$(git -C memory/ddaanet rev-parse HEAD)" ]

  run --separate-stderr bash "$CMD"
  [ "$status" -eq 0 ] || { printf '%s\n' "$stderr" >&2; return 1; }
  [ "$(git --git-dir="$MEMORY_REMOTE" rev-parse live:ddaanet)" = "$pin" ]
  [ "$(git --git-dir="$TMP_REPO/.bare-ddaanet.git" rev-parse live)" = "$pin" ]
}

@test "a push makes a tier's missing live from HEAD and publishes it" {
  tier_without_live
  # A tier commit recorded by memory without passing through the commit path.
  seed_tier_bullet ddaanet hand.md "committed by hand"
  git -C memory/ddaanet add -A
  git -C memory/ddaanet commit -qm "tier fact by hand"
  seed_root_bullet "ddaanet/hand.md" "committed by hand"
  git -C memory add -A
  git -C memory commit -qm "record the hand commit"
  git -C memory push -q . HEAD:refs/heads/live
  pin=$(git -C memory rev-parse HEAD:ddaanet)

  run --separate-stderr bash "$CMD"
  [ "$status" -eq 0 ] || { printf '%s\n' "$stderr" >&2; return 1; }
  [ "$(git --git-dir="$MEMORY_REMOTE" rev-parse live:ddaanet)" = "$pin" ]
  [ "$(git --git-dir="$TMP_REPO/.bare-ddaanet.git" rev-parse live)" = "$pin" ]
  [ "$(git -C memory/ddaanet rev-parse live)" = "$pin" ]
}

@test "a tier commit landed without a local live makes it from the new HEAD" {
  tier_without_live
  seed_tier_bullet ddaanet fresh.md "committed from a fresh clone"
  run --separate-stderr commit_sections "memory: a fact from a fresh clone"
  [ "$status" -eq 0 ] || { printf '%s\n' "$stderr" >&2; return 1; }
  [ "$(git -C memory/ddaanet rev-parse live)" = "$(git -C memory/ddaanet rev-parse HEAD)" ]
  [ "$(git -C memory/ddaanet rev-parse live)" = "$(git -C memory rev-parse HEAD:ddaanet)" ]
}

# A no-`live` tier whose remote moved on: the `live` made from HEAD sits at the
# pin, behind the remote, so the push takes rather than prepares a merge.
@test "push-memory takes a tier without a local live whose remote moved on" {
  tier_without_live
  up=$(push_tier_fact ddaanet '- [up](up.md) — published upstream')

  run --separate-stderr bash "$CMD"
  [ "$status" -eq 0 ] || { printf '%s\n' "$stderr" >&2; return 1; }
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$up" ]
  [ "$(git --git-dir="$TMP_REPO/.bare-ddaanet.git" rev-parse live)" = "$up" ]
  run git -C memory/ddaanet rev-parse -q --verify MERGE_HEAD
  [ "$status" -ne 0 ]
}

@test "the pre-push hook takes a tier without a local live whose remote moved on" {
  tier_without_live
  up=$(push_tier_fact ddaanet '- [up](up.md) — published upstream')

  run --separate-stderr bash "$PLUGIN_ROOT/scripts/git-hooks/pre-push"
  [ "$status" -eq 0 ] || { printf '%s\n' "$stderr" >&2; return 1; }
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$up" ]
  [ "$(git --git-dir="$TMP_REPO/.bare-ddaanet.git" rev-parse live)" = "$up" ]
}
