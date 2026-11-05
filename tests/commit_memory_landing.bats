#!/usr/bin/env bats
# $stderr is populated by bats `run --separate-stderr`; shellcheck cannot see it.
# shellcheck disable=SC2154
# The spaced-root case re-roots $TMP_REPO inside its own test body.
# shellcheck disable=SC2030,SC2031
bats_require_minimum_version 1.5.0

load helpers/setup
load helpers/fixtures
load helpers/tier-fixtures
load helpers/commit-memory

# A commit that lands a tier and then fails on memory retries to completion: the
# tier sits ahead of its pin, and the retry's `add -A` records it. The retry
# sends the summary again; the tier is clean by then, so it carries memory's
# section alone.

@test "a commit that landed a tier and then failed on memory's index retries to completion" {
  # The tier commit moves the tier ahead of the gitlink memory's index records,
  # and only memory's later `add -A` stages it. A transient index.lock between
  # the two leaves the tier ahead of its pin, and the retry finishes.
  half_landed_tier_fixture
  pin_before=$(git -C memory rev-parse ":ddaanet")

  run --separate-stderr commit_sections "memory: record the shared fact"
  [ "$status" -ne 0 ]
  # The fixture's shape, asserted rather than assumed: the tier commit landed
  # and memory's index still records the pin it started from.
  [ -f "$lock" ]
  [ "$(git -C memory/ddaanet rev-parse HEAD^)" = "$pin_before" ]
  [ "$(git -C memory rev-parse ":ddaanet")" = "$pin_before" ]

  rm -f "$lock"
  run --separate-stderr commit_sections "memory: record the shared fact"
  [ "$status" -eq 0 ]
  [ "$(git -C memory rev-parse HEAD:ddaanet)" = "$(git -C memory/ddaanet rev-parse HEAD)" ]
  [ "$(git -C memory log -1 --pretty=%s)" = "memory: record the shared fact" ]
  git -C memory/ddaanet show HEAD:MEMORY.md > "$BATS_TEST_TMPDIR/carrier.md"
  assert_bullets "$BATS_TEST_TMPDIR/carrier.md" \
    '- [shared](shared.md) — fresh hook'
  [ -z "$(git -C memory status --porcelain)" ]
}

# The same retry under a project path holding a space, which the suite otherwise
# reaches only when the ambient TMPDIR holds one.
@test "a half-landed tier commit retries to completion under a project path holding a space" {
  teardown_tmp_repo
  TMP_REPO="$(mktemp -d "${TMPDIR:-/tmp}/gitlore test.XXXXXX")"
  export TMP_REPO
  cd "$TMP_REPO"
  git init -q -b main
  git config user.email "test@example.com"
  git config user.name "Test"
  half_landed_tier_fixture
  [[ "$TMP_REPO" == *" "* ]]
  pin_before=$(git -C memory rev-parse ":ddaanet")

  run --separate-stderr commit_sections "memory: record the shared fact"
  [ "$status" -ne 0 ]
  [ -f "$lock" ]
  [ "$(git -C memory/ddaanet rev-parse HEAD^)" = "$pin_before" ]

  rm -f "$lock"
  run --separate-stderr commit_sections "memory: record the shared fact"
  [ "$status" -eq 0 ]
  [ "$(git -C memory rev-parse HEAD:ddaanet)" = "$(git -C memory/ddaanet rev-parse HEAD)" ]
  [ -z "$(git -C memory status --porcelain)" ]
}
