#!/usr/bin/env bats

load helpers/setup

@test "gitlore_say_for_agent_or_user prints agent text when CLAUDECODE set" {
  CLAUDECODE=1 run gitlore_say_for_agent_or_user "AGENT MESSAGE" "USER MESSAGE"
  [ "$status" -eq 0 ]
  [ "$output" = "AGENT MESSAGE" ]
}

@test "gitlore_say_for_agent_or_user prints user text when CLAUDECODE unset" {
  unset CLAUDECODE
  run gitlore_say_for_agent_or_user "AGENT MESSAGE" "USER MESSAGE"
  [ "$status" -eq 0 ]
  [ "$output" = "USER MESSAGE" ]
}
