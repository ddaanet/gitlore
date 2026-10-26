#!/usr/bin/env bats
# scripts/add-tier.sh — the url a tier is recorded under in the memory store's
# tracked `.gitmodules`, and the private-tier-under-public-parent warning.
# The tier's own remote keeps the url it was given, so pushes stay on ssh; the
# `.gitmodules` entry is the https form, so an anonymous recursive clone needs
# no GitHub SSH key.
# Each @test is its own subshell; per-test exports are consumed within that same
# test, so SC2030/SC2031 are false positives here.
# $stderr is populated by bats `run --separate-stderr`; shellcheck cannot see it.
# shellcheck disable=SC2030,SC2031,SC2154
bats_require_minimum_version 1.5.0

load helpers/setup
load helpers/fixtures
load helpers/tier-fixtures
load helpers/add-tier
load helpers/gh-mock

# The suite's own setup, with a private HOME: the tests route github.com urls to
# local bare repos through a global `insteadOf`.
setup() {
  setup_tmp_repo
  isolate_home
  export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
  export GIT_CONFIG_COUNT=1
  export GIT_CONFIG_KEY_0=protocol.file.allow
  export GIT_CONFIG_VALUE_0=always
  install_gh_mock
  export GH_MOCK_STDOUT_API_USER="alice"
}

# Route git operations addressed to $1 (a url literal) to the bare repo $2.
# What git stores in config stays the literal.
route_to_bare() {
  git config --global "url.$2.insteadOf" "$1"
}

@test "add-tier: mounting by an ssh GitHub url records https in .gitmodules and keeps ssh on the tier" {
  make_parent_with_memory
  bare=$(make_tier_remote ddaanet)
  route_to_bare "git@github.com:acme/ddaanet-memory.git" "$bare"
  write_intent "mode=mount" "name=ddaanet" "url=git@github.com:acme/ddaanet-memory.git"

  run bash "$ADD_TIER"
  [ "$status" -eq 0 ]

  [ "$(git config --file memory/.gitmodules --get submodule.ddaanet.url)" = "https://github.com/acme/ddaanet-memory.git" ]
  [ "$(git -C memory/ddaanet config --get remote.origin.url)" = "git@github.com:acme/ddaanet-memory.git" ]
  # Staged, not just edited: `submodule add` staged the ssh form first, and the
  # rewrite has to reach the index the memory commit is built from.
  [ "$(git -C memory show :.gitmodules | git config --file - --get submodule.ddaanet.url)" = "https://github.com/acme/ddaanet-memory.git" ]
  git -C memory diff --quiet -- .gitmodules
}

@test "add-tier: mounting by an https url leaves it as given" {
  make_parent_with_memory
  bare=$(make_tier_remote ddaanet)
  route_to_bare "https://github.com/acme/ddaanet-memory.git" "$bare"
  write_intent "mode=mount" "name=ddaanet" "url=https://github.com/acme/ddaanet-memory.git"

  run bash "$ADD_TIER"
  [ "$status" -eq 0 ]
  [ "$(git config --file memory/.gitmodules --get submodule.ddaanet.url)" = "https://github.com/acme/ddaanet-memory.git" ]
  [ "$(git -C memory/ddaanet config --get remote.origin.url)" = "https://github.com/acme/ddaanet-memory.git" ]
}

@test "add-tier: mounting by a non-GitHub ssh url leaves it as given" {
  make_parent_with_memory
  bare=$(make_tier_remote ddaanet)
  route_to_bare "git@git.example.org:acme/ddaanet-memory.git" "$bare"
  write_intent "mode=mount" "name=ddaanet" "url=git@git.example.org:acme/ddaanet-memory.git"

  run bash "$ADD_TIER"
  [ "$status" -eq 0 ]
  [ "$(git config --file memory/.gitmodules --get submodule.ddaanet.url)" = "git@git.example.org:acme/ddaanet-memory.git" ]
}

@test "add-tier: a tier created through gh is recorded as https and kept ssh on the tier" {
  make_parent_with_memory
  git remote add origin "https://github.com/acme/project.git"
  export GH_MOCK_REMOTE_URL="git@github.com:alice/orgwide-memory.git"
  bare="$TMP_REPO/.new-tier.git"
  git init -q -b main --bare "$bare"
  route_to_bare "$GH_MOCK_REMOTE_URL" "$bare"
  write_intent "mode=create" "name=orgwide" "description=org facts"

  run bash "$ADD_TIER"
  [ "$status" -eq 0 ]

  [ "$(git config --file memory/.gitmodules --get submodule.orgwide.url)" = "https://github.com/alice/orgwide-memory.git" ]
  [ "$(git -C memory/orgwide config --get remote.origin.url)" = "git@github.com:alice/orgwide-memory.git" ]
  git -C "$bare" show-ref --verify --quiet refs/heads/live
}

@test "add-tier: warns once when a tier created --private is mounted under a public parent" {
  make_parent_with_memory
  git remote add origin "https://github.com/acme/project.git"
  export GH_MOCK_VISIBILITY_MAP='acme/project=PUBLIC'
  export GH_MOCK_REMOTE_URL="git@github.com:alice/orgwide-memory.git"
  bare="$TMP_REPO/.new-tier.git"
  git init -q -b main --bare "$bare"
  route_to_bare "$GH_MOCK_REMOTE_URL" "$bare"
  write_intent "mode=create" "name=orgwide" "description=org facts"

  run --separate-stderr bash "$ADD_TIER"
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$stderr" | grep -c 'is private but this repository is public')" -eq 1 ]
  [[ "$stderr" == *"git@github.com:alice/orgwide-memory.git"* ]]
}

@test "add-tier: a created tier under a private parent gets no warning" {
  make_parent_with_memory
  git remote add origin "https://github.com/acme/project.git"
  export GH_MOCK_VISIBILITY_MAP='acme/project=PRIVATE'
  export GH_MOCK_REMOTE_URL="git@github.com:alice/orgwide-memory.git"
  bare="$TMP_REPO/.new-tier.git"
  git init -q -b main --bare "$bare"
  route_to_bare "$GH_MOCK_REMOTE_URL" "$bare"
  write_intent "mode=create" "name=orgwide" "description=org facts"

  run --separate-stderr bash "$ADD_TIER"
  [ "$status" -eq 0 ]
  [[ "$stderr" != *"is private but this repository is public"* ]]
}

@test "add-tier: mounting a private tier by url under a public parent warns" {
  make_parent_with_memory
  git remote add origin "https://github.com/acme/project.git"
  export GH_MOCK_VISIBILITY_MAP=$'acme/project=PUBLIC\nacme/ddaanet-memory=PRIVATE'
  bare=$(make_tier_remote ddaanet)
  route_to_bare "git@github.com:acme/ddaanet-memory.git" "$bare"
  write_intent "mode=mount" "name=ddaanet" "url=git@github.com:acme/ddaanet-memory.git"

  run --separate-stderr bash "$ADD_TIER"
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$stderr" | grep -c 'is private but this repository is public')" -eq 1 ]
}

@test "add-tier: mounting a public tier by url under a public parent stays silent" {
  make_parent_with_memory
  git remote add origin "https://github.com/acme/project.git"
  export GH_MOCK_VISIBILITY_MAP=$'acme/project=PUBLIC\nacme/ddaanet-memory=PUBLIC'
  bare=$(make_tier_remote ddaanet)
  route_to_bare "git@github.com:acme/ddaanet-memory.git" "$bare"
  write_intent "mode=mount" "name=ddaanet" "url=git@github.com:acme/ddaanet-memory.git"

  run --separate-stderr bash "$ADD_TIER"
  [ "$status" -eq 0 ]
  [[ "$stderr" != *"is private but this repository is public"* ]]
}

@test "add-tier: a tier whose visibility cannot be read stays silent under a public parent" {
  make_parent_with_memory
  git remote add origin "https://github.com/acme/project.git"
  export GH_MOCK_VISIBILITY_MAP='acme/project=PUBLIC'
  bare=$(make_tier_remote ddaanet)
  route_to_bare "git@github.com:acme/ddaanet-memory.git" "$bare"
  write_intent "mode=mount" "name=ddaanet" "url=git@github.com:acme/ddaanet-memory.git"

  run --separate-stderr bash "$ADD_TIER"
  [ "$status" -eq 0 ]
  [[ "$stderr" != *"is private but this repository is public"* ]]
}
