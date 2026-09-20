#!/usr/bin/env bats
bats_require_minimum_version 1.5.0

load helpers/setup
load helpers/fixtures
load helpers/tier-fixtures
load helpers/index-compose

# Header as in tests/index_compose.bats. Covers adoption: the up projection
# a landed merge runs.
# shellcheck disable=SC1091
source "$PLUGIN_ROOT/scripts/lib/index-compose.sh"

setup()    { setup_tmp_repo; }
teardown() { teardown_tmp_repo; }

# --- adoption: the up projection a landed merge runs ---
#
# Taking an upstream commit is a merge, and the merged carrier is what the user
# approved. Adoption is how it reaches the root index — the only surface CC
# recalls from — and it is the one moment the carrier outranks root's text.

@test "adoption replaces the root's tier block with the merged carrier" {
  make_parent_with_memory
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  seed_tier_bullet ddaanet existing.md "already here"
  gitlore_compose memory
  commit_memory_state
  grep -qF 'ddaanet/existing.md' memory/MEMORY.md

  # What a landed merge leaves in the carrier: one fact retracted upstream, one
  # added, one rewritten — against a root index that still says the old thing.
  set_bullets memory/ddaanet/MEMORY.md \
    '- [existing](existing.md) — reworded by the merge' \
    '- [arrived](arrived.md) — new from another repo'
  cp memory/ddaanet/MEMORY.md "$BATS_TEST_TMPDIR/carrier.before"

  run gitlore_compose_up memory ddaanet
  [ "$status" -eq 0 ]
  # The carrier's TEXT wins: root's own wording for the same path is replaced,
  # not preserved as it is in every other pass.
  assert_bullets memory/MEMORY.md \
    '- [existing](ddaanet/existing.md) — reworded by the merge' \
    '- [arrived](ddaanet/arrived.md) — new from another repo'
  # And the carrier is not written at all: a merge approves one store's content,
  # so nothing propagates into a store nobody reviewed. Byte equality, not the
  # absence of a prefix — a write that reflowed or reordered the carrier without
  # adding one is just as much a write.
  cmp -s memory/ddaanet/MEMORY.md "$BATS_TEST_TMPDIR/carrier.before"
}

@test "adoption drops a root line the merged carrier retracted" {
  make_parent_with_memory
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  seed_tier_bullet ddaanet kept.md "survives the merge"
  seed_tier_bullet ddaanet retracted.md "here until upstream drops it"
  gitlore_compose memory
  commit_memory_state
  grep -qF 'ddaanet/retracted.md' memory/MEMORY.md

  # The merge landed a carrier from which another consumer removed the fact.
  sed -i.bak '/retracted\.md/d' memory/ddaanet/MEMORY.md && rm -f memory/ddaanet/MEMORY.md.bak
  rm -f memory/ddaanet/retracted.md

  run gitlore_compose_up memory ddaanet
  [ "$status" -eq 0 ]
  run ! grep -qF 'retracted.md' memory/MEMORY.md
  grep -qF 'ddaanet/kept.md' memory/MEMORY.md
  # No dangling remnant, and the project's own lines are untouched.
  run gitlore_compose_dangling memory
  [ -z "$output" ]
}

@test "adoption leaves other tiers and the project's lines where they are" {
  make_parent_with_memory
  make_tier_in_memory ddaanet
  make_tier_in_memory lore
  set_tier_manifest ddaanet lore
  seed_tier_bullet ddaanet d.md "dd fact"
  seed_tier_bullet lore l.md "lore fact"
  seed_root_bullet "project_overview.md" "the project"
  gitlore_compose memory
  commit_memory_state

  set_bullets memory/ddaanet/MEMORY.md '- [d](d.md) — merged wording'
  run gitlore_compose_up memory ddaanet
  [ "$status" -eq 0 ]
  grep -qF -- '- [d](ddaanet/d.md) — merged wording' memory/MEMORY.md
  grep -qF -- '- [l](lore/l.md) — lore fact' memory/MEMORY.md
  grep -qF -- '- [project_overview](project_overview.md) — the project' memory/MEMORY.md
  # Manifest order still holds, and project lines stay last.
  d=$(grep -n 'ddaanet/d.md' memory/MEMORY.md | cut -d: -f1)
  l=$(grep -n 'lore/l.md' memory/MEMORY.md | cut -d: -f1)
  p=$(grep -n 'project_overview.md' memory/MEMORY.md | cut -d: -f1)
  [ "$d" -lt "$l" ]
  [ "$l" -lt "$p" ]
}

@test "a tier activated after its mount takes its carrier's lines into the root" {
  # Deactivate/reactivate round-trips through the same path a mount uses: root
  # holds no line for the tier, so it has no opinion to defend and adopts.
  make_parent_with_memory
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  seed_tier_bullet ddaanet shared.md "a portable fact"
  gitlore_compose memory
  commit_memory_state
  grep -qF 'ddaanet/shared.md' memory/MEMORY.md

  set_tier_manifest                       # dormant
  gitlore_compose memory
  run ! grep -qF 'ddaanet/shared.md' memory/MEMORY.md

  set_tier_manifest ddaanet               # active again
  run gitlore_compose memory
  [ "$status" -eq 0 ]
  grep -qF -- '- [shared](ddaanet/shared.md) — a portable fact' memory/MEMORY.md
}

@test "manifest order is tier block order" {
  make_parent_with_memory
  make_tier_in_memory ddaanet
  make_tier_in_memory lore
  set_tier_manifest lore ddaanet
  seed_tier_bullet ddaanet d.md "dd fact"
  seed_tier_bullet lore l.md "lore fact"
  gitlore_compose memory
  l=$(grep -n 'lore/l.md' memory/MEMORY.md | cut -d: -f1)
  d=$(grep -n 'ddaanet/d.md' memory/MEMORY.md | cut -d: -f1)
  [ "$l" -lt "$d" ]
}

@test "a dormant mounted tier is dropped from the root but keeps its carrier lines" {
  make_parent_with_memory
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  seed_tier_bullet ddaanet shared.md "a portable fact"
  gitlore_compose memory
  grep -qF 'ddaanet/shared.md' memory/MEMORY.md
  set_tier_manifest                       # deactivate
  run gitlore_compose memory
  [ "$status" -eq 0 ]
  run ! grep -qF 'ddaanet/shared.md' memory/MEMORY.md
  grep -qF -- '- [shared](shared.md) — a portable fact' memory/ddaanet/MEMORY.md
}

@test "a dormant tier's carrier survives two consecutive passes untouched" {
  # Root holds no line for a dormant tier, so it has no authority over that
  # tier's carrier and the down projection skips it entirely. Under the previous
  # model the second pass was the one that bit: the reconciliation base recorded
  # a carrier holding lines the root splice had already stripped, and read them
  # as deletions.
  make_parent_with_memory
  make_tier_in_memory ddaanet
  set_tier_manifest                       # mounted, never active
  seed_tier_bullet ddaanet sleeping.md "still here"
  cp memory/ddaanet/MEMORY.md "$BATS_TEST_TMPDIR/carrier.before"

  gitlore_compose memory
  run gitlore_compose memory
  [ "$status" -eq 0 ]
  cmp -s memory/ddaanet/MEMORY.md "$BATS_TEST_TMPDIR/carrier.before"
  grep -qF -- '- [sleeping](sleeping.md) — still here' memory/ddaanet/MEMORY.md
  run ! grep -qF 'ddaanet/sleeping.md' memory/MEMORY.md
}

@test "preamble and trailer are preserved verbatim" {
  make_parent_with_memory
  printf '# Memory Index\n\n- [A](a.md) — x\n\n<!-- footer -->\n' > memory/MEMORY.md
  run gitlore_compose memory
  [ "$status" -eq 0 ]
  head -1 memory/MEMORY.md | grep -qF '# Memory Index'
  tail -1 memory/MEMORY.md | grep -qF '<!-- footer -->'
}

@test "a bulletless unterminated index does not weld its preamble onto a bullet" {
  # All-preamble is the day-one state of a freshly seeded carrier, and the
  # preamble is emitted verbatim — so an index that arrived unterminated puts the
  # first composed bullet on the end of its last line. A glued line does not
  # parse as a bullet, so the pointer is lost on WRITE, the same fact the
  # unguarded reads lost on read.
  printf '# Tier index' > idx.md
  printf -- '- [A](a.md) — x\n' | gitlore_compose_write idx.md
  assert_bullets idx.md '- [A](a.md) — x'
  head -1 idx.md | grep -qxF '# Tier index'
}

@test "a bulletless unterminated index with nothing to write is left alone" {
  # The separator is a separator, not normalisation: with no bullets there is
  # nothing to separate, and rewriting the file would be churn on a store gitlore
  # was not asked to touch.
  printf '# Tier index' > idx.md
  run gitlore_compose_write idx.md < /dev/null
  [ "$status" -eq 0 ]
  [ -z "$output" ]                        # no "composed" line: nothing written
  [ "$(cat idx.md)" = "# Tier index" ]
  [ "$(tail -c 1 idx.md | wc -l | tr -d ' ')" = 0 ]
}

@test "project bullets keep their order and are never rewritten" {
  make_parent_with_memory
  printf '# Memory Index\n\n- [C](c.md) — three\n- [A](a.md) — one\n- [B](b.md) — two\n' > memory/MEMORY.md
  gitlore_compose memory
  run gitlore_index_part memory/MEMORY.md bullets
  [ "$output" = "$(printf -- '- [C](c.md) — three\n- [A](a.md) — one\n- [B](b.md) — two')" ]
}

