#!/usr/bin/env bats
# The hook-wiring sentinel's empty-first-line arm: a notice on systemMessage,
# since stderr reaches nobody on exit 0 (D14), and none of the retired "replay"
# wording.
# $stderr is populated by bats `run --separate-stderr`; shellcheck cannot see it.
# shellcheck disable=SC2154
bats_require_minimum_version 1.5.0

load helpers/setup
load helpers/fixtures
load helpers/divergence-fixtures
load helpers/cc-hook-session-start

@test "an empty sentinel line gets a systemMessage notice, not stderr" {
  make_parent_with_memory
  enable_gitlore
  printf '\n' > .claude/gitlore-hook-setup
  run --separate-stderr bash "$SESSION_START"
  [ "$status" -eq 0 ]
  jq -e '.systemMessage // "" | contains(".claude/gitlore-hook-setup has an empty first line")' <<<"$output"
  jq -e '.systemMessage // "" | contains("replay") | not' <<<"$output"
  [[ "$stderr" != *"sentinel"* ]]
}
