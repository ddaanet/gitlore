#!/usr/bin/env bats
bats_require_minimum_version 1.5.0

load helpers/setup
load helpers/fixtures
load helpers/tier-fixtures

# Header as in tests/index_compose.bats. Covers rule 7: a mounted tier must
# sit on or ahead of its pin.
# shellcheck disable=SC1091
source "$PLUGIN_ROOT/scripts/lib/index-compose.sh"

setup()    { setup_tmp_repo; }
teardown() { teardown_tmp_repo; }

# --- rule 7: a tier must sit on or ahead of its pin ---
#
# A tier ahead of its pin is composed up three-way. One moved sideways or
# behind is refused: a down pass would write root's text over a carrier no
# compose has read, and a commit would record a commit the pin has passed.
# Observed in the wild after a hand-run `reset --hard origin/live`.

@test "compose refuses a tier moved sideways onto unrelated history and names the commands that return it" {
  # The SIDEWAYS fixture: neither ancestry test holds, so the refusal names
  # the checkout that returns the tier to its pin.
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
  # And NOT a tier ahead's words: returning THIS tier to its pin is the right
  # remedy.
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

@test "a tier ahead of its pin composes up and is left where it stands" {
  pinned_store_with_tier
  pinned=$(git -C memory rev-parse :ddaanet)
  move_tier_off_pin ddaanet
  moved=$(git -C memory/ddaanet rev-parse HEAD)
  # The fixture's shape, asserted rather than assumed: HEAD contains the pin,
  # and the mount left no local `live` that holds HEAD's commits.
  git -C memory/ddaanet merge-base --is-ancestor "$pinned" "$moved"
  run ! git -C memory/ddaanet rev-parse -q --verify live

  run gitlore_compose memory
  [ "$status" -eq 0 ]
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$moved" ]
  grep -qxF -- '- [upstream](ddaanet/upstream.md) — arrived in another repo' memory/MEMORY.md
  [ -z "$(git -C memory/ddaanet status --porcelain)" ]
  # The pass stages the merged tier's gitlink and commits nothing: the staged
  # gitlink is the base the next pass reads (D78), and the commit that records
  # it is the user's, or the take's bookkeeping one.
  [ "$(git -C memory rev-parse :ddaanet)" = "$moved" ]
  [ "$(git -C memory rev-parse HEAD:ddaanet)" = "$pinned" ]
}

@test "the check leaves the gitlink of a tier ahead of its pin unstaged" {
  pinned_store_with_tier
  pinned=$(git -C memory rev-parse :ddaanet)
  move_tier_off_pin ddaanet

  run gitlore_compose_pending memory
  [ "$status" -eq 0 ]
  [ "$output" = "memory/MEMORY.md" ]
  [ "$(git -C memory rev-parse :ddaanet)" = "$pinned" ]
}

@test "a tier behind its pin is refused naming /gitlore:merge, and nothing is written" {
  # The memory index records a newer commit of the tier than the one checked
  # out, which a raw pull in memory leaves: a pass would project root onto an
  # older carrier, and a commit would record the older commit.
  pinned_store_with_tier
  old=$(git -C memory rev-parse :ddaanet)
  move_tier_off_pin ddaanet
  git -C memory add -- ddaanet
  pinned=$(git -C memory rev-parse :ddaanet)
  git -C memory/ddaanet checkout -q --detach "$old"
  [ "$pinned" != "$old" ]
  git -C memory/ddaanet merge-base --is-ancestor "$old" "$pinned"
  cp memory/MEMORY.md "$BATS_TEST_TMPDIR/root.before"
  cp memory/ddaanet/MEMORY.md "$BATS_TEST_TMPDIR/tier.before"

  run gitlore_compose memory
  [ "$status" -eq 1 ]
  tierline=$(printf '%s\n' "$output" | grep -F "tier 'ddaanet'")
  [[ "$tierline" == *"${old:0:12}"* ]]
  [[ "$tierline" == *"${pinned:0:12}"* ]]
  [[ "$tierline" == *"behind"* ]]
  [[ "$tierline" == *"/gitlore:merge"* ]]
  [[ "$output" != *"checkout --detach"* ]]
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$old" ]
  cmp -s memory/MEMORY.md "$BATS_TEST_TMPDIR/root.before"
  cmp -s memory/ddaanet/MEMORY.md "$BATS_TEST_TMPDIR/tier.before"
}
