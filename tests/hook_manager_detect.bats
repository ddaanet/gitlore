#!/usr/bin/env bats

load helpers/setup
load helpers/fixtures

DETECT="$PLUGIN_ROOT/scripts/hook-manager/detect.sh"

setup()    { setup_tmp_repo; }
teardown() { teardown_tmp_repo; }

@test "detects lefthook via lefthook.yml" {
  : > lefthook.yml
  run bash "$DETECT"
  [ "$output" = "lefthook" ]
}

@test "detects husky via .husky directory" {
  mkdir .husky
  run bash "$DETECT"
  [ "$output" = "husky" ]
}

@test "detects overcommit via .overcommit.yml" {
  : > .overcommit.yml
  run bash "$DETECT"
  [ "$output" = "overcommit" ]
}

@test "defaults to direct with a hand-rolled .git/hooks/pre-commit (no manager)" {
  printf '#!/bin/sh\n' > .git/hooks/pre-commit
  chmod +x .git/hooks/pre-commit
  run bash "$DETECT"
  [ "$output" = "direct" ]
}

@test "defaults to direct when no hook manager is detected" {
  run bash "$DETECT"
  [ "$output" = "direct" ]
}

@test "reports multi when both lefthook and husky are present" {
  : > lefthook.yml
  mkdir .husky
  run bash "$DETECT"
  [[ "$output" == multi:* ]]
  [[ "$output" == *lefthook* ]]
  [[ "$output" == *husky* ]]
}
