#!/usr/bin/env bats

load helpers/setup
load helpers/fixtures
load helpers/tier-fixtures

# Header as in tests/index_compose.bats. Covers rule 7 edge cases: a spaced
# project path, and a dormant tier moved off its pin.
# shellcheck disable=SC1091
source "$PLUGIN_ROOT/scripts/lib/index-compose.sh"

setup()    { setup_tmp_repo; }
teardown() { teardown_tmp_repo; }

# The two cases below re-root $TMP_REPO under a path holding a space. The
# branch reaches its tier through the relative `$mempath` it was called with,
# so the space enters at the one place it resolves an absolute path: the `abs`
# the printed command carries. The first case is the whole branch running under
# such a root, the second is that command.
reroot_spaced() {
  teardown_tmp_repo
  TMP_REPO="$(mktemp -d "${TMPDIR:-/tmp}/gitlore test.XXXXXX")"
  export TMP_REPO
  cd "$TMP_REPO" || return 1
  git init -q -b main
  git config user.email "test@example.com"
  git config user.name "Test"
}

@test "a tier ahead of its pin is returned to it under a project path holding a space" {
  reroot_spaced
  pinned_store_with_tier
  pinned=$(git -C memory rev-parse :ddaanet)
  move_tier_off_pin_into_live ddaanet
  moved=$(git -C memory/ddaanet rev-parse HEAD)
  abs=$(cd memory/ddaanet && pwd)
  # The fixture really is spaced, asserted rather than assumed.
  [[ "$abs" == *" "* ]]

  run gitlore_compose memory
  [ "$status" -eq 1 ]
  # The act, unchanged by the space: HEAD on the pin, the commits kept in
  # `live`, and the worktree carrier following HEAD rather than a ref move
  # alone.
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$pinned" ]
  [ "$(git -C memory/ddaanet rev-parse live)" = "$moved" ]
  git -C memory/ddaanet show "$pinned:MEMORY.md" > "$BATS_TEST_TMPDIR/pinned-carrier.md"
  cmp memory/ddaanet/MEMORY.md "$BATS_TEST_TMPDIR/pinned-carrier.md"
  [ -z "$(git -C memory/ddaanet status --porcelain)" ]
  tierline=$(printf '%s\n' "$output" | grep -F "tier 'ddaanet'")
  [[ "$tierline" == *"it is back on the pin"* ]]
  [[ "$tierline" == *"/gitlore:merge"* ]]
}

@test "a spaced tier that cannot be returned to its pin prints a command that runs verbatim" {
  # The arm of the same branch that hands the return to a human. Its command
  # carries the one absolute path the branch builds, so it is where a lost or
  # split space becomes a command that silently operates on the wrong tree.
  reroot_spaced
  pinned_store_with_tier
  pinned=$(git -C memory rev-parse :ddaanet)
  move_tier_off_pin_into_live ddaanet
  moved=$(git -C memory/ddaanet rev-parse HEAD)
  # The `unset -f` below is what leaves shellcheck reading the body as dead.
  # shellcheck disable=SC2317
  git() {
    if [ "$1" = -C ] && [ "$3" = checkout ]; then
      echo "fatal: simulated checkout failure" >&2
      return 128
    fi
    command git "$@"
  }

  run gitlore_compose memory
  [ "$status" -eq 1 ]
  # Dropped before the emitted command runs: the point is that the command
  # works, not that the stub lets it.
  unset -f git
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
  # This is also Item 1.3 slice 2's branch-ORDER case ("a tier that is both
  # mid-merge and ahead takes the mid-merge branch"): move_tier_off_pin leaves
  # the tier ahead of its pin, so once the ahead branch exists this fixture
  # satisfies both predicates and only the order decides which answers. That
  # the fixture is ahead is asserted rather than left to the helper's name —
  # a later repoint of move_tier_off_pin would otherwise turn the ordering pin
  # vacuous in silence.
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
  # Nor the ahead branch's, which would mean it ran first.
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

