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

# The landing record: a commit that lands a tier and then fails retries to
# completion, claims no foreign commit, and refuses one stacked on its own. The
# retry sends the summary again; the tier is clean by then, so it carries
# memory's section alone.

@test "a commit that landed a tier and then failed on memory's index retries to completion" {
  # The tier commit moves the tier ahead of the gitlink memory's index records,
  # and only memory's later `add -A` stages it. A transient index.lock between
  # the two leaves the tier ahead of its pin — the same shape the pin guard
  # refuses for a tier moved behind gitlore's back — and a retried commit
  # must recover transparently. The retry must recognise its
  # own landed tier commit and finish, not send it round the take.
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

# The same retry under a project path holding a space: the landing record and
# the landed-tier staging both handle the tier's path, and the suite otherwise
# reaches a spaced root only when the ambient TMPDIR holds one.
@test "a half-landed tier commit retries to completion under a project path holding a space" {
  teardown_tmp_repo
  TMP_REPO="$(mktemp -d "${TMPDIR:-/tmp}/gitlore test.XXXXXX")"
  export TMP_REPO
  cd "$TMP_REPO"
  git init -q -b main
  git config user.email "test@example.com"
  git config user.name "Test"
  half_landed_tier_fixture
  landing=$(gitlore_tier_landing_file memory/ddaanet)
  [[ "$landing" == *" "* ]]
  pin_before=$(git -C memory rev-parse ":ddaanet")

  run --separate-stderr commit_sections "memory: record the shared fact"
  [ "$status" -ne 0 ]
  [ -f "$lock" ]
  [ -f "$landing" ]
  [ "$(git -C memory/ddaanet rev-parse HEAD^)" = "$pin_before" ]

  rm -f "$lock"
  run --separate-stderr commit_sections "memory: record the shared fact"
  [ "$status" -eq 0 ]
  [ "$(git -C memory rev-parse HEAD:ddaanet)" = "$(git -C memory/ddaanet rev-parse HEAD)" ]
  [ ! -e "$landing" ]
  [ -z "$(git -C memory status --porcelain)" ]
}

@test "a tier commit that never landed leaves no claim on a later foreign commit" {
  # The retry adopts a tier commit only because gitlore recorded, just before
  # making it, the pin it was made on. A tier commit that fails must drop that
  # record: otherwise a commit made later on the same pin by anyone else reads
  # as gitlore's own, and its gitlink is staged without composing up.
  make_parent_with_memory
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  seed_tier_bullet ddaanet shared.md "stale hook"
  seed_root_bullet "ddaanet/shared.md" "fresh hook"
  gitlore_compose memory >/dev/null
  hook="$(git -C memory/ddaanet rev-parse --absolute-git-dir)/hooks/pre-commit"
  mkdir -p "$(dirname "$hook")"
  # shellcheck disable=SC2016  # $0 is the generated hook's own, not this shell's
  printf '#!/bin/sh\nrm -f "$0"\nexit 1\n' > "$hook"
  chmod +x "$hook"
  pin_before=$(git -C memory rev-parse ":ddaanet")

  run --separate-stderr commit_sections "memory: record the shared fact"
  [ "$status" -ne 0 ]
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$pin_before" ]

  git -C memory/ddaanet commit -q --allow-empty -m "moved outside /gitlore:merge"
  run --separate-stderr commit_sections "memory: record the shared fact"
  [ "$status" -ne 0 ]
  [ "$(git -C memory rev-parse ":ddaanet")" = "$pin_before" ]
  [[ "$stderr" == *"ahead of the pin"* ]]
}

# The landing record vouches for the commit made on its pin, never for one
# stacked on top of it: a retry whose tier HEAD's parent is not the recorded
# pin leaves the gitlink alone, and the pin guard names the tier ahead.
@test "a landing record does not adopt a foreign commit stacked on the landed one" {
  half_landed_tier_fixture
  pin_before=$(git -C memory rev-parse ":ddaanet")

  run --separate-stderr commit_sections "memory: record the shared fact"
  [ "$status" -ne 0 ]
  [ "$(git -C memory/ddaanet rev-parse HEAD^)" = "$pin_before" ]
  rm -f "$lock"

  git -C memory/ddaanet commit -q --allow-empty -m "moved outside /gitlore:merge"
  run --separate-stderr commit_sections "memory: record the shared fact"
  [ "$status" -ne 0 ]
  [ "$(git -C memory rev-parse ":ddaanet")" = "$pin_before" ]
  [[ "$stderr" == *"ahead of the pin"* ]]
}
