#!/usr/bin/env bats
# scripts/add-tier.sh — the clean-store check that licenses D71's canned commit
# sees every untracked file whatever the user's status config, and a mount into
# a memory store, or a mounted tier, holding a prepared merge, or a mounted tier off its pin, is refused before anything is written.
# Each @test is its own subshell; per-test exports are consumed within that same
# test, so SC2030/SC2031 are false positives here.
# shellcheck disable=SC2030,SC2031
bats_require_minimum_version 1.5.0

load helpers/setup
load helpers/fixtures
load helpers/tier-fixtures
load helpers/divergence-fixtures
load helpers/tier-divergence
load helpers/stub-synth
load helpers/merge-memory
load helpers/take-order
load helpers/gh-mock
load helpers/add-tier

STAGED_PHRASE="left staged for the next gitlore:commit"

@test "add-tier: status.showUntrackedFiles=no still keeps an untracked note out of a canned commit" {
  make_parent_with_memory
  git -C memory config status.showUntrackedFiles no
  printf -- '---\nname: orphan\ndescription: ""\n---\n\nbody\n' > memory/orphan.md
  # The config hides the note from a bare porcelain status.
  [ -z "$(git -C memory status --porcelain)" ]
  before=$(git -C memory rev-parse HEAD)
  bare=$(make_tier_remote ddaanet)
  write_intent "mode=mount" "name=ddaanet" "url=$bare"

  run bash "$ADD_TIER" < "$INTENT"
  [ "$status" -eq 0 ]

  [ "$(git -C memory rev-parse HEAD)" = "$before" ]
  run git -C memory ls-files --error-unmatch orphan.md
  [ "$status" -ne 0 ]
  [ -f memory/orphan.md ]
  [ -e memory/ddaanet/.git ]
}

@test "add-tier: status.showUntrackedFiles=no still reports the mount as left staged" {
  make_parent_with_memory
  git -C memory config status.showUntrackedFiles no
  printf 'note\n' > memory/orphan.md
  bare=$(make_tier_remote ddaanet)
  write_intent "mode=mount" "name=ddaanet" "url=$bare"

  run bash "$ADD_TIER" < "$INTENT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"$STAGED_PHRASE"* ]]
}

# Assert the refusal wrote nothing: no checkout, no registration, no manifest
# line, no staged change beyond what the merge itself staged.
assert_nothing_mounted() {
  [ ! -e memory/ddaanet ]
  if [ -f memory/.gitmodules ] && grep -qF ddaanet memory/.gitmodules; then
    echo "memory/.gitmodules registers ddaanet" >&2
    return 1
  fi
  if [ -f memory/.gitlore-tiers ] && grep -qx ddaanet memory/.gitlore-tiers; then
    echo "memory/.gitlore-tiers lists ddaanet" >&2
    return 1
  fi
  [ "$(git -C memory rev-parse HEAD)" = "$before" ]
}

@test "add-tier: a memory store with MERGE_HEAD set refuses the mount and names /gitlore:resolve" {
  make_parent_with_memory
  # A side commit adding a file, so the merge stages work and the store reads
  # as pending: the arm that used to exit 0 with the mount in the merge's index.
  blob=$(printf 'local only\n' | git -C memory hash-object -w --stdin)
  tree=$({ git -C memory ls-tree HEAD; printf '100644 blob %s\tlocal-only.md\n' "$blob"; } |
    git -C memory mktree)
  side=$(git -C memory commit-tree "$tree" -p HEAD -m side)
  git -C memory merge -q --no-ff --no-commit "$side"
  git -C memory rev-parse -q --verify MERGE_HEAD >/dev/null
  before=$(git -C memory rev-parse HEAD)
  bare=$(make_tier_remote ddaanet)
  write_intent "mode=mount" "name=ddaanet" "url=$bare"

  run bash "$ADD_TIER" < "$INTENT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"/gitlore:resolve"* ]]
  assert_nothing_mounted
  git -C memory rev-parse -q --verify MERGE_HEAD >/dev/null
}

@test "add-tier: a memory store holding only a gitlore merge-state file refuses the mount" {
  make_parent_with_memory
  printf '{}\n' > "$(git -C memory rev-parse --git-path gitlore-merge-state)"
  before=$(git -C memory rev-parse HEAD)
  bare=$(make_tier_remote ddaanet)
  write_intent "mode=mount" "name=ddaanet" "url=$bare"

  run bash "$ADD_TIER" < "$INTENT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"/gitlore:resolve"* ]]
  assert_nothing_mounted
}

# A mounted tier left mid-merge the way production leaves it: its live branch
# moved, a local tier fact committed, and the merge gate prepared the merge.
make_mid_merge_tier() {
  make_parent_with_memory
  mount_tier_at_live ddaanet
  set_tier_manifest ddaanet
  advance_branch_with_file memory/ddaanet live other.md body "sideways" live
  echo "- [org fact](f.md) — ours" >> memory/ddaanet/MEMORY.md
  gitlore_compose memory >/dev/null
  commit_sections "memory: record the org fact"
  merge_gate || true
  [ -n "$(git -C memory/ddaanet rev-parse -q --verify MERGE_HEAD)" ]
}

# Capture what the refusal must leave alone, then check it after the run.
snapshot_memory_root() {
  cp memory/.gitlore-tiers "$BATS_TEST_TMPDIR/tiers.before"
  cp memory/.gitmodules "$BATS_TEST_TMPDIR/modules.before"
  git -C memory status --porcelain > "$BATS_TEST_TMPDIR/status.before"
}

assert_second_tier_refused() {
  [[ "$output" == *"/gitlore:resolve"* ]]
  [[ "$output" == *"merge"* ]]
  [[ "$output" != *"mounted at"* ]]
  [ ! -e memory/second ]
  cmp memory/.gitlore-tiers "$BATS_TEST_TMPDIR/tiers.before"
  cmp memory/.gitmodules "$BATS_TEST_TMPDIR/modules.before"
  git -C memory status --porcelain > "$BATS_TEST_TMPDIR/status.after"
  cmp "$BATS_TEST_TMPDIR/status.after" "$BATS_TEST_TMPDIR/status.before"
  git -C memory/ddaanet rev-parse -q --verify MERGE_HEAD >/dev/null
}

@test "add-tier: a mounted tier holding a prepared merge refuses a mount and names /gitlore:resolve" {
  make_mid_merge_tier
  bare=$(make_tier_remote second)
  write_intent "mode=mount" "name=second" "url=$bare"
  snapshot_memory_root

  run bash "$ADD_TIER" < "$INTENT"
  [ "$status" -ne 0 ]
  assert_second_tier_refused
}

@test "add-tier: a mounted tier holding a prepared merge refuses a create before any remote is written" {
  make_mid_merge_tier
  git init -q --bare "$TMP_REPO/.new-tier.git"
  write_intent "mode=create" "name=second" "url=$TMP_REPO/.new-tier.git" \
    "description=Second tier"
  snapshot_memory_root

  run bash "$ADD_TIER" < "$INTENT"
  [ "$status" -ne 0 ]
  assert_second_tier_refused
  [ -z "$(git -C "$TMP_REPO/.new-tier.git" for-each-ref)" ]
}

# --- a mounted tier off the commit the memory store records for it ---

# The memory remote take_base_store publishes to; the suite setup does not set it.
pins_env() {
  MEMORY_REMOTE="$TMP_REPO/.memory-remote.git"
  export MEMORY_REMOTE
}

# ddaanet left ahead of its pin the way production leaves it: the tier merge
# lands through resolve's continuation, which does not record the tier.
make_ahead_tier_after_resolve() {
  make_mid_merge_tier
  git -C memory/ddaanet add -A
  run bash "$RESOLVE" continue-after-merge
  [ "$status" -eq 0 ]
  [ -z "$(git -C memory/ddaanet rev-parse -q --verify MERGE_HEAD)" ]
  [ "$(git -C memory/ddaanet rev-parse HEAD)" != "$(git -C memory rev-parse :ddaanet)" ]
}

make_behind_tier() {
  pins_env
  take_base_store ddaanet
  local_tier_commit_recorded ddaanet loc.md
  git -C memory/ddaanet checkout -q --detach HEAD~1
}

make_forked_tier() {
  make_behind_tier
  seed_tier_bullet ddaanet hand.md "hand fact"
  git -C memory/ddaanet add -A
  git -C memory/ddaanet commit -qm hand
}

# Everything the refusal must leave alone, taken before the run.
snapshot_pin_state() {
  snapshot_memory_root
  git -C memory rev-parse HEAD > "$BATS_TEST_TMPDIR/head.before"
  git -C memory rev-parse :ddaanet > "$BATS_TEST_TMPDIR/pin.before"
  git -C memory/ddaanet rev-parse HEAD > "$BATS_TEST_TMPDIR/tierhead.before"
}

# $1: a stable phrase of the pin state's refusal.
assert_pin_refusal() {
  [[ "$output" == *"ddaanet"* ]]
  [[ "$output" == *"is checked out at"* ]]
  [[ "$output" == *"/gitlore:merge"* ]]
  [[ "$output" == *"$1"* ]]
  [[ "$output" != *"mounted at"* ]]
  [[ "$output" != *"activated"* ]]
  [ ! -e memory/second ]
  cmp memory/.gitlore-tiers "$BATS_TEST_TMPDIR/tiers.before"
  cmp memory/.gitmodules "$BATS_TEST_TMPDIR/modules.before"
  git -C memory status --porcelain > "$BATS_TEST_TMPDIR/status.after"
  cmp "$BATS_TEST_TMPDIR/status.after" "$BATS_TEST_TMPDIR/status.before"
  [ "$(git -C memory rev-parse HEAD)" = "$(cat "$BATS_TEST_TMPDIR/head.before")" ]
  [ "$(git -C memory rev-parse :ddaanet)" = "$(cat "$BATS_TEST_TMPDIR/pin.before")" ]
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$(cat "$BATS_TEST_TMPDIR/tierhead.before")" ]
}

@test "add-tier: a mounted tier ahead of its pin, as resolve leaves it, refuses a mount" {
  make_ahead_tier_after_resolve
  bare=$(make_tier_remote second)
  write_intent "mode=mount" "name=second" "url=$bare"
  snapshot_pin_state

  run bash "$ADD_TIER" < "$INTENT"
  [ "$status" -ne 0 ]
  assert_pin_refusal "ahead of the commit"
}

@test "add-tier: a mounted tier behind its pin refuses a mount" {
  make_behind_tier
  bare=$(make_tier_remote second)
  write_intent "mode=mount" "name=second" "url=$bare"
  snapshot_pin_state

  run bash "$ADD_TIER" < "$INTENT"
  [ "$status" -ne 0 ]
  assert_pin_refusal "behind the commit"
}

@test "add-tier: a mounted tier forked beside its pin refuses a mount" {
  make_forked_tier
  bare=$(make_tier_remote second)
  write_intent "mode=mount" "name=second" "url=$bare"
  snapshot_pin_state

  run bash "$ADD_TIER" < "$INTENT"
  [ "$status" -ne 0 ]
  assert_pin_refusal "beside the commit"
}

@test "add-tier: a mounted tier ahead of its pin refuses a create before gh or any remote is touched" {
  make_ahead_tier_after_resolve
  isolate_home
  install_gh_mock
  export GH_MOCK_LOG="$BATS_TEST_TMPDIR/gh.log"
  export GH_MOCK_STDOUT_API_USER="alice"
  export GH_MOCK_REMOTE_URL="git@github.com:alice/second-memory.git"
  bare="$TMP_REPO/.new-tier.git"
  git init -q -b main --bare "$bare"
  git config --global "url.$bare.insteadOf" "$GH_MOCK_REMOTE_URL"
  write_intent "mode=create" "name=second" "description=Second tier"
  snapshot_pin_state

  run bash "$ADD_TIER" < "$INTENT"
  [ "$status" -ne 0 ]
  assert_pin_refusal "ahead of the commit"
  [ ! -s "$GH_MOCK_LOG" ]
  [ -z "$(git -C "$bare" for-each-ref)" ]
}

# Control, green before and after the fix: the compose yields a tier off its pin
# when the root is dirty and forked from its live (the merge that would fix it
# would itself refuse), so the mount goes through.
@test "add-tier: an ahead tier under a dirty root forked from live still mounts" {
  pins_env
  take_base_store ddaanet
  local_tier_commit_recorded ddaanet loc.md
  move_tier_off_pin_into_live ddaanet
  git -C memory branch -f live "$(git -C memory commit-tree "HEAD^{tree}" -p HEAD~1 -m elsewhere)"
  printf -- '---\nname: dirty\ndescription: ""\n---\n\nbody\n' > memory/dirty.md
  seed_root_bullet dirty.md "an uncommitted root fact"
  bare=$(make_tier_remote second)
  write_intent "mode=mount" "name=second" "url=$bare"

  run bash "$ADD_TIER" < "$INTENT"
  [ "$status" -eq 0 ]
  [ -e memory/second/.git ]
  grep -qx second memory/.gitlore-tiers
}
