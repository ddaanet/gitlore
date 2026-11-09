#!/usr/bin/env bats

load helpers/setup
load helpers/fixtures
load helpers/tier-fixtures

# Header as in tests/index_compose.bats. Covers rule 7 edge cases: a spaced
# project path, a mid-merge tier, the take's path for a tier it moved, and a
# dormant tier moved ahead of its pin.
# shellcheck disable=SC1091
source "$PLUGIN_ROOT/scripts/lib/index-compose.sh"

setup()    { setup_tmp_repo; }
teardown() { teardown_tmp_repo; }

# The two cases below re-root $TMP_REPO under a path holding a space. The
# rule reaches its tier through the relative `$mempath` it was called with, so
# the space enters at the one place it resolves an absolute path: the `abs` the
# sideways refusal's command carries.
reroot_spaced() {
  teardown_tmp_repo
  TMP_REPO="$(mktemp -d "${TMPDIR:-/tmp}/gitlore test.XXXXXX")"
  export TMP_REPO
  cd "$TMP_REPO" || return 1
  git init -q -b main
  git config user.email "test@example.com"
  git config user.name "Test"
}

@test "a tier ahead of its pin is refused under a project path holding a space" {
  # The tier's local `live` follows HEAD here, as after a tier commit whose
  # gitlink the memory side then lost: the refusal reads the pin, not `live`,
  # so this shape is refused like the one HEAD alone holds. Fails under a pass
  # that composes the tier up, or one whose spaced-path handling turns the
  # refusal into an error of its own.
  reroot_spaced
  pinned_store_with_tier
  pinned=$(git -C memory rev-parse :ddaanet)
  move_tier_off_pin_into_live ddaanet
  moved=$(git -C memory/ddaanet rev-parse HEAD)
  abs=$(cd memory/ddaanet && pwd)
  # The fixture really is spaced, asserted rather than assumed.
  [[ "$abs" == *" "* ]]
  cp memory/MEMORY.md "$BATS_TEST_TMPDIR/root.before"
  cp memory/ddaanet/MEMORY.md "$BATS_TEST_TMPDIR/tier.before"

  run gitlore_compose memory
  [ "$status" -eq 1 ]
  tierline=$(printf '%s\n' "$output" | grep -F "tier 'ddaanet'")
  [[ "$tierline" == *"${moved:0:12}, ahead of the commit the memory store records at ${pinned:0:12}"* ]]
  [[ "$tierline" == *"Run /gitlore:merge"* ]]
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$moved" ]
  [ "$(git -C memory rev-parse :ddaanet)" = "$pinned" ]
  cmp -s memory/MEMORY.md "$BATS_TEST_TMPDIR/root.before"
  cmp -s memory/ddaanet/MEMORY.md "$BATS_TEST_TMPDIR/tier.before"
}

@test "a spaced tier moved sideways off its pin prints a command that runs verbatim" {
  # The refusal that hands the return to a human. Its command carries the one
  # absolute path the rule builds, so it is where a lost or split space becomes
  # a command that silently operates on the wrong tree.
  reroot_spaced
  pinned_store_with_tier
  move_tier_diverged_off_pin ddaanet
  pinned=$(git -C memory rev-parse :ddaanet)
  moved=$(git -C memory/ddaanet rev-parse HEAD)
  [ "$moved" != "$pinned" ]

  run gitlore_compose memory
  [ "$status" -eq 1 ]
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$moved" ]
  tierline=$(printf '%s\n' "$output" | grep -F "tier 'ddaanet'")
  cmd=${tierline#*\`}
  cmd=${cmd%%\`*}
  [[ "$cmd" == *"gitlore test."* ]]
  # Verbatim, from an unrelated directory: what the reader does with it.
  (cd / && eval "$cmd")
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$pinned" ]
}

@test "a moved tier holding MERGE_HEAD is sent to /gitlore:resolve instead" {
  # The branch-ORDER case: move_tier_off_pin leaves the tier ahead of its pin,
  # which passes on its own, so only the order decides that the mid-merge
  # refusal answers. That the fixture is ahead is asserted rather than left to
  # the helper's name — a later repoint of move_tier_off_pin would otherwise
  # turn the ordering pin vacuous in silence.
  pinned_store_with_tier
  pinned=$(git -C memory rev-parse :ddaanet)
  move_tier_off_pin ddaanet
  git -C memory/ddaanet merge-base --is-ancestor "$pinned" HEAD
  git -C memory/ddaanet rev-parse HEAD \
    > "$(git -C memory/ddaanet rev-parse --git-path MERGE_HEAD)"

  run gitlore_compose memory
  [ "$status" -eq 1 ]
  [[ "$output" == *"tier 'ddaanet' is mid-merge"* ]]
  [[ "$output" == *"/gitlore:resolve"* ]]
  # And NOT the return-to-the-pin remedy: that checkout unlinks MERGE_HEAD and
  # destroys the prepared merge, so the two wordings must not both appear.
  [[ "$output" != *"checkout --detach"* ]]
  # Nor the tier-ahead refusal, which would mean that arm ran first.
  [[ "$output" != *"ahead"* ]]
}

@test "a moved tier with a merge state file and no MERGE_HEAD is mid-merge too" {
  # The second half of the branch-order pin above, over the other mid-merge
  # predicate.
  pinned_store_with_tier
  pinned=$(git -C memory rev-parse :ddaanet)
  move_tier_off_pin ddaanet
  git -C memory/ddaanet merge-base --is-ancestor "$pinned" HEAD
  # What a re-checkout leaves behind: remove_branch_state() unlinked MERGE_HEAD
  # and the state file outlived it (tests/resolve_recovery.bats).
  printf '{"flavor":"head-vs-remote"}\n' > "$(gitlore_merge_state_file memory/ddaanet)"

  run gitlore_compose memory
  [ "$status" -eq 1 ]
  [[ "$output" == *"tier 'ddaanet' is mid-merge"* ]]
  [[ "$output" != *"checkout --detach"* ]]
  [[ "$output" != *"ahead"* ]]
}

@test "a tier the take moved keeps its arrival while root's new line mirrors down" {
  # The take's path for a tier it moved (gitlore_compose_moved_tiers): compose
  # it up, record the pair. Fails if the next pass reads a base older than the
  # recorded gitlink and takes the arrival for a root deletion.
  pinned_store_with_tier
  move_tier_off_pin ddaanet
  run gitlore_compose_up memory ddaanet :
  [ "$status" -eq 0 ]
  git -C memory add -- MEMORY.md ddaanet
  git -C memory commit -qm "Update MEMORY.md for ddaanet tier merge."
  [ "$(git -C memory rev-parse HEAD:ddaanet)" = "$(git -C memory/ddaanet rev-parse HEAD)" ]

  seed_root_bullet "ddaanet/local.md" "authored here"
  printf -- '---\nname: local\ndescription: ""\n---\n\nbody\n' > memory/ddaanet/local.md

  run gitlore_compose memory
  [ "$status" -eq 0 ]
  # It composed rather than merely returning 0: the root-authored line mirrored
  # down into the carrier, and the carrier's own arrival was not destroyed.
  grep -qxF -- '- [local](local.md) — authored here' memory/ddaanet/MEMORY.md
  grep -qxF -- '- [upstream](upstream.md) — arrived in another repo' memory/ddaanet/MEMORY.md
}

@test "the compose-up adopts a tier ahead of its pin" {
  # The end of a take calls it directly for the tiers it moved.
  pinned_store_with_tier
  move_tier_off_pin ddaanet

  run gitlore_compose_up memory ddaanet :
  [ "$status" -eq 0 ]
  assert_bullets memory/MEMORY.md \
    '- [shared](ddaanet/shared.md) — a portable fact' \
    '- [upstream](ddaanet/upstream.md) — arrived in another repo'
}

@test "a dormant tier moved ahead of its pin is refused too" {
  # The commit's `add -A` records a dormant tier's HEAD as much as an active
  # one's, and the take walks every mounted tier. Fails under a pin check that
  # walks the active tiers only.
  pinned_store_with_tier
  set_tier_manifest
  pinned=$(git -C memory rev-parse :ddaanet)
  move_tier_off_pin ddaanet
  moved=$(git -C memory/ddaanet rev-parse HEAD)
  # Root still carries the dormant tier's block here, which a pass would drop:
  # the byte-identical root pins the refusal running ahead of that write.
  cp memory/MEMORY.md "$BATS_TEST_TMPDIR/root.before"
  cp memory/ddaanet/MEMORY.md "$BATS_TEST_TMPDIR/tier.before"

  run gitlore_compose memory
  [ "$status" -eq 1 ]
  tierline=$(printf '%s\n' "$output" | grep -F "tier 'ddaanet'")
  [[ "$tierline" == *"${moved:0:12}, ahead of the commit the memory store records at ${pinned:0:12}"* ]]
  [[ "$tierline" == *"Run /gitlore:merge"* ]]
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$moved" ]
  [ "$(git -C memory rev-parse :ddaanet)" = "$pinned" ]
  cmp -s memory/MEMORY.md "$BATS_TEST_TMPDIR/root.before"
  cmp -s memory/ddaanet/MEMORY.md "$BATS_TEST_TMPDIR/tier.before"
}

