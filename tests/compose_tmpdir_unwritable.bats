#!/usr/bin/env bats
# A compose run whose temp directory cannot be created leaves every index as it
# found it and fails. gitlore_compose_down builds its projection in a scratch
# directory under ${TMPDIR:-/tmp}; when that directory cannot be made, the
# projection is empty and must not be written over the tier's index as if root
# held no lines for the tier. The temp directory is broken for the command under
# test alone, by naming a directory that does not exist, so the fixture setup and
# bats keep a working one and no test depends on /tmp being read-only.
#
# $stderr is populated by bats `run --separate-stderr`; shellcheck cannot see it.
# shellcheck disable=SC2154
bats_require_minimum_version 1.5.0

load helpers/setup
load helpers/fixtures
load helpers/tier-fixtures
load helpers/stub-synth
load helpers/merge-memory
load helpers/commit-memory

# An active tier on its pin whose carrier holds two lines, both mirrored in
# root, committed. Then root gains a line of its own, so a commit has something
# to record.
tier_store_with_lines() {
  pinned_store_with_tier
  seed_tier_bullet ddaanet second.md "a second portable fact"
  seed_root_bullet ddaanet/second.md "a second portable fact"
  gitlore_compose memory >/dev/null
  commit_memory_state
  [ "$(grep -c '^- \[' memory/ddaanet/MEMORY.md)" -ge 2 ]
}

# Copies of both indexes taken before the command under test.
snapshot_indexes() {
  cp memory/ddaanet/MEMORY.md "$BATS_TEST_TMPDIR/tier.before"
  cp memory/MEMORY.md "$BATS_TEST_TMPDIR/root.before"
}

# Both indexes are byte-identical to the snapshot.
assert_indexes_untouched() {
  cmp "$BATS_TEST_TMPDIR/tier.before" memory/ddaanet/MEMORY.md
  cmp "$BATS_TEST_TMPDIR/root.before" memory/MEMORY.md
}

@test "a compose with an unusable temp directory fails and leaves the tier index and root index byte-identical" {
  tier_store_with_lines
  snapshot_indexes
  run --separate-stderr env TMPDIR="$BATS_TEST_TMPDIR/missing" bash "$PLUGIN_ROOT/bin/gitlore-compose"
  [ "$status" -ne 0 ]
  assert_indexes_untouched
}

@test "a compose with an unusable temp directory leaves the tier index and root index byte-identical when root has edited a tier line" {
  tier_store_with_lines
  sed 's/a second portable fact/reworded in root/' memory/MEMORY.md > "$BATS_TEST_TMPDIR/root.edit"
  cp "$BATS_TEST_TMPDIR/root.edit" memory/MEMORY.md
  snapshot_indexes
  run --separate-stderr env TMPDIR="$BATS_TEST_TMPDIR/missing" bash "$PLUGIN_ROOT/bin/gitlore-compose"
  [ "$status" -ne 0 ]
  assert_indexes_untouched
}

@test "lock-in: the commit path with an unusable temp directory aborts and leaves both indexes byte-identical" {
  tier_store_with_lines
  printf -- '---\nname: proj\ndescription: ""\n---\n\nbody\n' > memory/proj.md
  seed_root_bullet proj.md "a project fact"
  snapshot_indexes
  commits=$(git -C memory rev-list --count HEAD)
  summary=$(sectioned_summary "memory: record")
  # shellcheck disable=SC2016  # the inner shell expands its own arguments
  run --separate-stderr bash -c 'printf "%s\n" "$1" | env TMPDIR="$2" bash "$3"' \
    _ "$summary" "$BATS_TEST_TMPDIR/missing" "$CMD"
  [ "$status" -ne 0 ]
  cmp "$BATS_TEST_TMPDIR/tier.before" memory/ddaanet/MEMORY.md
  cmp "$BATS_TEST_TMPDIR/root.before" memory/MEMORY.md
  [ "$(git -C memory rev-list --count HEAD)" = "$commits" ]
}

@test "lock-in: the same store composes with a working temp directory and exits 0 with both indexes unchanged" {
  tier_store_with_lines
  snapshot_indexes
  mkdir "$BATS_TEST_TMPDIR/tmp"
  run --separate-stderr env TMPDIR="$BATS_TEST_TMPDIR/tmp" bash "$PLUGIN_ROOT/bin/gitlore-compose"
  [ "$status" -eq 0 ]
  assert_indexes_untouched
}
