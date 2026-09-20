#!/usr/bin/env bats
# scripts/add-tier.sh — mount (or create then mount) a memory tier. D17 3-iii.
# Intent-file parsing, validation, and url transport bounds.
# Each @test is its own subshell; per-test exports are consumed within that same
# test, so SC2030/SC2031 are false positives here.
# shellcheck disable=SC2030,SC2031
bats_require_minimum_version 1.5.0

load helpers/setup
load helpers/fixtures
load helpers/tier-fixtures
load helpers/add-tier

# --- intent parsing --------------------------------------------------------

@test "add-tier: a description containing '=' and spaces survives parsing" {
  make_parent_with_memory
  bare=$(make_tier_remote ddaanet)
  write_intent "mode=mount" "name=ddaanet" "url=$bare" \
    "description=facts where a=b holds, spaces and all"

  run bash "$ADD_TIER"
  [ "$status" -eq 0 ]
}

@test "add-tier: an unknown intent key is an error, not a silent drop" {
  make_parent_with_memory
  bare=$(make_tier_remote ddaanet)
  write_intent "mode=mount" "name=ddaanet" "url=$bare" "descripton=typo"

  run bash "$ADD_TIER"
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown intent key"* ]]
  [ ! -e memory/ddaanet ]
}

@test "add-tier: a line that is not key=value is an error naming its number" {
  make_parent_with_memory
  write_intent "mode=mount" "just some prose"

  run bash "$ADD_TIER"
  [ "$status" -ne 0 ]
  [[ "$output" == *"line 2"* ]]
}

@test "add-tier: blank lines and comments are ignored" {
  make_parent_with_memory
  bare=$(make_tier_remote ddaanet)
  write_intent "# what this tier is for" "" "mode=mount" "name=ddaanet" "url=$bare"

  run bash "$ADD_TIER"
  [ "$status" -eq 0 ]
  [ -e memory/ddaanet/.git ]
}

@test "add-tier: a missing intent file fails without touching the store" {
  make_parent_with_memory
  run bash "$ADD_TIER"
  [ "$status" -ne 0 ]
  [[ "$output" == *"no add-tier intent file"* ]]
}

# --- validation ------------------------------------------------------------

@test "add-tier: an unknown mode is refused" {
  make_parent_with_memory
  write_intent "mode=borrow" "name=ddaanet" "url=x"
  run bash "$ADD_TIER"
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown mode"* ]]
}

@test "add-tier: mount without a url is refused" {
  make_parent_with_memory
  write_intent "mode=mount" "name=ddaanet"
  run bash "$ADD_TIER"
  [ "$status" -ne 0 ]
  [[ "$output" == *"url="* ]]
}

@test "add-tier: create without a description is refused" {
  make_parent_with_memory
  write_intent "mode=create" "name=ddaanet" "url=x"
  run bash "$ADD_TIER"
  [ "$status" -ne 0 ]
  [[ "$output" == *"description="* ]]
}

@test "add-tier: a name containing a slash is refused" {
  make_parent_with_memory
  write_intent "mode=mount" "name=org/ddaanet" "url=x"
  run bash "$ADD_TIER"
  [ "$status" -ne 0 ]
  [[ "$output" == *"slash"* ]]
}

@test "add-tier: a name containing whitespace is refused (the manifest could never list it)" {
  make_parent_with_memory
  write_intent "mode=mount" "name=two words" "url=x"
  run bash "$ADD_TIER"
  [ "$status" -ne 0 ]
  [[ "$output" == *"whitespace"* ]]
  [ ! -e "memory/two words" ]
}

@test "add-tier: re-mounting an already-mounted tier is refused" {
  make_parent_with_memory
  make_tier_in_memory ddaanet
  write_intent "mode=mount" "name=ddaanet" "url=$TMP_REPO/.bare-ddaanet.git"

  run bash "$ADD_TIER"
  [ "$status" -ne 0 ]
  [[ "$output" == *"already"* ]]
}

@test "add-tier: a name whose directory already exists is refused" {
  make_parent_with_memory
  mkdir memory/ddaanet
  write_intent "mode=mount" "name=ddaanet" "url=x"
  run bash "$ADD_TIER"
  [ "$status" -ne 0 ]
  [[ "$output" == *"already exists"* ]]
}

# --- url transport bounds -------------------------------------------------
#
# git's own protocol.ext.allow already defaults to `never` (2.47.3 refuses with
# "transport 'ext' not allowed"), so these pin the guard that makes the bound
# hold regardless of the user's git config — the hook runs outside the agent's
# sandbox, with network.

@test "add-tier: an ext:: transport-helper url is refused before git is reached" {
  make_parent_with_memory
  write_intent "mode=mount" "name=ddaanet" "url=ext::sh -c 'touch $TMP_REPO/PWNED'"

  run bash "$ADD_TIER"
  [ "$status" -ne 0 ]
  [[ "$output" == *"transport helper"* ]]
  [ ! -e "$TMP_REPO/PWNED" ]
  [ ! -e memory/ddaanet ]
}

@test "add-tier: an unknown url scheme is refused" {
  make_parent_with_memory
  write_intent "mode=mount" "name=ddaanet" "url=ftp://example.com/repo.git"
  run bash "$ADD_TIER"
  [ "$status" -ne 0 ]
  [[ "$output" == *"scheme"* ]]
}

@test "add-tier: a url starting with '-' is refused (git would read it as an option)" {
  make_parent_with_memory
  write_intent "mode=mount" "name=ddaanet" "url=--upload-pack=touch"
  run bash "$ADD_TIER"
  [ "$status" -ne 0 ]
  [[ "$output" == *"option"* ]]
}

@test "add-tier: create refuses a transport-helper url before pushing to it" {
  make_parent_with_memory
  write_intent "mode=create" "name=orgwide" "url=ext::sh -c 'touch $TMP_REPO/PWNED'" \
    "description=org facts"
  run bash "$ADD_TIER"
  [ "$status" -ne 0 ]
  [[ "$output" == *"transport helper"* ]]
  [ ! -e "$TMP_REPO/PWNED" ]
}

@test "add-tier: the ordinary remote spellings are accepted" {
  make_parent_with_memory
  # Reaching git is enough — these must fail on the network/path, not the
  # guard. A closed local port refuses instantly; a DNS-based unreachable
  # host (example.invalid) can stall for 10+ seconds per scheme behind a
  # proxying sandbox, which made this loop the suite's slowest single test.
  for u in "https://127.0.0.1:1/x.git" "ssh://git@127.0.0.1:1/x.git" \
           "git@127.0.0.1:x.git" "git://127.0.0.1:1/x.git"; do
    write_intent "mode=mount" "name=t" "url=$u"
    run bash "$ADD_TIER"
    [ "$status" -ne 0 ]                       # connection refused, of course
    [[ "$output" == *"submodule add failed"* ]]   # …but it got past the guard
  done
}

@test "add-tier: a bad url fails with git's own message and mounts nothing" {
  make_parent_with_memory
  write_intent "mode=mount" "name=ddaanet" "url=$TMP_REPO/.no-such-remote.git"

  run bash "$ADD_TIER"
  [ "$status" -ne 0 ]
  [[ "$output" == *"submodule add failed"* ]]
  [ ! -e memory/ddaanet ]
  run git config --file memory/.gitmodules --get submodule.ddaanet.path
  [ "$status" -ne 0 ]
}

@test "add-tier: refuses when the repo has no memory submodule" {
  # Bare repo from setup_tmp_repo, no memory.
  mkdir -p .claude
  printf 'mode=mount\nname=x\nurl=y\n' > .claude/gitlore-add-tier
  run bash "$ADD_TIER"
  [ "$status" -ne 0 ]
  [[ "$output" == *"memory submodule"* ]]
}

