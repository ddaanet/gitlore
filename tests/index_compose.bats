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

@test "check fails on a line welding two pointer bullets together" {
  # The data-loss shape: an `Edit` deletion consuming the separator on both
  # sides joins two bullets onto one physical line. It parses as ONE valid
  # bullet for the first path, so neither the duplicate nor the interleaved
  # rule sees anything — and the second path simply disappears from every
  # parse of the index, which the next compose reads as a root-side delete.
  make_parent_with_memory
  seed_root_bullet "kept.md" "first hook"
  printf -- '- [A](welded_a.md) — hook a- [B](welded_b.md) — hook b\n' >> memory/MEMORY.md
  run gitlore_compose_check memory
  [ "$status" -eq 1 ]
  [[ "$output" == *"welds"* ]]
  [[ "$output" == *"welded_b.md"* ]]   # names the path that would vanish
}

@test "check names the welded line, and the weld survives a missing separator" {
  # Glue that lands before the first hook's separator leaves the line with no
  # `) — ` between the two links at all, so a rule keyed on the separator
  # would miss it. Keyed on the first link's closing paren, it does not.
  make_parent_with_memory
  printf -- '- [A](welded_a.md)- [B](welded_b.md) — hook b\n' >> memory/MEMORY.md
  run gitlore_compose_check memory
  [ "$status" -eq 1 ]
  [[ "$output" == *"welds"* ]]
  [[ "$output" == *"welded_b.md"* ]]
}

@test "check leaves a hook carrying parens, dashes and a bracket alone" {
  # The negative half of the pair: the rule must not fire on ordinary hooks.
  # A bracketed span and a parenthetical are both common in real hooks; only a
  # second BULLET is corruption.
  make_parent_with_memory
  seed_root_bullet "fine.md" 'hook (with parens) — and [a bracket] and a - dash'
  run gitlore_compose_check memory
  [ "$status" -eq 0 ]
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

# --- rule 7: an active tier must sit at its pin (D36, D43) ---
#
# D36 rests on only one of the two projections having moved between passes. A
# tier moved outside /gitlore:merge breaks that: nothing adopted the carrier's
# newer text up into the root, so the down pass would write root's OLDER text
# over it. Observed in the wild after a hand-run `reset --hard origin/live`.

# Advance a mounted tier one commit past the gitlink the memory store's index
# records for it — the shape a hand-run `git -C memory/<tier> reset --hard
# origin/live` leaves behind. The carrier gains a line the root has never seen,
# which is exactly the text a down pass would overwrite.
move_tier_off_pin() {
  local tier="${1:-ddaanet}"
  seed_tier_bullet "$tier" upstream.md "arrived in another repo"
  git -C "memory/$tier" add -A || return 1
  GITLORE_MEMORY_COMMIT=1 git -C "memory/$tier" commit -qm "carrier advanced outside a merge"
}

# The store every test in this section starts from: one composed, committed tier
# line, so the pin is recorded and root and carrier agree before anything moves.
pinned_store_with_tier() {
  make_parent_with_memory
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  seed_tier_bullet ddaanet shared.md "a portable fact"
  gitlore_compose memory >/dev/null
  commit_memory_state
}

@test "compose refuses a moved tier and names the commands that return it" {
  pinned_store_with_tier
  pinned=$(git -C memory rev-parse :ddaanet)
  move_tier_off_pin ddaanet
  moved=$(git -C memory/ddaanet rev-parse HEAD)
  abs=$(cd memory/ddaanet && pwd)
  cp memory/MEMORY.md "$BATS_TEST_TMPDIR/root.before"
  cp memory/ddaanet/MEMORY.md "$BATS_TEST_TMPDIR/tier.before"

  run gitlore_compose memory
  [ "$status" -eq 1 ]
  [[ "$output" == *"tier 'ddaanet' is checked out at ${moved:0:12}"* ]]
  [[ "$output" == *"the memory store records ${pinned:0:12}"* ]]
  # Verbatim-runnable: absolute path, full sha.
  [[ "$output" == *"git -C \"$abs\" checkout --detach $pinned"* ]]
  # Nothing written. The refusal is the whole point: a down pass here replaces
  # the carrier's newer text with root's older text and reports success.
  cmp -s memory/MEMORY.md "$BATS_TEST_TMPDIR/root.before"
  cmp -s memory/ddaanet/MEMORY.md "$BATS_TEST_TMPDIR/tier.before"
}

@test "a moved tier holding MERGE_HEAD is sent to /gitlore:resolve instead" {
  pinned_store_with_tier
  move_tier_off_pin ddaanet
  git -C memory/ddaanet rev-parse HEAD \
    > "$(git -C memory/ddaanet rev-parse --git-path MERGE_HEAD)"

  run gitlore_compose memory
  [ "$status" -eq 1 ]
  [[ "$output" == *"tier 'ddaanet' is mid-merge"* ]]
  [[ "$output" == *"/gitlore:resolve"* ]]
  # And NOT the return-to-the-pin remedy: that checkout unlinks MERGE_HEAD and
  # destroys the prepared merge, so the two wordings must not both appear.
  [[ "$output" != *"checkout --detach"* ]]
}

@test "a moved tier with a merge state file and no MERGE_HEAD is mid-merge too" {
  pinned_store_with_tier
  move_tier_off_pin ddaanet
  # What a re-checkout leaves behind: remove_branch_state() unlinked MERGE_HEAD
  # and the state file outlived it (tests/resolve_recovery.bats).
  printf '{"flavor":"head-vs-remote"}\n' > "$(gitlore_merge_state_file memory/ddaanet)"

  run gitlore_compose memory
  [ "$status" -eq 1 ]
  [[ "$output" == *"tier 'ddaanet' is mid-merge"* ]]
  [[ "$output" != *"checkout --detach"* ]]
}

@test "staging the moved gitlink lets the same store compose again" {
  pinned_store_with_tier
  move_tier_off_pin ddaanet
  run gitlore_compose memory
  [ "$status" -eq 1 ]

  # The hand-off every merge path performs as its last act (D43).
  git -C memory add -- ddaanet
  seed_root_bullet "ddaanet/local.md" "authored here"
  printf -- '---\nname: local\ndescription: ""\n---\n\nbody\n' > memory/ddaanet/local.md

  run gitlore_compose memory
  [ "$status" -eq 0 ]
  # It composed rather than merely returning 0: the root-authored line mirrored
  # down into the carrier, and the carrier's own arrival was not destroyed.
  grep -qxF -- '- [local](local.md) — authored here' memory/ddaanet/MEMORY.md
  grep -qxF -- '- [upstream](upstream.md) — arrived in another repo' memory/ddaanet/MEMORY.md
}

@test "adoption still runs while the tier is ahead of its pin" {
  # The up pass IS the merge path, and it runs before that path stages the
  # gitlink — so the rule that refuses the down pass must not reach it.
  pinned_store_with_tier
  move_tier_off_pin ddaanet

  run gitlore_compose_up memory ddaanet
  [ "$status" -eq 0 ]
  assert_bullets memory/MEMORY.md \
    '- [shared](ddaanet/shared.md) — a portable fact' \
    '- [upstream](ddaanet/upstream.md) — arrived in another repo'
}

@test "a dormant tier moved off its pin does not refuse" {
  # The down pass never projects onto a dormant tier, so its position is not
  # this rule's business.
  pinned_store_with_tier
  set_tier_manifest
  move_tier_off_pin ddaanet

  run gitlore_compose memory
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
  # No write permission on the carrier's directory: the temp file cannot be
  # created there, so gitlore_compose_write fails.
  chmod a-w memory/ddaanet
  run gitlore_compose memory
  chmod u+w memory/ddaanet
  [ "$status" -eq 2 ]
  [[ "$output" == *"could not write memory/ddaanet/MEMORY.md"* ]]
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
