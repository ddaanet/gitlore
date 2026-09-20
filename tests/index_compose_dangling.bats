#!/usr/bin/env bats

load helpers/setup
load helpers/fixtures
load helpers/tier-fixtures

# Header as in tests/index_compose.bats. Covers dangling pointers, cap_list,
# failed writes, and problem attribution.
# shellcheck disable=SC1091
source "$PLUGIN_ROOT/scripts/lib/index-compose.sh"

setup()    { setup_tmp_repo; }
teardown() { teardown_tmp_repo; }

@test "dangling reports a root bullet whose file is absent" {
  make_parent_with_memory
  seed_root_bullet "gone.md" "the fact that got away"
  run gitlore_compose_dangling memory
  [ "$status" -eq 0 ]
  [[ "$output" == *"gone.md"* ]]
  [[ "$output" == *"memory/MEMORY.md"* ]]
  # The phrase every "compose said nothing about dangling" negative refutes,
  # pinned here so a rewording of the report turns this red instead of leaving
  # them watching a string nothing emits.
  [[ "$output" == *"$GITLORE_T_DANGLING"* ]]
}

@test "dangling is silent when every pointer resolves" {
  make_parent_with_memory
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  seed_tier_bullet ddaanet shared.md "a portable fact"
  seed_root_bullet "here.md" "present"
  printf 'body\n' > memory/here.md
  gitlore_compose memory
  run gitlore_compose_dangling memory
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "dangling resolves a tier-prefixed root path inside the tier" {
  make_parent_with_memory
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  seed_tier_bullet ddaanet shared.md "a portable fact"
  gitlore_compose memory                    # splices ddaanet/shared.md into the root
  run gitlore_compose_dangling memory
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "dangling reports each missing target once, not once per index" {
  make_parent_with_memory
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  # A file-only deletion: the shared carrier still advertises the fact (line
  # kept), only the local file copy is gone. The carrier line keeps it alive in
  # both indexes — unlike a retracted fact, whose carrier line is also gone and
  # which compose drops. So it is a genuine both-indexes dangling: report once.
  seed_tier_bullet ddaanet vanished.md "a portable fact"
  rm memory/ddaanet/vanished.md
  gitlore_compose memory                    # splices the surviving line up into the root
  grep -qF 'ddaanet/vanished.md' memory/MEMORY.md
  run gitlore_compose_dangling memory
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -c 'vanished.md')" -eq 1 ]
}

@test "dangling inspects a dormant tier's carrier, which the root never shows" {
  make_parent_with_memory
  make_tier_in_memory ddaanet
  set_tier_manifest                         # mounted, never active
  printf -- '- [orphan](orphan.md) — no such file\n' >> memory/ddaanet/MEMORY.md
  run gitlore_compose_dangling memory
  [ "$status" -eq 0 ]
  [[ "$output" == *"orphan.md"* ]]
  [[ "$output" == *"memory/ddaanet/MEMORY.md"* ]]
}

@test "a dangling pointer reports but never refuses: compose still writes" {
  make_parent_with_memory
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  seed_tier_bullet ddaanet shared.md "a portable fact"
  seed_root_bullet "gone.md" "stale line"
  run gitlore_compose memory
  [ "$status" -eq 0 ]
  grep -qF 'ddaanet/shared.md' memory/MEMORY.md
  # The stale line survives: an index edit is the agent's, never the hook's.
  grep -qF -- '- [gone](gone.md) — stale line' memory/MEMORY.md
  # And compose's own report stays a list of what it WROTE.
  [[ "$output" != *"$GITLORE_T_DANGLING"* ]]
}

@test "cap_list passes a list at or under the cap through unchanged" {
  run bash -c 'source "$1"; printf "a\nb\nc\n" | gitlore_cap_list' _ "$PLUGIN_ROOT/scripts/lib/index-compose.sh"
  [ "$status" -eq 0 ]
  [ "$output" = "a
b
c" ]
}

@test "cap_list truncates past the cap and counts the remainder in one summary" {
  run bash -c 'source "$1"; printf "l%s\n" 1 2 3 4 5 6 7 | gitlore_cap_list' _ "$PLUGIN_ROOT/scripts/lib/index-compose.sh"
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -c '^l')" -eq 5 ]
  [[ "$output" == *"… and 2 more"* ]]
}

@test "cap_list ignores blank lines when counting and printing" {
  run bash -c 'source "$1"; printf "a\n\nb\n\n" | gitlore_cap_list' _ "$PLUGIN_ROOT/scripts/lib/index-compose.sh"
  [ "$status" -eq 0 ]
  [ "$output" = "a
b" ]
}

@test "a failed index write is reported, not reported as success" {
  # The writes run inside a command substitution feeding a string append, and
  # every caller invokes gitlore_compose as an `if` condition — which disables
  # errexit for the whole call. Without an explicit status check a failed write
  # left the index unchanged and the hook said "recomposed".
  make_parent_with_memory
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  seed_root_bullet "ddaanet/shared.md" "a portable fact"
  # No write permission on the carrier's directory: gitlore_compose_write's temp
  # file lands in the tier's own gitdir, not here, but the `mv` into this
  # directory still needs write access to create the destination entry, so
  # that `mv` is what fails.
  chmod a-w memory/ddaanet
  run gitlore_compose memory
  chmod u+w memory/ddaanet
  [ "$status" -eq 2 ]
  [[ "$output" == *"could not write memory/ddaanet/MEMORY.md"* ]]
}

@test "problem attribution matches the exact file prefix" {
  # A space in the mempath, a tier name that is a prefix of another and a
  # longer path ending in the queried one all defeat a naive matcher: a regex
  # would read "." as any char, unquoted word splitting would break on the
  # space, and an unanchored match would take the longer path.
  input=$(printf '%s\n' \
    "my mem.d/MEMORY.md: duplicate pointer path dup.md" \
    "my mem.d/a/MEMORY.md: duplicate pointer path other.md" \
    "my mem.d/ab/MEMORY.md: duplicate pointer path third.md" \
    "my memXd/MEMORY.md: duplicate pointer path decoy.md" \
    "nested/my mem.d/MEMORY.md: duplicate pointer path suffix.md" \
    "root index line 'gone/x.md' has a prefix naming no mounted tier — it is a leftover from a removed tier and must be fixed by hand")

  run gitlore_compose_problems_in "my mem.d/a/MEMORY.md" <<< "$input"
  [ "$status" -eq 0 ]
  [ "$output" = "my mem.d/a/MEMORY.md: duplicate pointer path other.md" ]

  run gitlore_compose_problems_in "my mem.d/MEMORY.md" <<< "$input"
  [ "$status" -eq 0 ]
  [ "$output" = "my mem.d/MEMORY.md: duplicate pointer path dup.md" ]

  run gitlore_compose_problems_in "my mem.d/b/MEMORY.md" <<< "$input"
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}

@test "a failing check writes nothing at all" {
  make_parent_with_memory
  make_tier_in_memory ddaanet
  set_tier_manifest ghost
  seed_tier_bullet ddaanet shared.md "a portable fact"
  cp memory/MEMORY.md "$BATS_TEST_TMPDIR/root.before"
  cp memory/ddaanet/MEMORY.md "$BATS_TEST_TMPDIR/tier.before"
  run gitlore_compose memory
  [ "$status" -eq 1 ]
  [[ "$output" == *"ghost"* ]]
  cmp -s memory/MEMORY.md "$BATS_TEST_TMPDIR/root.before"
  cmp -s memory/ddaanet/MEMORY.md "$BATS_TEST_TMPDIR/tier.before"
}

