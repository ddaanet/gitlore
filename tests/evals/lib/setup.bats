#!/usr/bin/env bats

EVAL_LIB_DIR="$BATS_TEST_DIRNAME"
export EVAL_LIB_DIR

setup() {
  source "$EVAL_LIB_DIR/setup.sh"
}

teardown() {
  teardown_eval_repo
}

@test "setup_eval_repo creates EVAL_REPO with memory/MEMORY.md containing initial content" {
  setup_eval_repo "# Initial Memory"
  [ -f "$EVAL_REPO/memory/MEMORY.md" ]
  run grep "# Initial Memory" "$EVAL_REPO/memory/MEMORY.md"
  [ "$status" -eq 0 ]
}

@test "setup_eval_repo creates at least one memory commit" {
  setup_eval_repo "# Memory"
  run git -C "$EVAL_REPO/memory" log --oneline
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -ge 1 ]
}

@test "teardown_eval_repo removes EVAL_REPO" {
  setup_eval_repo "# Memory"
  local repo="$EVAL_REPO"
  teardown_eval_repo
  [ ! -d "$repo" ]
}
