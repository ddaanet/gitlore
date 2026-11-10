#!/usr/bin/env bats
# scripts/add-tier.sh — the clean-store check that licenses D71's canned commit
# sees every untracked file whatever the user's status config, and a mount into
# a memory store holding a prepared merge is refused before anything is written.
# Each @test is its own subshell; per-test exports are consumed within that same
# test, so SC2030/SC2031 are false positives here.
# shellcheck disable=SC2030,SC2031
bats_require_minimum_version 1.5.0

load helpers/setup
load helpers/fixtures
load helpers/tier-fixtures
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
  [ ! -f memory/.gitmodules ] || ! grep -qF ddaanet memory/.gitmodules
  [ ! -f memory/.gitlore-tiers ] || ! grep -qx ddaanet memory/.gitlore-tiers
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
