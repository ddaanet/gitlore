#!/usr/bin/env bats

load helpers/setup
load helpers/fixtures
load helpers/tier-fixtures

# Header as in tests/index_compose.bats. Covers rule 7 edge cases: a spaced
# project path, a mid-merge tier, and a dormant tier moved ahead of its pin.
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

@test "a tier ahead of its pin composes up under a project path holding a space" {
  reroot_spaced
  pinned_store_with_tier
  move_tier_off_pin_into_live ddaanet
  moved=$(git -C memory/ddaanet rev-parse HEAD)
  abs=$(cd memory/ddaanet && pwd)
  # The fixture really is spaced, asserted rather than assumed.
  [[ "$abs" == *" "* ]]

  run gitlore_compose memory
  [ "$status" -eq 0 ]
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$moved" ]
  grep -qxF -- '- [upstream](ddaanet/upstream.md) — arrived in another repo' memory/MEMORY.md
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
  # Nor a pass over a tier ahead, which would mean it ran first.
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

@test "a tier ahead of its pin keeps its arrival while root's new line mirrors down" {
  pinned_store_with_tier
  move_tier_off_pin ddaanet
  run gitlore_compose memory
  [ "$status" -eq 0 ]

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

@test "a dormant tier moved ahead of its pin does not refuse" {
  pinned_store_with_tier
  set_tier_manifest
  move_tier_off_pin ddaanet

  run gitlore_compose memory
  [ "$status" -eq 0 ]
}

