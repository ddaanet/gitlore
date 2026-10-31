#!/usr/bin/env bats
# scripts/add-tier.sh — D71: on a clean memory store the mount commits itself
# under a canned message and stages the moved memory gitlink in the parent; a
# store with pending work gets no commit and the mount stays staged.
# Each @test is its own subshell; per-test exports are consumed within that same
# test, so SC2030/SC2031 are false positives here.
# shellcheck disable=SC2030,SC2031
bats_require_minimum_version 1.5.0

load helpers/setup
load helpers/fixtures
load helpers/tier-fixtures
load helpers/add-tier

# The phrase commands/add-tier.md keys its hand-off to gitlore:commit on.
STAGED_PHRASE="left staged for the next gitlore:commit"

# The paths memory's HEAD commit touches, one per line, sorted.
head_paths() {
  git -C memory show --name-only --format= HEAD | LC_ALL=C sort
}

# --- clean store: the canned commit -----------------------------------------

@test "add-tier commit: the fixture store is clean before the call" {
  make_parent_with_memory
  [ -z "$(git -C memory status --porcelain)" ]
}

@test "add-tier commit: a clean store gets one canned commit on live carrying exactly the mount" {
  make_parent_with_memory
  before=$(git -C memory rev-parse HEAD)
  bare=$(make_tier_remote ddaanet)
  write_intent "mode=mount" "name=ddaanet" "url=$bare"

  run bash "$ADD_TIER" < "$INTENT"
  [ "$status" -eq 0 ]

  [ "$(git -C memory rev-list --count "$before..HEAD")" = 1 ]
  [ "$(git -C memory rev-parse HEAD)" = "$(git -C memory rev-parse live)" ]
  [ "$(git -C memory log -1 --format=%B)" = \
    "$(printf 'mount ddaanet tier from %s\n\norg-wide facts for ddaanet projects' "$bare")" ]
  [ "$(head_paths)" = "$(printf '.gitlore-tiers\n.gitmodules\nddaanet')" ]
  [ -z "$(git -C memory status --porcelain)" ]
  [ -z "$(git -C memory/ddaanet status --porcelain)" ]
  [ "$(git -C memory rev-parse HEAD:ddaanet)" = "$(git -C memory/ddaanet rev-parse HEAD)" ]
}

@test "add-tier commit: a tier whose live carries facts adds the recomposed MEMORY.md to the commit" {
  make_parent_with_memory
  bare=$(make_tier_remote ddaanet)
  push_tier_fact ddaanet "- [x](x.md) — from live" >/dev/null
  write_intent "mode=mount" "name=ddaanet" "url=$bare"

  run bash "$ADD_TIER" < "$INTENT"
  [ "$status" -eq 0 ]

  [ "$(head_paths)" = "$(printf '.gitlore-tiers\n.gitmodules\nMEMORY.md\nddaanet')" ]
  grep -qF -- '- [x](ddaanet/x.md) — from live' memory/MEMORY.md
  [ -z "$(git -C memory status --porcelain)" ]
}

@test "add-tier commit: the call reports the compose and the post-compose size on stdout" {
  make_parent_with_memory
  bare=$(make_tier_remote ddaanet)
  push_tier_fact ddaanet "- [x](x.md) — from live" >/dev/null
  write_intent "mode=mount" "name=ddaanet" "url=$bare"
  # Any index is past a 10-byte cutoff, so the size line is the loud arm.
  export GITLORE_INDEX_LOADER_CUTOFF_BYTES=10

  run bash "$ADD_TIER" < "$INTENT"
  [ "$status" -eq 0 ]

  [[ "$output" == *"recomposed tier pointers"* ]]
  [[ "$output" == *"active-tier set changed"* ]]
  # Measured after the compose: the byte count is the composed file's.
  bytes=$(wc -c < memory/MEMORY.md | tr -d ' ')
  [[ "$output" == *"memory/MEMORY.md is $bytes bytes after the mount"* ]]
}

@test "add-tier commit: create mode commits as 'create <name> tier at <url>' with the description as body" {
  make_parent_with_memory
  before=$(git -C memory rev-parse HEAD)
  git init -q --bare "$TMP_REPO/.new-tier.git"
  write_intent "mode=create" "name=orgwide" "url=$TMP_REPO/.new-tier.git" \
    "description=Cross-project facts shared by all org repositories"

  run bash "$ADD_TIER" < "$INTENT"
  [ "$status" -eq 0 ]

  [ "$(git -C memory rev-list --count "$before..HEAD")" = 1 ]
  [ "$(git -C memory log -1 --format=%s)" = "create orgwide tier at $TMP_REPO/.new-tier.git" ]
  [ "$(git -C memory log -1 --format=%b)" = \
    "Cross-project facts shared by all org repositories" ]
  [ "$(head_paths)" = "$(printf '.gitlore-tiers\n.gitmodules\norgwide')" ]
  [ "$(git -C memory rev-parse HEAD)" = "$(git -C memory rev-parse live)" ]
}

# --- clean store: the parent gitlink ----------------------------------------

@test "add-tier commit: the moved memory gitlink is staged in the parent" {
  make_parent_with_memory
  bare=$(make_tier_remote ddaanet)
  write_intent "mode=mount" "name=ddaanet" "url=$bare"
  # Not staged before the call, so the staging below is the script's.
  [ -z "$(git diff --cached --name-only)" ]

  run bash "$ADD_TIER" < "$INTENT"
  [ "$status" -eq 0 ]

  [ "$(git diff --cached --name-only)" = memory ]
  [ "$(git rev-parse :memory)" = "$(git -C memory rev-parse HEAD)" ]
}

# --- refusals leave the store alone -----------------------------------------

@test "add-tier commit: a refused url commits nothing and mounts nothing" {
  make_parent_with_memory
  before=$(git -C memory rev-parse HEAD)
  write_intent "mode=mount" "name=ddaanet" "url=ext::sh -c 'touch $TMP_REPO/PWNED'"

  run bash "$ADD_TIER" < "$INTENT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"transport helper"* ]]

  [ ! -e "$TMP_REPO/PWNED" ]
  [ ! -e memory/ddaanet ]
  [ "$(git -C memory rev-parse HEAD)" = "$before" ]
  [ -z "$(git -C memory status --porcelain)" ]
  [ -z "$(git diff --cached --name-only)" ]
}

# --- pending work: no canned commit -----------------------------------------

@test "add-tier commit: a modified MEMORY.md means no commit, the mount staged, and the report says so" {
  make_parent_with_memory
  printf -- '- [local](local.md) — unapproved edit\n' >> memory/MEMORY.md
  before=$(git -C memory rev-parse HEAD)
  bare=$(make_tier_remote ddaanet)
  write_intent "mode=mount" "name=ddaanet" "url=$bare"

  run bash "$ADD_TIER" < "$INTENT"
  [ "$status" -eq 0 ]

  [ "$(git -C memory rev-parse HEAD)" = "$before" ]
  staged=$(git -C memory diff --cached --name-only)
  grep -qxF .gitmodules <<<"$staged"
  grep -qxF ddaanet <<<"$staged"
  [ -e memory/ddaanet/.git ]
  grep -qx ddaanet memory/.gitlore-tiers
  grep -qF -- 'unapproved edit' memory/MEMORY.md
  [[ "$output" == *"$STAGED_PHRASE"* ]]
  [ -z "$(git diff --cached --name-only)" ]
}

@test "add-tier commit: an untracked fact file means no commit, the mount staged, and the report says so" {
  make_parent_with_memory
  printf -- '---\nname: orphan\ndescription: ""\n---\n\nbody\n' > memory/orphan.md
  before=$(git -C memory rev-parse HEAD)
  bare=$(make_tier_remote ddaanet)
  write_intent "mode=mount" "name=ddaanet" "url=$bare"

  run bash "$ADD_TIER" < "$INTENT"
  [ "$status" -eq 0 ]

  [ "$(git -C memory rev-parse HEAD)" = "$before" ]
  staged=$(git -C memory diff --cached --name-only)
  grep -qxF .gitmodules <<<"$staged"
  grep -qxF ddaanet <<<"$staged"
  [ -f memory/orphan.md ]
  [[ "$output" == *"$STAGED_PHRASE"* ]]
  [ -z "$(git diff --cached --name-only)" ]
}

@test "add-tier commit: a clean-store mount does not say the mount was left staged" {
  make_parent_with_memory
  bare=$(make_tier_remote ddaanet)
  write_intent "mode=mount" "name=ddaanet" "url=$bare"

  run bash "$ADD_TIER" < "$INTENT"
  [ "$status" -eq 0 ]
  [ -e memory/ddaanet/.git ]
  [[ "$output" != *"$STAGED_PHRASE"* ]]
}
