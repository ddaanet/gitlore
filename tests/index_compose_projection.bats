#!/usr/bin/env bats
bats_require_minimum_version 1.5.0

load helpers/setup
load helpers/fixtures
load helpers/tier-fixtures
load helpers/index-compose

# Header as in tests/index_compose.bats. Covers splice-up/mirror-down
# projection, bullet ordering, and unterminated indexes.
# shellcheck disable=SC1091
source "$PLUGIN_ROOT/scripts/lib/index-compose.sh"

setup()    { setup_tmp_repo; }
teardown() { teardown_tmp_repo; }

@test "splice up: an active tier's carrier bullets appear prefixed in the root" {
  make_parent_with_memory
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  seed_tier_bullet ddaanet shared.md "a portable fact"
  seed_root_bullet "project_overview.md" "the project"
  run gitlore_compose memory
  [ "$status" -eq 0 ]
  grep -qF -- '- [shared](ddaanet/shared.md) — a portable fact' memory/MEMORY.md
  # Tier block precedes project lines.
  tierline=$(grep -n 'ddaanet/shared.md' memory/MEMORY.md | cut -d: -f1)
  projline=$(grep -n 'project_overview.md' memory/MEMORY.md | cut -d: -f1)
  [ "$tierline" -lt "$projline" ]
}

@test "mirror down: a root-authored tier line lands in the carrier, unprefixed" {
  make_parent_with_memory
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  # No prior compose, so the base is empty: a root-authored line the carrier
  # lacks is a fresh add and mirrors down.
  seed_root_bullet "ddaanet/new_fact.md" "authored in the root"
  run gitlore_compose memory
  [ "$status" -eq 0 ]
  # Exactly the one line, unprefixed. The prefix stripping is what the block
  # equality pins: a prefixed twin alongside it fails the same assertion the
  # missing line does.
  assert_bullets memory/ddaanet/MEMORY.md \
    '- [new_fact](new_fact.md) — authored in the root'
}

# --- ordering ---
#
# The root index is the surface the agent edits, so the order it states there is
# an authored choice and mirror-down carries it into the carrier. A carrier-only
# arrival still lands where the carrier put it: the base makes that a positional
# merge, not an append.


@test "mirror down carries the root's order into the carrier" {
  make_parent_with_memory
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  seed_tier_bullet ddaanet one.md "first"
  seed_tier_bullet ddaanet two.md "second"
  gitlore_compose memory                    # base recorded: one, two

  # The agent reorders the tier block in the root index — the only index it edits.
  set_bullets memory/MEMORY.md \
    '- [two](ddaanet/two.md) — second' \
    '- [one](ddaanet/one.md) — first'

  run gitlore_compose memory
  [ "$status" -eq 0 ]
  twoline=$(grep -n '](two.md)' memory/ddaanet/MEMORY.md | cut -d: -f1)
  oneline=$(grep -n '](one.md)' memory/ddaanet/MEMORY.md | cut -d: -f1)
  [ "$twoline" -lt "$oneline" ]
  # And splice-up reproduces it, so the reorder is stable rather than undone.
  rtwo=$(grep -n 'ddaanet/two.md' memory/MEMORY.md | cut -d: -f1)
  rone=$(grep -n 'ddaanet/one.md' memory/MEMORY.md | cut -d: -f1)
  [ "$rtwo" -lt "$rone" ]
}

@test "a kept carrier-only line stays at its own offset, not at the end" {
  make_parent_with_memory
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  seed_tier_bullet ddaanet a.md "first"
  seed_tier_bullet ddaanet c.md "last"
  gitlore_compose memory                    # root adopts the carrier: a, c
  commit_memory_state

  # A line written straight into the carrier, between the two root knows about.
  # Root never carried it, so the projection keeps it — where the carrier put it.
  set_bullets memory/ddaanet/MEMORY.md \
    '- [a](a.md) — first' \
    '- [b](b.md) — written into the carrier' \
    '- [c](c.md) — last'

  run gitlore_compose memory
  [ "$status" -eq 0 ]
  la=$(grep -n '](a.md)' memory/ddaanet/MEMORY.md | cut -d: -f1)
  lb=$(grep -n '](b.md)' memory/ddaanet/MEMORY.md | cut -d: -f1)
  lc=$(grep -n '](c.md)' memory/ddaanet/MEMORY.md | cut -d: -f1)
  [ "$la" -lt "$lb" ]
  [ "$lb" -lt "$lc" ]
}

@test "a carrier line the root never carried is kept and reported" {
  make_parent_with_memory
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  seed_tier_bullet ddaanet known.md "root knows this one"
  gitlore_compose memory                    # root adopts it
  commit_memory_state
  seed_tier_bullet ddaanet stray.md "nobody authored this in the root"

  run gitlore_compose memory
  [ "$status" -eq 0 ]
  # Kept: absent from root at HEAD, so it is not a deletion — and destroying it
  # over an ambiguity is the one thing the pass must not do.
  grep -qF -- '- [stray](stray.md) — nobody authored this in the root' memory/ddaanet/MEMORY.md
  # Not spliced into the root either: root has a block for this tier and did not
  # ask for this line.
  run ! grep -qF 'ddaanet/stray.md' memory/MEMORY.md
  # And named, so it is not silently stranded out of recall.
  run gitlore_compose_orphans memory
  [ "$status" -eq 0 ]
  [[ "$output" == *"stray.md is in the tier but not in the root index"* ]]
  [[ "$output" != *"known.md"* ]]
}

# --- indexes whose last line carries no newline ---
#
# gitlore_compose_write always terminates what it writes, so an unterminated
# index is never gitlore's own output — it arrives by hand edit, by an agent
# `Edit`, or from another consumer's writer, and the store travels that way. An
# unguarded `read` fills $line and *then* returns non-zero at EOF, so the last
# line is read and thrown away: it drops out of every path list built that way,
# and the order merge reads its absence on one side as that side deleting it.

@test "an unterminated carrier keeps its last line through a compose" {
  make_parent_with_memory
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  seed_tier_bullet ddaanet alpha.md "a"
  seed_tier_bullet ddaanet beta.md "b"
  seed_tier_bullet ddaanet gamma.md "g"
  gitlore_compose memory                    # root adopts the carrier's three
  commit_memory_state
  unterminate_index memory/ddaanet/MEMORY.md

  run gitlore_compose memory
  [ "$status" -eq 0 ]
  assert_bullets memory/ddaanet/MEMORY.md \
    '- [alpha](alpha.md) — a' \
    '- [beta](beta.md) — b' \
    '- [gamma](gamma.md) — g'
  # Root is the terminated side here, so it keeps the line either way — assert it
  # to pin which surface the loss lands on, the asymmetry that let this run
  # undetected in a real store.
  assert_bullets memory/MEMORY.md \
    '- [alpha](ddaanet/alpha.md) — a' \
    '- [beta](ddaanet/beta.md) — b' \
    '- [gamma](ddaanet/gamma.md) — g'
}

@test "both indexes unterminated: neither loses its last line" {
  make_parent_with_memory
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  seed_tier_bullet ddaanet alpha.md "a"
  seed_tier_bullet ddaanet beta.md "b"
  seed_tier_bullet ddaanet gamma.md "g"
  gitlore_compose memory
  commit_memory_state
  unterminate_index memory/ddaanet/MEMORY.md
  unterminate_index memory/MEMORY.md

  run gitlore_compose memory
  [ "$status" -eq 0 ]
  # Both surfaces drop it in one pass, which leaves the fact with no pointer
  # anywhere while the file itself is still on disk.
  assert_bullets memory/ddaanet/MEMORY.md \
    '- [alpha](alpha.md) — a' \
    '- [beta](beta.md) — b' \
    '- [gamma](gamma.md) — g'
  assert_bullets memory/MEMORY.md \
    '- [alpha](ddaanet/alpha.md) — a' \
    '- [beta](ddaanet/beta.md) — b' \
    '- [gamma](ddaanet/gamma.md) — g'
}

@test "an unterminated root index still reports its last bullet as dangling" {
  make_parent_with_memory
  seed_root_bullet "gone.md" "the file was removed"
  unterminate_index memory/MEMORY.md
  run gitlore_compose_dangling memory
  [ "$status" -eq 0 ]
  [[ "$output" == *"gone.md names no file in the memory store"* ]]
}

@test "compose is byte-idempotent" {
  make_parent_with_memory
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  seed_tier_bullet ddaanet shared.md "a portable fact"
  seed_root_bullet "ddaanet/other.md" "root authored"
  seed_root_bullet "project_overview.md" "the project"
  gitlore_compose memory
  cp memory/MEMORY.md "$BATS_TEST_TMPDIR/root.1"
  cp memory/ddaanet/MEMORY.md "$BATS_TEST_TMPDIR/tier.1"
  run gitlore_compose memory
  [ "$status" -eq 0 ]
  [ -z "$output" ]                       # nothing changed → nothing reported
  cmp -s memory/MEMORY.md "$BATS_TEST_TMPDIR/root.1"
  cmp -s memory/ddaanet/MEMORY.md "$BATS_TEST_TMPDIR/tier.1"
}

@test "the root's hook text wins over a divergent carrier hook" {
  make_parent_with_memory
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  seed_tier_bullet ddaanet shared.md "stale carrier text"
  seed_root_bullet "ddaanet/shared.md" "fresh curated text"
  run gitlore_compose memory
  [ "$status" -eq 0 ]
  # Replaced, not appended beside: block equality says the carrier holds the
  # root's wording once and the superseded wording not at all.
  assert_bullets memory/ddaanet/MEMORY.md '- [shared](shared.md) — fresh curated text'
  assert_bullets memory/MEMORY.md '- [shared](ddaanet/shared.md) — fresh curated text'
}

@test "removing an active tier's root line drops it from the carrier in one pass" {
  make_parent_with_memory
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  seed_tier_bullet ddaanet keep.md "stays"
  seed_tier_bullet ddaanet drop.md "goes away"
  gitlore_compose memory
  grep -qF 'ddaanet/keep.md' memory/MEMORY.md
  grep -qF 'ddaanet/drop.md' memory/MEMORY.md
  # Commit, so root at HEAD carries both facts: that is what makes the omission
  # below a deletion rather than a line root never had.
  commit_memory_state

  # The agent deletes the fact and edits only the root index, the way the write
  # instructions describe — never touching the carrier by hand. Against the base
  # the root omission reads as a delete (not a fresh carrier add), so it drops.
  sed -i.bak '/ddaanet\/drop\.md/d' memory/MEMORY.md && rm -f memory/MEMORY.md.bak

  run gitlore_compose memory
  [ "$status" -eq 0 ]
  # Both surfaces pinned independently: dropping the fact from one index and
  # leaving it in the other fails exactly one of these two.
  assert_bullets memory/ddaanet/MEMORY.md '- [keep](keep.md) — stays'
  assert_bullets memory/MEMORY.md '- [keep](ddaanet/keep.md) — stays'

  # And it stays gone — no later compose resurrects it from a stale mirror.
  run gitlore_compose memory
  [ "$status" -eq 0 ]
  assert_bullets memory/ddaanet/MEMORY.md '- [keep](keep.md) — stays'
  assert_bullets memory/MEMORY.md '- [keep](ddaanet/keep.md) — stays'
}

@test "a root deletion lands even where the carrier added a line beside it" {
  make_parent_with_memory
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  seed_tier_bullet ddaanet a.md "first"
  seed_tier_bullet ddaanet drop.md "goes away"
  seed_tier_bullet ddaanet c.md "last"
  gitlore_compose memory
  commit_memory_state

  # The odd layout the HEAD-base check defends against. Root deletes the fact;
  # the carrier independently gains a line right where it was. The path-list
  # merge sees one hunk carrying a delete and an insert, and its --union
  # resolution keeps BOTH — so the deleted path reaches the pick loop after
  # all, and only the base check still distinguishes it from a carrier-only
  # arrival. Every other deletion fixture is resolved before that check runs.
  sed -i.bak '/ddaanet\/drop\.md/d' memory/MEMORY.md && rm -f memory/MEMORY.md.bak
  set_bullets memory/ddaanet/MEMORY.md \
    '- [a](a.md) — first' \
    '- [drop](drop.md) — goes away' \
    '- [new](new.md) — written into the carrier' \
    '- [c](c.md) — last'

  run gitlore_compose memory
  [ "$status" -eq 0 ]
  # The carrier-only arrival is kept and the root's deletion still lands — the
  # two halves of the same union hunk, decided oppositely.
  assert_bullets memory/ddaanet/MEMORY.md \
    '- [a](a.md) — first' \
    '- [new](new.md) — written into the carrier' \
    '- [c](c.md) — last'
}

