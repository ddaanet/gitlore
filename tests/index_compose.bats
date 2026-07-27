#!/usr/bin/env bats
bats_require_minimum_version 1.5.0

load helpers/setup
load helpers/fixtures
load helpers/tier-fixtures

# `load helpers/setup` already sources every scripts/lib/*.sh, which is where
# gitlore_tier_paths / gitlore_active_tiers come from. Re-sourcing util.sh here
# would fail on its readonly constants, so only the file under test is named.
# shellcheck disable=SC1091
source "$PLUGIN_ROOT/scripts/lib/index-compose.sh"

setup()    { setup_tmp_repo; }
teardown() { teardown_tmp_repo; }

@test "bullet_path extracts the path from a well-formed bullet" {
  run gitlore_bullet_path '- [Some Title](foo_bar.md) — the hook text'
  [ "$status" -eq 0 ]
  [ "$output" = "foo_bar.md" ]
}

@test "bullet_path handles a prefixed path and a hook containing parens" {
  run gitlore_bullet_path '- [T](ddaanet/x.md) — hook (with parens) — and a dash'
  [ "$output" = "ddaanet/x.md" ]
}

@test "bullet_path rejects a non-bullet and a bullet with no link" {
  run gitlore_bullet_path '# Memory Index'
  [ "$status" -eq 1 ]
  run gitlore_bullet_path '- [just a bracketed phrase] and prose'
  [ "$status" -eq 1 ]
}

@test "bullet_path accepts a bullet with no hook separator" {
  run gitlore_bullet_path '- [T](foo.md)'
  [ "$status" -eq 0 ]
  [ "$output" = "foo.md" ]
}

@test "reprefix and deprefix round-trip, preserving title and hook" {
  line='- [Some Title](foo.md) — hook — with an em dash'
  run gitlore_bullet_reprefix "$line" ddaanet
  [ "$output" = '- [Some Title](ddaanet/foo.md) — hook — with an em dash' ]
  run gitlore_bullet_deprefix "$output" ddaanet
  [ "$output" = "$line" ]
}

@test "deprefix refuses a line that does not carry the prefix" {
  run gitlore_bullet_deprefix '- [T](foo.md) — h' ddaanet
  [ "$status" -eq 1 ]
}

@test "index_region reports the first and last bullet lines" {
  printf '# Head\n\n- [A](a.md) — x\n- [B](b.md) — y\n\nTrailing prose\n' > idx.md
  run gitlore_index_region idx.md
  [ "$output" = "3 4" ]
}

@test "index_region reports 0 0 for a bulletless index" {
  printf -- '---\ndescription: "d"\n---\n\n# Tier\n' > idx.md
  run gitlore_index_region idx.md
  [ "$output" = "0 0" ]
}

@test "index_part splits preamble, bullets and trailer" {
  printf '# Head\n\n- [A](a.md) — x\n- [B](b.md) — y\n\nTrailing prose\n' > idx.md
  run gitlore_index_part idx.md preamble
  [ "$output" = "$(printf '# Head\n')" ]
  run gitlore_index_part idx.md bullets
  [ "$output" = "$(printf -- '- [A](a.md) — x\n- [B](b.md) — y')" ]
  run gitlore_index_part idx.md trailer
  [ "$output" = "$(printf '\nTrailing prose')" ]
}

@test "index_part of a bulletless index is all preamble" {
  printf -- '---\ndescription: "d"\n---\n\n# Tier\n' > idx.md
  run gitlore_index_part idx.md bullets
  [ -z "$output" ]
  run gitlore_index_part idx.md trailer
  [ -z "$output" ]
  run gitlore_index_part idx.md preamble
  [[ "$output" == *"# Tier"* ]]
}

@test "tier_of attributes a prefixed path to a mounted tier" {
  tiers=$(printf 'ddaanet\nlore\n')
  run gitlore_tier_of "ddaanet/x.md" "$tiers"
  [ "$status" -eq 0 ]
  [ "$output" = "ddaanet" ]
}

@test "tier_of rejects a bare path and an unknown prefix" {
  tiers=$(printf 'ddaanet\n')
  run gitlore_tier_of "x.md" "$tiers"
  [ "$status" -eq 1 ]
  run gitlore_tier_of "gone/x.md" "$tiers"
  [ "$status" -eq 1 ]
}

@test "check passes on a well-formed store" {
  make_parent_with_memory
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  seed_root_bullet "project_overview.md" "the project"
  run gitlore_compose_check memory
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "check fails on a duplicate path in the root index" {
  make_parent_with_memory
  seed_root_bullet "dup.md" "first"
  seed_root_bullet "dup.md" "second"
  run gitlore_compose_check memory
  [ "$status" -eq 1 ]
  [[ "$output" == *"duplicate"* ]]
  [[ "$output" == *"dup.md"* ]]
}

@test "check fails when the manifest lists a tier that is not mounted" {
  make_parent_with_memory
  set_tier_manifest ghost
  run gitlore_compose_check memory
  [ "$status" -eq 1 ]
  [[ "$output" == *"ghost"* ]]
  [[ "$output" == *"not mounted"* ]]
}

@test "check fails on a root bullet whose prefix names no mounted tier" {
  make_parent_with_memory
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  seed_root_bullet "removed_tier/orphan.md" "leftover"
  run gitlore_compose_check memory
  [ "$status" -eq 1 ]
  [[ "$output" == *"removed_tier/orphan.md"* ]]
}

@test "check fails on a non-bullet line inside the bullet region" {
  make_parent_with_memory
  seed_root_bullet "a.md" "x"
  printf '\nSome interleaved prose\n\n' >> memory/MEMORY.md
  seed_root_bullet "b.md" "y"
  run gitlore_compose_check memory
  [ "$status" -eq 1 ]
  [[ "$output" == *"interleaved"* ]]
}

@test "check inspects tier carriers too, not just the root" {
  make_parent_with_memory
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  seed_tier_bullet ddaanet dup.md "first"
  seed_tier_bullet ddaanet dup.md "second"
  run gitlore_compose_check memory
  [ "$status" -eq 1 ]
  [[ "$output" == *"duplicate"* ]]
}

@test "problems from two indexes stay on separate lines" {
  # Each index's problems are captured separately, and a capture drops its
  # trailing newline: without one added back, the root's last problem and the
  # carrier's first share a line — and that string is the refusal banner the
  # user reads.
  make_parent_with_memory
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  seed_root_bullet "ddaanet/dup.md" "first"
  seed_root_bullet "ddaanet/dup.md" "second"
  seed_tier_bullet ddaanet other.md "first"
  seed_tier_bullet ddaanet other.md "second"
  run gitlore_compose_check memory
  [ "$status" -eq 1 ]
  [ "${#lines[@]}" -eq 2 ]
  [ "${lines[0]}" = "memory/MEMORY.md: duplicate pointer path ddaanet/dup.md" ]
  [ "${lines[1]}" = "memory/ddaanet/MEMORY.md: duplicate pointer path other.md" ]
}

@test "a mounted but unlisted tier is dormant, not an error" {
  make_parent_with_memory
  make_tier_in_memory ddaanet
  set_tier_manifest
  run gitlore_compose_check memory
  [ "$status" -eq 0 ]
}

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
  grep -qF -- '- [new_fact](new_fact.md) — authored in the root' memory/ddaanet/MEMORY.md
  run ! grep -qF 'ddaanet/new_fact.md' memory/ddaanet/MEMORY.md
}

# --- ordering ---
#
# The root index is the surface the agent edits, so the order it states there is
# an authored choice and mirror-down carries it into the carrier. A carrier-only
# arrival still lands where the carrier put it: the base makes that a positional
# merge, not an append.

# Replace $1's bullet block with the remaining args, preamble and trailer intact.
set_bullets() { local f="$1"; shift; printf '%s\n' "$@" | gitlore_compose_write "$f" >/dev/null; }

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

@test "a carrier-only arrival lands at its own offset, not at the end" {
  make_parent_with_memory
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  seed_tier_bullet ddaanet a.md "first"
  seed_tier_bullet ddaanet c.md "last"
  gitlore_compose memory                    # base recorded: a, c

  # Another consumer inserted a fact BETWEEN the two and we fast-forwarded it in.
  set_bullets memory/ddaanet/MEMORY.md \
    '- [a](a.md) — first' \
    '- [b](b.md) — arrived between' \
    '- [c](c.md) — last'

  run gitlore_compose memory
  [ "$status" -eq 0 ]
  la=$(grep -n 'ddaanet/a.md' memory/MEMORY.md | cut -d: -f1)
  lb=$(grep -n 'ddaanet/b.md' memory/MEMORY.md | cut -d: -f1)
  lc=$(grep -n 'ddaanet/c.md' memory/MEMORY.md | cut -d: -f1)
  [ "$la" -lt "$lb" ]
  [ "$lb" -lt "$lc" ]
}

@test "root and carrier inserting at one offset order the root's line first" {
  make_parent_with_memory
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  seed_tier_bullet ddaanet a.md "first"
  seed_tier_bullet ddaanet z.md "last"
  gitlore_compose memory                    # base recorded: a, z

  set_bullets memory/MEMORY.md \
    '- [a](ddaanet/a.md) — first' \
    '- [r](ddaanet/r.md) — authored in the root' \
    '- [z](ddaanet/z.md) — last'
  set_bullets memory/ddaanet/MEMORY.md \
    '- [a](a.md) — first' \
    '- [t](t.md) — arrived in the carrier' \
    '- [z](z.md) — last'

  run gitlore_compose memory
  [ "$status" -eq 0 ]
  lr=$(grep -n '](r.md)' memory/ddaanet/MEMORY.md | cut -d: -f1)
  lt=$(grep -n '](t.md)' memory/ddaanet/MEMORY.md | cut -d: -f1)
  lz=$(grep -n '](z.md)' memory/ddaanet/MEMORY.md | cut -d: -f1)
  [ "$lr" -lt "$lt" ]
  [ "$lt" -lt "$lz" ]
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
  grep -qF -- '— fresh curated text' memory/ddaanet/MEMORY.md
  run ! grep -qF 'stale carrier text' memory/ddaanet/MEMORY.md
  [ "$(grep -c 'shared.md' memory/MEMORY.md)" -eq 1 ]
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
  # That first compose recorded the three-way base (both facts), so the delete
  # below has something to diff against.

  # The agent deletes the fact and edits only the root index, the way the write
  # instructions describe — never touching the carrier by hand. Against the base
  # the root omission reads as a delete (not a fresh carrier add), so it drops.
  sed -i.bak '/ddaanet\/drop\.md/d' memory/MEMORY.md && rm -f memory/MEMORY.md.bak

  run gitlore_compose memory
  [ "$status" -eq 0 ]
  run ! grep -qF 'drop.md' memory/ddaanet/MEMORY.md
  grep -qF -- '- [keep](keep.md) — stays' memory/ddaanet/MEMORY.md
  run ! grep -qF 'ddaanet/drop.md' memory/MEMORY.md
  grep -qF 'ddaanet/keep.md' memory/MEMORY.md

  # And it stays gone — no later compose resurrects it from a stale mirror.
  run gitlore_compose memory
  [ "$status" -eq 0 ]
  run ! grep -qF 'drop.md' memory/ddaanet/MEMORY.md
  run ! grep -qF 'ddaanet/drop.md' memory/MEMORY.md
}

@test "an upstream-retracted tier fact syncs to a clean drop, not a resurrection" {
  # The real incident: another consumer deleted a shared fact (carrier line AND
  # file) and pushed; we fast-forwarded that clean carrier in, but the root
  # index still carried the stale line. Compose must complete the deletion —
  # against the base the carrier's omission is a delete, not the root line a new
  # add — instead of resurrecting the line into the freshly-cleaned carrier.
  make_parent_with_memory
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  seed_tier_bullet ddaanet kept.md "survives the sync"
  seed_tier_bullet ddaanet retracted.md "here until upstream drops it"
  gitlore_compose memory                    # records the base holding both facts
  grep -qF 'ddaanet/retracted.md' memory/MEMORY.md

  # An upstream fast-forward drops the fact: its carrier line and file are gone,
  # but the root index (not yet reprojected) still lists it.
  sed -i.bak '/retracted\.md/d' memory/ddaanet/MEMORY.md && rm -f memory/ddaanet/MEMORY.md.bak
  rm -f memory/ddaanet/retracted.md
  grep -qF 'ddaanet/retracted.md' memory/MEMORY.md         # the stale root remnant

  run gitlore_compose memory
  [ "$status" -eq 0 ]
  # The retraction propagated: gone from both indexes, the kept fact untouched.
  run ! grep -qF 'retracted.md' memory/MEMORY.md
  run ! grep -qF 'retracted.md' memory/ddaanet/MEMORY.md
  grep -qF 'ddaanet/kept.md' memory/MEMORY.md
  grep -qF -- '- [kept](kept.md) — survives the sync' memory/ddaanet/MEMORY.md

  # No dangling remnant lingers, and a second pass changes nothing (idempotent).
  run gitlore_compose_dangling memory
  [ -z "$output" ]
  run gitlore_compose memory
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  run ! grep -qF 'retracted.md' memory/MEMORY.md
}

@test "an upstream-added carrier fact reaches the root even when its block is non-empty" {
  # The mirror of the retraction: a fact another consumer ADDED arrives in the
  # carrier by fast-forward. Against the base its presence is a new add (not a
  # root-side deletion), so splice-up lifts it into the root — the case a plain
  # carrier-not-in-root drop used to eat once the root block was established.
  make_parent_with_memory
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  seed_tier_bullet ddaanet existing.md "already here"
  gitlore_compose memory                    # base + root now hold the existing fact
  grep -qF 'ddaanet/existing.md' memory/MEMORY.md

  # Upstream fast-forward brings a new carrier line the root has never seen.
  seed_tier_bullet ddaanet arrived.md "new from another repo"
  run gitlore_compose memory
  [ "$status" -eq 0 ]
  grep -qF -- '- [arrived](ddaanet/arrived.md) — new from another repo' memory/MEMORY.md
  grep -qF 'ddaanet/existing.md' memory/MEMORY.md
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

@test "a dormant tier still receives mirror-down, so no root line is lost" {
  make_parent_with_memory
  make_tier_in_memory ddaanet
  set_tier_manifest                       # mounted, never active
  seed_root_bullet "ddaanet/rescued.md" "would be dropped"
  run gitlore_compose memory
  [ "$status" -eq 0 ]
  grep -qF -- '- [rescued](rescued.md) — would be dropped' memory/ddaanet/MEMORY.md
  run ! grep -qF 'ddaanet/rescued.md' memory/MEMORY.md
}

@test "preamble and trailer are preserved verbatim" {
  make_parent_with_memory
  printf '# Memory Index\n\n- [A](a.md) — x\n\n<!-- footer -->\n' > memory/MEMORY.md
  run gitlore_compose memory
  [ "$status" -eq 0 ]
  head -1 memory/MEMORY.md | grep -qF '# Memory Index'
  tail -1 memory/MEMORY.md | grep -qF '<!-- footer -->'
}

@test "project bullets keep their order and are never rewritten" {
  make_parent_with_memory
  printf '# Memory Index\n\n- [C](c.md) — three\n- [A](a.md) — one\n- [B](b.md) — two\n' > memory/MEMORY.md
  gitlore_compose memory
  run gitlore_index_part memory/MEMORY.md bullets
  [ "$output" = "$(printf -- '- [C](c.md) — three\n- [A](a.md) — one\n- [B](b.md) — two')" ]
}

@test "dangling reports a root bullet whose file is absent" {
  make_parent_with_memory
  seed_root_bullet "gone.md" "the fact that got away"
  run gitlore_compose_dangling memory
  [ "$status" -eq 0 ]
  [[ "$output" == *"gone.md"* ]]
  [[ "$output" == *"memory/MEMORY.md"* ]]
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
  [[ "$output" != *"names no file"* ]]
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
  # No write permission on the carrier's directory: the temp file cannot be
  # created there, so gitlore_compose_write fails.
  chmod a-w memory/ddaanet
  run gitlore_compose memory
  chmod u+w memory/ddaanet
  [ "$status" -eq 2 ]
  [[ "$output" == *"could not write memory/ddaanet/MEMORY.md"* ]]
}

# --- compose-base audit log ---
#
# refs/gitlore/compose-base is a COMMIT CHAIN, not a bare blob. Each successful
# full compose appends one commit whose tree holds BOTH merge inputs of that
# pass: carrier.md (the base the next pass merges against) and root.md (the
# other input, otherwise unrecoverable — root composition is allowed to float
# ahead of any commit). `git log refs/gitlore/compose-base` in the tier is then
# the audit log, and `refs/gitlore/compose-base~N:carrier.md` recovers what any
# past pass merged against — which is what a vanished pointer line needs to be
# diagnosable at all.

# Echo the number of audit commits on a tier's compose-base ref. Args: $1 = tier.
base_count() { git -C "memory/$1" rev-list --count refs/gitlore/compose-base; }

@test "compose-base is a commit recording both merge inputs" {
  make_parent_with_memory
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  seed_tier_bullet ddaanet shared.md "a portable fact"
  seed_root_bullet "project_overview.md" "the project"
  run gitlore_compose memory
  [ "$status" -eq 0 ]

  run git -C memory/ddaanet cat-file -t refs/gitlore/compose-base
  [ "$status" -eq 0 ]
  [ "$output" = "commit" ]

  git -C memory/ddaanet cat-file -p refs/gitlore/compose-base:carrier.md \
    > "$BATS_TEST_TMPDIR/carrier.audit"
  cmp -s "$BATS_TEST_TMPDIR/carrier.audit" memory/ddaanet/MEMORY.md
  git -C memory/ddaanet cat-file -p refs/gitlore/compose-base:root.md \
    > "$BATS_TEST_TMPDIR/root.audit"
  cmp -s "$BATS_TEST_TMPDIR/root.audit" memory/MEMORY.md
}

@test "a second compose appends a second audit commit over the first" {
  make_parent_with_memory
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  seed_tier_bullet ddaanet shared.md "a portable fact"
  gitlore_compose memory
  cp memory/ddaanet/MEMORY.md "$BATS_TEST_TMPDIR/carrier.1"

  # A root-authored add: mirror-down rewrites the carrier, so the pass really
  # does compose something new rather than re-recording the same state.
  seed_root_bullet "ddaanet/added.md" "authored in the root"
  run gitlore_compose memory
  [ "$status" -eq 0 ]
  [ -n "$output" ]

  run base_count ddaanet
  [ "$status" -eq 0 ]
  [ "$output" = "2" ]

  # The FIRST pass's inputs are still recoverable behind the new tip.
  git -C memory/ddaanet cat-file -p 'refs/gitlore/compose-base~1:carrier.md' \
    > "$BATS_TEST_TMPDIR/carrier.audit1"
  cmp -s "$BATS_TEST_TMPDIR/carrier.audit1" "$BATS_TEST_TMPDIR/carrier.1"
}

@test "an idempotent compose appends no audit commit" {
  make_parent_with_memory
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  seed_tier_bullet ddaanet shared.md "a portable fact"
  seed_root_bullet "project_overview.md" "the project"
  gitlore_compose memory
  run base_count ddaanet
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]

  # Nothing changed, so nothing was reconciled: the log records passes that
  # moved the store, not every time the hook fired.
  run gitlore_compose memory
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  run base_count ddaanet
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]
}

@test "a legacy blob compose-base is still the base, and becomes a commit" {
  make_parent_with_memory
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  seed_tier_bullet ddaanet keep.md "stays"
  seed_tier_bullet ddaanet drop.md "goes away"
  # Root omits one of the two facts — a delete only if the base below is read.
  seed_root_bullet "ddaanet/keep.md" "stays"

  # The shape every live store carries today: the ref names the carrier BLOB.
  blob=$(git -C memory/ddaanet hash-object -w --stdin < memory/ddaanet/MEMORY.md)
  git -C memory/ddaanet update-ref refs/gitlore/compose-base "$blob"

  run gitlore_compose memory
  [ "$status" -eq 0 ]
  # Observable proof the blob was read as the base: drop.md is at base and the
  # root dropped it, so it goes. With an unread (empty) base it would be a fresh
  # carrier add and survive.
  run ! grep -qF 'drop.md' memory/ddaanet/MEMORY.md
  grep -qF -- '- [keep](keep.md) — stays' memory/ddaanet/MEMORY.md
  grep -qF 'ddaanet/keep.md' memory/MEMORY.md

  # And the store is migrated in place: the next pass has a chain to append to.
  run git -C memory/ddaanet cat-file -t refs/gitlore/compose-base
  [ "$status" -eq 0 ]
  [ "$output" = "commit" ]
}

@test "an up-only compose appends no audit commit and leaves the ref alone" {
  make_parent_with_memory
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  seed_tier_bullet ddaanet shared.md "a portable fact"
  gitlore_compose memory
  before=$(git -C memory/ddaanet rev-parse refs/gitlore/compose-base)

  # A carrier arrival the up-only pass splices into the root while writing no
  # carrier: root and carrier were never reconciled, so there is nothing to
  # record and the base must not move.
  seed_tier_bullet ddaanet arrived.md "new from another repo"
  run gitlore_compose memory up
  [ "$status" -eq 0 ]
  grep -qF 'ddaanet/arrived.md' memory/MEMORY.md

  [ "$(git -C memory/ddaanet rev-parse refs/gitlore/compose-base)" = "$before" ]
  run base_count ddaanet
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]
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
