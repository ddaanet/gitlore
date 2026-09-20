#!/usr/bin/env bats
bats_require_minimum_version 1.5.0

load helpers/setup
load helpers/fixtures
load helpers/tier-fixtures

# Header as in tests/index_compose.bats. Covers rule 7: an active tier must
# sit at its pin.
# shellcheck disable=SC1091
source "$PLUGIN_ROOT/scripts/lib/index-compose.sh"

setup()    { setup_tmp_repo; }
teardown() { teardown_tmp_repo; }

# --- rule 7: an active tier must sit at its pin (D36, D43) ---
#
# D36 rests on only one of the two projections having moved between passes. A
# tier moved outside /gitlore:merge breaks that: nothing adopted the carrier's
# newer text up into the root, so the down pass would write root's OLDER text
# over it. Observed in the wild after a hand-run `reset --hard origin/live`.

@test "compose refuses a tier moved sideways onto unrelated history and names the commands that return it" {
  # Repointed at Item 1.3 slice 2 onto the SIDEWAYS fixture: this wording and
  # its checkout --detach remedy are the case that stays unchanged once the
  # new ahead branch lands, so this test now proves that, not an ahead
  # fixture whose wording the new branch is about to move elsewhere.
  #
  # Born-green: today ahead and sideways get identical wording, so this
  # cannot be forced red by writing it — its red is owed to the test review's
  # mutation instead. Implement the new branch WITHOUT the
  # `merge-base --is-ancestor` test (i.e. unconditionally, for every off-pin
  # tier); the `checkout --detach` and `!= *"ahead"*` assertions below go red
  # because every off-pin tier — sideways included — now takes the ahead
  # wording. Then restore the ancestry test.
  pinned_store_with_tier
  pinned=$(git -C memory rev-parse :ddaanet)
  move_tier_sideways_off_pin ddaanet
  moved=$(git -C memory/ddaanet rev-parse HEAD)
  abs=$(cd memory/ddaanet && pwd)
  cp memory/MEMORY.md "$BATS_TEST_TMPDIR/root.before"
  cp memory/ddaanet/MEMORY.md "$BATS_TEST_TMPDIR/tier.before"
  # The fixture's shape, asserted rather than assumed: no shared history at all,
  # so neither ancestry test can hold. Without this the test would keep passing
  # if the fixture ever drifted into some other shape.
  run ! git -C memory/ddaanet merge-base "$pinned" "$moved"

  run gitlore_compose memory
  [ "$status" -eq 1 ]
  [[ "$output" == *"tier 'ddaanet' is checked out at ${moved:0:12}"* ]]
  [[ "$output" == *"the memory store records ${pinned:0:12}"* ]]
  # Verbatim-runnable: absolute path, full sha.
  [[ "$output" == *"git -C \"$abs\" checkout --detach $pinned"* ]]
  # And NOT the ahead branch's words: returning THIS tier to its pin is the
  # right remedy, so a branch that answered "ahead" here would be offering the
  # wrong one.
  [[ "$output" != *"ahead"* ]]
  # Nothing written. The refusal is the whole point: a down pass here replaces
  # the carrier's newer text with root's older text and reports success.
  cmp -s memory/MEMORY.md "$BATS_TEST_TMPDIR/root.before"
  cmp -s memory/ddaanet/MEMORY.md "$BATS_TEST_TMPDIR/tier.before"
}

@test "compose refuses a tier diverged from its pin with the same return-to-pin remedy" {
  # The everyday sideways shape, and the one the orphan fixture above cannot
  # stand in for: HEAD and the pin share an ancestor, so `merge-base` succeeds
  # and only `merge-base --is-ancestor` separates this from the ahead case. An
  # implementation that branched on shared history would answer "ahead" here
  # and offer a remedy that is not the right one, while the orphan test stayed
  # green.
  #
  # Born-green, with the same mutation as the orphan test above.
  pinned_store_with_tier
  move_tier_diverged_off_pin ddaanet
  pinned=$(git -C memory rev-parse :ddaanet)
  moved=$(git -C memory/ddaanet rev-parse HEAD)
  abs=$(cd memory/ddaanet && pwd)
  # The shape, asserted rather than assumed: shared history WITH the pin, and
  # the pin still not contained in HEAD.
  git -C memory/ddaanet merge-base "$pinned" "$moved" >/dev/null
  run ! git -C memory/ddaanet merge-base --is-ancestor "$pinned" "$moved"

  run gitlore_compose memory
  [ "$status" -eq 1 ]
  [[ "$output" == *"tier 'ddaanet' is checked out at ${moved:0:12}"* ]]
  [[ "$output" == *"the memory store records ${pinned:0:12}"* ]]
  [[ "$output" == *"git -C \"$abs\" checkout --detach $pinned"* ]]
  [[ "$output" != *"ahead"* ]]
}

@test "a tier ahead of its pin whose commits HEAD alone holds is refused where it stands" {
  # An AHEAD tier (HEAD is a descendant of the pin — move_tier_off_pin's
  # fixture) with no local `live` at all: the take reads `live`, so the
  # checkout back to the pin would strand every commit HEAD alone holds, and
  # the tier is left exactly where it is. What the refusal owes is the act that
  # puts those commits where the tooling can reach them.
  #
  # Three positives on the tier's OWN report line, so none of them can be
  # satisfied by a different line of the report: both truncated shas — which
  # commit the tier is on and which one the store records — and "ahead", the
  # direction, which loose in the whole output could belong to a sentence
  # saying the opposite.
  pinned_store_with_tier
  pinned=$(git -C memory rev-parse :ddaanet)
  move_tier_off_pin ddaanet
  moved=$(git -C memory/ddaanet rev-parse HEAD)
  # The fixture's shape, asserted rather than assumed: HEAD contains the pin,
  # and the mount left no local `live` for the take to read.
  git -C memory/ddaanet merge-base --is-ancestor "$pinned" "$moved"
  run ! git -C memory/ddaanet rev-parse -q --verify live
  abs=$(cd memory/ddaanet && pwd)

  run gitlore_compose memory
  [ "$status" -eq 1 ]
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$moved" ]
  tierline=$(printf '%s\n' "$output" | grep -F "tier 'ddaanet'")
  [[ "$tierline" == *"${moved:0:12}"* ]]
  [[ "$tierline" == *"${pinned:0:12}"* ]]
  [[ "$tierline" == *"ahead"* ]]
  # The remedy is the tooling's own adoption, reached by putting HEAD's commits
  # in the tier's local `live`: the runnable push, quoted so a spaced project
  # path survives the paste, and the take that adopts from there.
  [[ "$tierline" == *"git -C \"$abs\" push . HEAD:refs/heads/live"* ]]
  [[ "$tierline" == *"/gitlore:merge"* ]]
  # Adoption is never a hand edit of root's block: the superseded remedy had the
  # reader retext the root index and stage the gitlink themselves, which is the
  # overwrite this refusal exists to stop — staged before the carrier is adopted
  # up, the next compose writes root's older text over it.
  [[ "$output" != *"replace every line"* ]]
  [[ "$output" != *"add -- \"ddaanet\""* ]]
  # `checkout --detach <pinned>` is exactly the command that would destroy the
  # commits this tier carries while `live` does not hold them, so it must not be
  # offered here — asserted explicitly so it cannot pass by the ahead wording
  # simply never having been written.
  [[ "$output" != *"checkout --detach"* ]]
}

@test "a dirty tier ahead of its pin is refused where it stands" {
  # The same refusal for the other reason: `live` holds every commit HEAD does,
  # so the checkout would lose no commit — but it would carry work no approved
  # summary covers onto the pin, and the take refuses a dirty store in any case.
  pinned_store_with_tier
  pinned=$(git -C memory rev-parse :ddaanet)
  move_tier_off_pin_into_live ddaanet
  moved=$(git -C memory/ddaanet rev-parse HEAD)
  printf -- '---\nname: pending\ndescription: ""\n---\n\nunapproved\n' > memory/ddaanet/pending.md
  # The fixture's shape: the take's own reachability test passes, and only the
  # dirt separates this from the returned-to-the-pin case.
  git -C memory/ddaanet merge-base --is-ancestor "$moved" live
  [ -n "$(git -C memory/ddaanet status --porcelain)" ]

  run gitlore_compose memory
  [ "$status" -eq 1 ]
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$moved" ]
  [ -f memory/ddaanet/pending.md ]
  tierline=$(printf '%s\n' "$output" | grep -F "tier 'ddaanet'")
  [[ "$tierline" == *"ahead"* ]]
  # Leaving the tier clean is the act that unblocks it, and the refusal names it.
  [[ "$tierline" == *"leave nothing uncommitted"* ]]
  [[ "$output" != *"it is back on the pin"* ]]
}

@test "a tier ahead of its pin whose local 'live' holds its commits is returned to the pin for the take" {
  # The state a tier commit leaves once the memory side loses the moved gitlink:
  # `live` holds every commit HEAD does, so the pin checkout discards nothing
  # and leaves exactly what gitlore_adopt_advanced_live takes — a clean tier on
  # its pin with `live` ahead of it. The refusal stands, because the root index
  # still has to take the carrier before anything composes down onto it.
  pinned_store_with_tier
  pinned=$(git -C memory rev-parse :ddaanet)
  move_tier_off_pin_into_live ddaanet
  moved=$(git -C memory/ddaanet rev-parse HEAD)
  # The fixture's shape, asserted rather than assumed: HEAD contains the pin,
  # and `live` contains HEAD.
  git -C memory/ddaanet merge-base --is-ancestor "$pinned" "$moved"
  git -C memory/ddaanet merge-base --is-ancestor "$moved" live

  run gitlore_compose memory
  [ "$status" -eq 1 ]
  # The act: HEAD back on the pin, the commits still in `live`, and the working
  # tree actually followed — a ref move that left the carrier where it was would
  # have the down pass overwrite it on the next pass all the same.
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$pinned" ]
  [ "$(git -C memory/ddaanet rev-parse live)" = "$moved" ]
  git -C memory/ddaanet show "$pinned:MEMORY.md" > "$BATS_TEST_TMPDIR/pinned-carrier.md"
  cmp memory/ddaanet/MEMORY.md "$BATS_TEST_TMPDIR/pinned-carrier.md"
  [ -z "$(git -C memory/ddaanet status --porcelain)" ]

  tierline=$(printf '%s\n' "$output" | grep -F "tier 'ddaanet'")
  [[ "$tierline" == *"${moved:0:12}"* ]]
  [[ "$tierline" == *"${pinned:0:12}"* ]]
  # The next command is the take, which adopts the carrier into the root index
  # before the gitlink moves.
  [[ "$tierline" == *"/gitlore:merge"* ]]
  # Adoption is the tooling's: neither a hand rebuild of root's block nor the
  # command that puts HEAD's commits into `live`, which they are already in.
  [[ "$output" != *"replace every line"* ]]
  [[ "$output" != *"HEAD:refs/heads/live"* ]]
}

@test "a tier that cannot be returned to its pin is refused untouched, with git's own message" {
  # The failure is stood in for rather than provoked: `git checkout` exits 0
  # after reporting files it could not unlink (measured on git 2.47 against a
  # read-only worktree directory), so a permission induction would move HEAD
  # and prove nothing. The stub intercepts that one call and leaves every other
  # git call in the pass alone. A refusal that reported the return as done would
  # leave the next pass composing root's older text over a carrier still ahead.
  pinned_store_with_tier
  pinned=$(git -C memory rev-parse :ddaanet)
  move_tier_off_pin_into_live ddaanet
  moved=$(git -C memory/ddaanet rev-parse HEAD)
  abs=$(cd memory/ddaanet && pwd)
  git() {
    if [ "$1" = -C ] && [ "$3" = checkout ]; then
      echo "fatal: simulated checkout failure" >&2
      return 128
    fi
    command git "$@"
  }

  run gitlore_compose memory
  [ "$status" -eq 1 ]
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$moved" ]
  tierline=$(printf '%s\n' "$output" | grep -F "tier 'ddaanet'")
  [[ "$tierline" == *"could not be returned to the pin"* ]]
  # git's own message, on the one line this report gives the tier, and the
  # command that finishes the return once the path is writable again.
  [[ "$tierline" == *"git said:"* ]]
  [[ "$tierline" == *"git -C \"$abs\" checkout --detach $pinned"* ]]
  [[ "$output" != *"it is back on the pin"* ]]
}

