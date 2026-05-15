#!/usr/bin/env bats

load helpers/setup
load helpers/fixtures

setup()    { setup_tmp_repo; }
teardown() { teardown_tmp_repo; }

@test "smoke: harness creates a clean parent repo" {
  [ -d "$TMP_REPO/.git" ]
  run git rev-parse --is-inside-work-tree
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "smoke: fixture creates parent with memory submodule" {
  make_parent_with_memory
  [ -f .gitmodules ]
  run git config --file .gitmodules submodule.gitlore-memory.path
  [ "$status" -eq 0 ]
  [ "$output" = "memory" ]
}
