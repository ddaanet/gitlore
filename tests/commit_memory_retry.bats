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

# Retries: a commit that lands a tier or memory's own commit and then fails
# retries to completion, and the approved summary survives every failure point.

@test "a commit that landed a tier and then failed on memory's index retries to completion" {
  # The tier commit moves the tier ahead of the gitlink memory's index records,
  # and only memory's later `add -A` stages it. A transient index.lock between
  # the two leaves the tier ahead of its pin — the same shape the pin guard
  # refuses for a tier moved behind gitlore's back — and memory-commit-batch.sh
  # promises the next batch retries transparently. The retry must recognise its
  # own landed tier commit and finish, not send it round the take.
  half_landed_tier_fixture
  pin_before=$(git -C memory rev-parse ":ddaanet")

  run --separate-stderr bash "$CMD" -m "memory: record the shared fact"
  [ "$status" -ne 0 ]
  # The fixture's shape, asserted rather than assumed: the tier commit landed
  # and memory's index still records the pin it started from.
  [ -f "$lock" ]
  [ "$(git -C memory/ddaanet rev-parse HEAD^)" = "$pin_before" ]
  [ "$(git -C memory rev-parse ":ddaanet")" = "$pin_before" ]

  rm -f "$lock"
  run --separate-stderr bash "$CMD" -F "$(gitlore_commit_msg_file memory)"
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

  run --separate-stderr bash "$CMD" -m "memory: record the shared fact"
  [ "$status" -ne 0 ]
  [ -f "$lock" ]
  [ -f "$landing" ]
  [ "$(git -C memory/ddaanet rev-parse HEAD^)" = "$pin_before" ]

  rm -f "$lock"
  run --separate-stderr bash "$CMD" -F "$(gitlore_commit_msg_file memory)"
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
  hook="$(git -C memory/ddaanet rev-parse --absolute-git-dir)/hooks/pre-commit"
  mkdir -p "$(dirname "$hook")"
  # shellcheck disable=SC2016  # $0 is the generated hook's own, not this shell's
  printf '#!/bin/sh\nrm -f "$0"\nexit 1\n' > "$hook"
  chmod +x "$hook"
  pin_before=$(git -C memory rev-parse ":ddaanet")

  run --separate-stderr bash "$CMD" -m "memory: record the shared fact"
  [ "$status" -ne 0 ]
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$pin_before" ]

  git -C memory/ddaanet commit -q --allow-empty -m "moved outside /gitlore:merge"
  run --separate-stderr bash "$CMD" -m "memory: record the shared fact"
  [ "$status" -ne 0 ]
  [ "$(git -C memory rev-parse ":ddaanet")" = "$pin_before" ]
  [[ "$stderr" == *"ahead of the pin"* ]]
}

@test "a commit that fails after composing keeps the approval for the retry" {
  # The pre-commit path retries on the summary file as it stands — only
  # commit-memory.sh rewrites it. The first run's compose re-texts the carrier,
  # a write newer than the summary, so a failure after it must restamp the file
  # or the retry is refused as unapproved for a projection the summary covers.
  half_landed_tier_fixture
  msgfile=$(gitlore_commit_msg_file memory)
  printf 'memory: record the shared fact\n' > "$msgfile"
  # gitlore_commit_msg_freshness compares whole-second mtimes with `>=`, so a
  # carrier write landing in the summary's second would read fresh unrestamped.
  sleep 1

  write_sync_driver

  run --separate-stderr bash "$driver"
  [ "$status" -ne 0 ]
  # The fixture's shape: compose re-texted the carrier, and the run died past it.
  assert_bullets memory/ddaanet/MEMORY.md '- [shared](shared.md) — fresh hook'
  [ -f "$lock" ]
  [ "$(gitlore_commit_msg_freshness memory)" = "yes" ]
}

# A composed carrier the run then fails to commit: the same one-shot hook
# refusal the foreign-commit case above uses, measured on the approval
# instead of on the landing record.
@test "a tier commit that fails after composing keeps the approval for the retry" {
  make_parent_with_memory
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  seed_tier_bullet ddaanet shared.md "stale hook"
  seed_root_bullet "ddaanet/shared.md" "fresh hook"
  hook="$(git -C memory/ddaanet rev-parse --absolute-git-dir)/hooks/pre-commit"
  mkdir -p "$(dirname "$hook")"
  # shellcheck disable=SC2016  # $0 is the generated hook's own, not this shell's
  printf '#!/bin/sh\nrm -f "$0"\nexit 1\n' > "$hook"
  chmod +x "$hook"
  msgfile=$(gitlore_commit_msg_file memory)
  printf 'memory: record the shared fact\n' > "$msgfile"
  # Whole-second mtimes compared with `>=` — see the case above.
  sleep 1
  pin_before=$(git -C memory rev-parse ":ddaanet")
  write_sync_driver

  run --separate-stderr bash "$driver"
  [ "$status" -ne 0 ]
  assert_bullets memory/ddaanet/MEMORY.md '- [shared](shared.md) — fresh hook'
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$pin_before" ]
  [ "$(gitlore_commit_msg_freshness memory)" = "yes" ]
}

# The last step that can fail: memory's own commit, after the tier commit
# and `add -A` have landed.
@test "a memory commit that fails after composing keeps the approval for the retry" {
  make_parent_with_memory
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  seed_tier_bullet ddaanet shared.md "stale hook"
  seed_root_bullet "ddaanet/shared.md" "fresh hook"
  hook="$(git -C memory rev-parse --absolute-git-dir)/hooks/pre-commit"
  mkdir -p "$(dirname "$hook")"
  # shellcheck disable=SC2016  # $0 is the generated hook's own, not this shell's
  printf '#!/bin/sh\nrm -f "$0"\nexit 1\n' > "$hook"
  chmod +x "$hook"
  msgfile=$(gitlore_commit_msg_file memory)
  printf 'memory: record the shared fact\n' > "$msgfile"
  sleep 1
  head_before=$(git -C memory rev-parse HEAD)
  write_sync_driver

  run --separate-stderr bash "$driver"
  [ "$status" -ne 0 ]
  # The fixture's shape: the tier commit landed and was staged, and memory's
  # commit is the step that failed.
  [ "$(git -C memory rev-parse ":ddaanet")" = "$(git -C memory/ddaanet rev-parse HEAD)" ]
  [ "$(git -C memory rev-parse HEAD)" = "$head_before" ]
  [ ! -e "$hook" ]
  [ "$(gitlore_commit_msg_freshness memory)" = "yes" ]
}

# A tier `live` advance refused as non-fast-forward without the two refs
# having diverged prepares no merge, so it restamps like any other failure.
# No fixture reaches that ancestry right after a commit — only a concurrent
# advance of `live` does — so the classifier is stood in for, over a `live`
# that really refuses the fast-forward.
@test "a tier live advance refused without divergence keeps the approval for the retry" {
  make_parent_with_memory
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  seed_tier_bullet ddaanet shared.md "stale hook"
  seed_root_bullet "ddaanet/shared.md" "fresh hook"
  git -C memory/ddaanet checkout -q --detach
  side=$(git -C memory/ddaanet commit-tree -p HEAD -m side "HEAD^{tree}")
  git -C memory/ddaanet branch -f live "$side"
  msgfile=$(gitlore_commit_msg_file memory)
  printf 'memory: record the shared fact\n' > "$msgfile"
  sleep 1
  write_sync_driver "gitlore_classify_refusal() { printf 'unknown\\n'; }"

  run --separate-stderr bash "$driver"
  [ "$status" -ne 0 ]
  # The fixture's shape: the tier committed, and its `live` was not advanced.
  [ "$(git -C memory/ddaanet rev-parse HEAD^)" = "$(git -C memory rev-parse ":ddaanet")" ]
  [ "$(git -C memory/ddaanet rev-parse live)" = "$side" ]
  [ ! -f "$(gitlore_merge_state_file memory/ddaanet)" ]
  [[ "$stderr" == *"tier 'ddaanet' — HEAD is not at its local 'live'"* ]]
  [ "$(gitlore_commit_msg_freshness memory)" = "yes" ]
}

# The landing record vouches for the commit made on its pin, never for one
# stacked on top of it: a retry whose tier HEAD's parent is not the recorded
# pin leaves the gitlink alone, and the pin guard names the tier ahead.
@test "a landing record does not adopt a foreign commit stacked on the landed one" {
  half_landed_tier_fixture
  pin_before=$(git -C memory rev-parse ":ddaanet")

  run --separate-stderr bash "$CMD" -m "memory: record the shared fact"
  [ "$status" -ne 0 ]
  [ "$(git -C memory/ddaanet rev-parse HEAD^)" = "$pin_before" ]
  rm -f "$lock"

  git -C memory/ddaanet commit -q --allow-empty -m "moved outside /gitlore:merge"
  run --separate-stderr bash "$CMD" -F "$(gitlore_commit_msg_file memory)"
  [ "$status" -ne 0 ]
  [ "$(git -C memory rev-parse ":ddaanet")" = "$pin_before" ]
  [[ "$stderr" == *"ahead of the pin"* ]]
}
