#!/usr/bin/env bats
# $stderr is populated by bats `run --separate-stderr`; shellcheck cannot see it.
# shellcheck disable=SC2154
bats_require_minimum_version 1.5.0

load helpers/setup
load helpers/fixtures
load helpers/tier-fixtures

# The two bullet producers of a compose pass, gitlore_compose_down and
# gitlore_compose_root_bullets, fail when one of their own scratch writes or
# file reads fails, so the pass refuses with its existing message and leaves the
# index as it was. A failure the producer survives with status 0 hands the
# writer a short list, and the index loses lines silently: a scratch file on a
# disk that fills mid-pass, a merged block that cannot be read. Both producers'
# stdout goes to a capturing caller, so an emit alone is not a write that can
# fail; the guards that remain are on file reads and scratch writes.
#
# A failing write is injected by shadowing printf, sed or cat with a function
# that fails one chosen call made directly from the function under test
# (FUNCNAME) and passes every other through, so the fixture and the rest of the
# pass are unaffected. The injected failure says so on stderr, which each test
# asserts, so a green result shows the write it names was the one that failed.
# shellcheck disable=SC1091
source "$PLUGIN_ROOT/scripts/lib/index-compose.sh"

setup()    { setup_tmp_repo; }
teardown() { teardown_tmp_repo; }

# Fail the $3-th call of command $1 made directly from function $2 whose
# arguments, joined by spaces, match glob $4; every other call runs the real
# command.
fail_call() {
  FAIL_CMD="$1" FAIL_IN="$2" FAIL_NTH="$3" FAIL_GLOB="$4" FAIL_SEEN=0
}
injected() {
  [ "${FUNCNAME[2]}" = "$FAIL_IN" ] || return 1
  # shellcheck disable=SC2254  # the glob is the point
  case "$*" in $FAIL_GLOB) ;; *) return 1 ;; esac
  FAIL_SEEN=$((FAIL_SEEN + 1))
  [ "$FAIL_SEEN" -eq "$FAIL_NTH" ] || return 1
  builtin echo "injected $FAIL_CMD failure in $FAIL_IN" >&2
}
# shellcheck disable=SC2059  # a pass-through: the format is the caller's
printf() { [ "${FAIL_CMD-}" = printf ] && injected "$@" && return 1; builtin printf "$@"; }
sed()    { [ "${FAIL_CMD-}" = sed ] && injected "$@" && return 1; command sed "$@"; }
cat()    { [ "${FAIL_CMD-}" = cat ] && injected "$@" && return 1; command cat "$@"; }

# An active tier on its pin whose carrier holds two lines, both mirrored in
# root, committed.
tier_store_with_lines() {
  pinned_store_with_tier
  seed_tier_bullet ddaanet second.md "a second portable fact"
  seed_root_bullet ddaanet/second.md "a second portable fact"
  gitlore_compose memory >/dev/null
  commit_memory_state
  [ "$(grep -c '^- \[' memory/ddaanet/MEMORY.md)" -eq 2 ]
}

# The producer under test failed, and through the injected write.
assert_injected_failure() {
  [ "$status" -ne 0 ]
  [[ "$stderr" == *"injected $1 failure"* ]]
}

# Inside gitlore_compose_down, the tier-relative path second.md is appended to
# root.paths, carrier.paths, head.paths and head.kept, in that order, and its
# bullet to root.bullets, then carrier.bullets.
@test "compose_down fails when a root.paths append fails" {
  tier_store_with_lines
  fail_call printf gitlore_compose_down 1 '* second.md'
  run --separate-stderr gitlore_compose_down memory ddaanet
  assert_injected_failure printf
}

@test "compose_down fails when a root.bullets append fails" {
  tier_store_with_lines
  fail_call printf gitlore_compose_down 1 '*](second.md)*'
  run --separate-stderr gitlore_compose_down memory ddaanet
  assert_injected_failure printf
}

@test "compose_down fails when a carrier.paths append fails" {
  tier_store_with_lines
  fail_call printf gitlore_compose_down 2 '* second.md'
  run --separate-stderr gitlore_compose_down memory ddaanet
  assert_injected_failure printf
}

@test "compose_down fails when a carrier.bullets append fails" {
  tier_store_with_lines
  fail_call printf gitlore_compose_down 2 '*](second.md)*'
  run --separate-stderr gitlore_compose_down memory ddaanet
  assert_injected_failure printf
}

@test "compose_down fails when a head.paths append fails" {
  tier_store_with_lines
  fail_call printf gitlore_compose_down 3 '* second.md'
  run --separate-stderr gitlore_compose_down memory ddaanet
  assert_injected_failure printf
}

@test "compose_down fails when a head.kept append fails" {
  tier_store_with_lines
  fail_call printf gitlore_compose_down 4 '* second.md'
  run --separate-stderr gitlore_compose_down memory ddaanet
  assert_injected_failure printf
}

# Bullets are read back in order, shared.md then second.md, each by one sed of
# the scratch file.
@test "compose_down fails when reading a bullet from its scratch file fails" {
  tier_store_with_lines
  fail_call sed gitlore_compose_down 2 '*root.bullets'
  run --separate-stderr gitlore_compose_down memory ddaanet
  assert_injected_failure sed
}

@test "lock-in: compose_down with no failing write prints both lines" {
  tier_store_with_lines
  run gitlore_compose_down memory ddaanet
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 2 ]
}

@test "a pass whose down projection fails an append leaves the carrier untouched with the existing refusal" {
  tier_store_with_lines
  cp memory/ddaanet/MEMORY.md "$BATS_TEST_TMPDIR/tier.before"
  fail_call printf gitlore_compose_down 1 '* second.md'
  run --separate-stderr gitlore_compose memory
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"injected printf failure"* ]]
  [[ "$output" == *"could not compose memory/ddaanet/MEMORY.md; it was left untouched"* ]]
  command cmp "$BATS_TEST_TMPDIR/tier.before" memory/ddaanet/MEMORY.md
}

# The merged block gitlore_compose_merge_tiers lists is gone when it is read.
@test "root_bullets fails when a merged tier block cannot be read" {
  tier_store_with_lines
  mkdir "$BATS_TEST_TMPDIR/merged"
  builtin printf 'ddaanet\n' > "$BATS_TEST_TMPDIR/merged/tiers"
  run --separate-stderr gitlore_compose_root_bullets memory "$BATS_TEST_TMPDIR/merged"
  [ "$status" -ne 0 ]
}

# The producer's failure, whatever its cause, reaches the pass as the existing
# refusal.
@test "a pass whose root producer fails leaves root untouched with the existing refusal" {
  tier_store_with_lines
  cp memory/MEMORY.md "$BATS_TEST_TMPDIR/root.before"
  gitlore_compose_root_bullets() { return 1; }
  run gitlore_compose memory
  [ "$status" -eq 2 ]
  [[ "$output" == *"could not compose memory/MEMORY.md; it was left untouched"* ]]
  command cmp "$BATS_TEST_TMPDIR/root.before" memory/MEMORY.md
}

@test "lock-in: root_bullets adopts every carrier line" {
  make_parent_with_memory
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  seed_tier_bullet ddaanet shared.md "a portable fact"
  seed_tier_bullet ddaanet second.md "a second portable fact"
  run gitlore_compose_root_bullets memory
  [ "$status" -eq 0 ]
  [[ "$output" == *"](ddaanet/shared.md)"* ]]
  [[ "$output" == *"](ddaanet/second.md)"* ]]
}

