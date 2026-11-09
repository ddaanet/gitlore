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

# A commit that lands a tier and then fails on memory leaves the tier one commit
# ahead of the gitlink memory's index records — the shape a killed take leaves.
# The retry meets the commit's pin guard (gitlore_sync_memory_to_live), which
# refuses the state naming the take and records nothing: the tier keeps its
# landed commit, memory keeps its HEAD. The take (scripts/merge-memory.sh, what
# /gitlore:merge runs) composes the tier's lines up and records the gitlink —
# staged, under D43, since the half-landed store is dirty — and the commit
# retried once more completes with the tier recorded at the landed commit.

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

# The first attempt: the tier commit lands, memory's `add -A` meets the lock.
# Sets $pin_before and $landed; asserts the fixture's shape rather than assuming
# it.
first_attempt_half_lands() {
  pin_before=$(git -C memory rev-parse ":ddaanet")
  memory_before=$(git -C memory rev-parse HEAD)
  run --separate-stderr commit_sections "memory: record the shared fact"
  [ "$status" -ne 0 ]
  [ -f "$lock" ]
  landed=$(git -C memory/ddaanet rev-parse HEAD)
  [ "$landed" != "$pin_before" ]
  [ "$(git -C memory/ddaanet rev-parse HEAD^)" = "$pin_before" ]
  [ "$(git -C memory rev-parse ":ddaanet")" = "$pin_before" ]
  rm -f "$lock"
}

# The retry, refused by the pin guard: nothing rewinds, nothing is recorded.
retry_is_refused() {
  run --separate-stderr commit_sections "memory: record the shared fact"
  [ "$status" -ne 0 ] || { printf 'the retry went through; HEAD records the tier at %s\n' \
    "$(git -C memory rev-parse HEAD:ddaanet)" >&2; false; }
  assert_commit_refused_ahead ddaanet "$landed" "$pin_before"
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$landed" ] \
    || { printf 'the retry moved the tier to %s, expected it to stay at %s\n' \
           "$(git -C memory/ddaanet rev-parse HEAD)" "$landed" >&2; false; }
  [ "$(git -C memory rev-parse HEAD)" = "$memory_before" ]
  [ "$(git -C memory rev-parse ":ddaanet")" = "$pin_before" ]
  git -C memory/ddaanet show HEAD:MEMORY.md > "$BATS_TEST_TMPDIR/carrier.md"
  assert_bullets "$BATS_TEST_TMPDIR/carrier.md" \
    '- [shared](shared.md) — fresh hook'
}

# The take over the half-landed store: the root is dirty (the fixture's composed
# index and manifest are uncommitted), so the moved gitlink and the recomposed
# root index are staged for the next memory commit (D43), not committed. Root
# already carries the line the tier landed, and keeps it.
take_records_the_tier() {
  run --separate-stderr bash "$PLUGIN_ROOT/scripts/merge-memory.sh"
  [ "$status" -eq 0 ] || { printf 'the take failed:\n%s\n%s\n' "$output" "$stderr" >&2; false; }
  [[ "$output" == *"staged rather than committed"* ]] \
    || { printf 'the take did not report the staged gitlink:\n%s\n' "$output" >&2; false; }
  [ "$(git -C memory rev-parse ":ddaanet")" = "$landed" ] \
    || { printf 'the take left the staged gitlink at %s, not the landed %s\n' \
           "$(git -C memory rev-parse ":ddaanet")" "$landed" >&2; false; }
  [ "$(git -C memory rev-parse HEAD:ddaanet)" = "$pin_before" ]
  [ "$(git -C memory rev-parse HEAD)" = "$memory_before" ]
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$landed" ]
  git -C memory diff --cached --name-only | grep -Fqx -- ddaanet
  assert_bullets memory/MEMORY.md \
    '- [shared](ddaanet/shared.md) — fresh hook'
}

# The commit after the take completes: the tier is recorded at the landed
# commit, memory's HEAD moves, the store is clean.
commit_after_take_completes() {
  run --separate-stderr commit_sections "memory: record the shared fact"
  [ "$status" -eq 0 ] || { printf 'the commit after the take failed:\n%s\n' "$stderr" >&2; false; }
  [ "$(git -C memory rev-parse HEAD)" != "$memory_before" ]
  [ "$(git -C memory rev-parse HEAD:ddaanet)" = "$landed" ]
  [ "$(git -C memory log -1 --pretty=%s)" = "memory: record the shared fact" ]
  git -C memory show HEAD:MEMORY.md > "$BATS_TEST_TMPDIR/root.md"
  assert_bullets "$BATS_TEST_TMPDIR/root.md" \
    '- [shared](ddaanet/shared.md) — fresh hook'
  [ -z "$(git -C memory status --porcelain)" ]
}

@test "a commit that landed a tier and then failed on memory's index is refused on retry naming the take, and completes after it" {
  # Fails under a retry that records the tier's HEAD through `add -A` (the
  # killed-take shape committed in silence), under one that rewinds the tier
  # onto its pin (losing the landed carrier line), or under a take that leaves
  # the tier unrecorded so the commit after it is refused again.
  half_landed_tier_fixture
  first_attempt_half_lands
  retry_is_refused
  take_records_the_tier
  commit_after_take_completes
}

# The same chain under a project path holding a space, which the suite otherwise
# reaches only when the ambient TMPDIR holds one: the pin guard, the take and
# the commit each walk the tier path.
@test "a half-landed tier commit is refused, taken and completed under a project path holding a space" {
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
  retry_is_refused
  take_records_the_tier
  commit_after_take_completes
}
