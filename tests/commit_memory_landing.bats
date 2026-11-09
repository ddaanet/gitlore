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

# A commit that lands a tier and then fails on memory's own commit leaves the
# tier's gitlink staged in memory at the landed commit: the commit path
# (gitlore_sync_tiers_to_live) stages each tier as its commit lands, and a staged
# gitlink is root's record of having seen the tier (D78). The retry's pin guard
# (gitlore_sync_memory_to_live) reads that index pin, finds the tier on it, and
# the retry completes with the tier recorded at the landed commit. A hand commit
# on top of the landed one is still ahead of the staged pin and is refused
# naming the take; a take (scripts/merge-memory.sh, what /gitlore:merge runs)
# run between the attempts finds nothing to record and leaves the staging as it
# stands.

# The pin guard's refusal on stderr for tier $1 checked out at $2 over the pin
# $3: its header, the verbatim pin-check line, the take as the remedy, and not
# the pending check's abort, which the guard runs ahead of.
assert_commit_refused_ahead() {
  [[ "$stderr" == *"a tier was moved off the commit the memory store records for it"* ]] \
    || { printf 'no pin-guard header; stderr:\n%s\n' "$stderr" >&2; return 1; }
  [[ "$stderr" == *"tier '$1' is checked out at ${2:0:12}, ahead of the commit the memory store records at ${3:0:12}, so the root index has not taken its lines. Run /gitlore:merge, which composes them into the root index and records the tier."* ]] \
    || { printf 'the refusal does not carry the tier line; stderr:\n%s\n' "$stderr" >&2; return 1; }
  [[ "$stderr" != *"gitlore-compose"* ]]
}

# The first attempt: the tier commit lands and its gitlink is staged, then
# memory's `add -A` is refused. Sets $pin_before, $memory_before and $landed;
# asserts the fixture's shape rather than assuming it.
first_attempt_half_lands() {
  pin_before=$(git -C memory rev-parse ":ddaanet")
  memory_before=$(git -C memory rev-parse HEAD)
  PATH="$refuse_bin:$PATH" run --separate-stderr commit_sections "memory: record the shared fact"
  [ "$status" -ne 0 ]
  [[ "$stderr" == *"$refused_msg"* ]] \
    || { printf 'the first attempt did not die on memory'"'"'s add -A; stderr:\n%s\n' "$stderr" >&2; false; }
  landed=$(git -C memory/ddaanet rev-parse HEAD)
  [ "$landed" != "$pin_before" ]
  [ "$(git -C memory/ddaanet rev-parse HEAD^)" = "$pin_before" ]
  [ "$(git -C memory rev-parse ":ddaanet")" = "$landed" ] \
    || { printf 'the tier landed at %s but the index records %s\n' \
           "$landed" "$(git -C memory rev-parse ":ddaanet")" >&2; false; }
  [ "$(git -C memory rev-parse HEAD:ddaanet)" = "$pin_before" ]
  [ "$(git -C memory rev-parse HEAD)" = "$memory_before" ]
}

# The retry completes: the tier is recorded at the landed commit, memory's HEAD
# moves, the store is clean, and root carries the line the tier landed.
retry_completes() {
  run --separate-stderr commit_sections "memory: record the shared fact"
  [ "$status" -eq 0 ] || { printf 'the retry failed:\n%s\n' "$stderr" >&2; false; }
  [ "$(git -C memory rev-parse HEAD)" != "$memory_before" ]
  [ "$(git -C memory rev-parse HEAD:ddaanet)" = "$landed" ]
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$landed" ]
  [ "$(git -C memory log -1 --pretty=%s)" = "memory: record the shared fact" ]
  git -C memory show HEAD:MEMORY.md > "$BATS_TEST_TMPDIR/root.md"
  assert_bullets "$BATS_TEST_TMPDIR/root.md" \
    '- [shared](ddaanet/shared.md) — fresh hook'
  [ -z "$(git -C memory status --porcelain)" ]
}

@test "a commit that landed a tier and then failed on memory's commit completes on retry, recording the tier at the landed commit" {
  # Fails under a commit path that stages no gitlink as the tier lands (the
  # retry is then refused naming the take), under a retry that rewinds the tier
  # onto its old pin (losing the landed carrier line), and under one that
  # records anything but the landed commit.
  half_landed_tier_fixture
  first_attempt_half_lands
  retry_completes
}

@test "a hand commit on top of the landed tier commit is refused on retry naming the take, and nothing is recorded" {
  # The staged gitlink is the record; a commit made by hand after it is ahead
  # of that record. Fails under a retry that records the tier's HEAD through
  # `add -A`, and under a guard that reads HEAD's gitlink for the pin, whose
  # refusal would name the old pin rather than the landed commit.
  half_landed_tier_fixture
  first_attempt_half_lands
  printf 'more body\n' >> memory/ddaanet/shared.md
  git -C memory/ddaanet add -A
  git -C memory/ddaanet commit -qm "a hand commit on the landed one"
  hand=$(git -C memory/ddaanet rev-parse HEAD)
  [ "$hand" != "$landed" ]

  run --separate-stderr commit_sections "memory: record the shared fact"
  [ "$status" -ne 0 ] || { printf 'the retry went through; HEAD records the tier at %s\n' \
    "$(git -C memory rev-parse HEAD:ddaanet)" >&2; false; }
  assert_commit_refused_ahead ddaanet "$hand" "$landed"
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$hand" ]
  [ "$(git -C memory rev-parse HEAD)" = "$memory_before" ]
  [ "$(git -C memory rev-parse ":ddaanet")" = "$landed" ]
  [ "$(git -C memory rev-parse HEAD:ddaanet)" = "$pin_before" ]
}

@test "a take run between the first attempt and the retry leaves the staged gitlink where it is, and the retry then completes" {
  # The tier sits on its staged pin, so the take has nothing to compose up or
  # record. Fails under a take that re-pins the tier from HEAD's gitlink
  # (rewinding it off the landed commit), under one that commits the dirty
  # root, and under a retry refused after the take.
  half_landed_tier_fixture
  first_attempt_half_lands

  run --separate-stderr bash "$PLUGIN_ROOT/scripts/merge-memory.sh"
  [ "$status" -eq 0 ] || { printf 'the take failed:\n%s\n%s\n' "$output" "$stderr" >&2; false; }
  [ "$(git -C memory rev-parse HEAD)" = "$memory_before" ]
  [ "$(git -C memory rev-parse ":ddaanet")" = "$landed" ] \
    || { printf 'the take moved the staged gitlink to %s, off the landed %s\n' \
           "$(git -C memory rev-parse ":ddaanet")" "$landed" >&2; false; }
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$landed" ]
  git -C memory diff --cached --name-only | grep -Fqx -- ddaanet
  retry_completes
}

# The same chain under a project path holding a space, which the suite otherwise
# reaches only when the ambient TMPDIR holds one: the tier's commit, the gitlink
# staging, the pin guard and the memory commit each walk the tier path.
@test "a half-landed tier commit completes on retry under a project path holding a space" {
  teardown_tmp_repo
  TMP_REPO="$(mktemp -d "${TMPDIR:-/tmp}/gitlore test.XXXXXX")"
  export TMP_REPO
  cd "$TMP_REPO"
  git init -q -b main
  git config user.email "test@example.com"
  git config user.name "Test"
  half_landed_tier_fixture
  [[ "$TMP_REPO" == *" "* ]]
  first_attempt_half_lands
  retry_completes
}
