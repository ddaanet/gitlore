#!/usr/bin/env bats
# $stderr is populated by bats `run --separate-stderr`; shellcheck cannot see it.
# shellcheck disable=SC2154,SC2119,SC2120
bats_require_minimum_version 1.5.0

load helpers/setup
load helpers/fixtures
load helpers/tier-fixtures
load helpers/commit-memory
load helpers/divergence-fixtures
load helpers/index-compose
load helpers/cc-hook-index-compose
load helpers/add-tier

# A compose reaches a fixed point: a store the compose has just written is a
# store the next pass would leave alone. The case is a dormant tier whose
# carrier ends unterminated, activated by a manifest edit: the first pass adopts
# the carrier's lines into root, and only a second pass sees root holding the
# tier and re-lays the carrier out.

# A committed memory store with a dormant tier whose carrier is unterminated.
dormant_unterminated_tier() {
  make_parent_with_memory
  make_tier_in_memory ddaanet
  set_tier_manifest
  seed_tier_bullet ddaanet a.md first
  unterminate_index memory/ddaanet/MEMORY.md
  commit_sections "memory: dormant"
}

@test "an activation batch leaves no pending compose for the next commit" {
  dormant_unterminated_tier
  pre memory/.gitlore-tiers
  set_tier_manifest ddaanet
  feed >/dev/null

  run gitlore_compose_pending memory
  [ "$status" -eq 0 ]
  [ -z "$output" ]

  printf -- '---\nname: proj\ndescription: ""\n---\n\nbody\n' > memory/proj.md
  seed_root_bullet "proj.md" "a project fact"
  run --separate-stderr commit_sections "memory: fact"
  [ "$status" -eq 0 ]
  [[ "$stderr" != *"aborted"* ]]
}

@test "one gitlore-compose clears the abort after a terminal activation" {
  dormant_unterminated_tier
  set_tier_manifest ddaanet
  printf -- '---\nname: proj\ndescription: ""\n---\n\nbody\n' > memory/proj.md
  seed_root_bullet "proj.md" "a project fact"

  run --separate-stderr commit_sections "memory: fact"
  [ "$status" -ne 0 ]
  [[ "$stderr" == *"gitlore-compose"* ]]

  run bash "$PLUGIN_ROOT/bin/gitlore-compose"
  [ "$status" -eq 0 ]
  local composed="$output"

  run gitlore_compose_pending memory
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  # Each index is named once, however many passes the compose took.
  [ "$(printf '%s\n' "$composed" | grep -c 'memory/ddaanet/MEMORY.md')" -eq 1 ]
}

# A mount reaches the sync through add-tier.sh's own sourcing, which the suites
# that call the sync from a driver do not exercise.
mount_with_carrier() { # $1 = the carrier text, printf %b escapes
  local bare work
  make_parent_with_memory
  bare=$(make_tier_remote ddaanet)
  work="$BATS_TEST_TMPDIR/work"
  git clone -q "$bare" "$work"
  (
    cd "$work" || exit 1
    git config user.email t@example.com
    git config user.name t
    git checkout -q live
    printf '%b' "$1" > MEMORY.md
    git commit -qam carrier
    git push -q origin live
  )
  write_intent "mode=mount" "name=ddaanet" "url=$bare"
  run --separate-stderr bash "$ADD_TIER" < "$INTENT"
}

@test "add-tier: a mount of an unterminated carrier prints the refusal instead of dying on a missing function" {
  mount_with_carrier '---\ndescription: "x"\n---\n\n# t\n- [a](a.md) — first\n- [b](b.md) — b'
  [[ "$output$stderr" != *"command not found"* ]]
  # The mount's compose normalizes the carrier, which leaves the tier dirty
  # with no section in the mount's own summary: the sync's refusal is printed.
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"nothing was committed"* ]]
}

@test "add-tier: a mount of a carrier with a blank line between bullets prints the refusal instead of dying on a missing function" {
  mount_with_carrier '---\ndescription: "x"\n---\n\n# t\n- [a](a.md) — first\n\n- [b](b.md) — b\n'
  [[ "$output$stderr" != *"command not found"* ]]
  # The mount's compose normalizes the carrier, which leaves the tier dirty
  # with no section in the mount's own summary: the sync's refusal is printed.
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"nothing was committed"* ]]
}
