#!/usr/bin/env bats

# shellcheck source=tests/helpers/run-asserts.bash
source "$BATS_TEST_DIRNAME/../../helpers/run-asserts.bash"

EVAL_LIB_DIR="$BATS_TEST_DIRNAME"
export EVAL_LIB_DIR

setup() {
  # shellcheck disable=SC1091  # dynamic path resolved at runtime; not followable here
  source "$EVAL_LIB_DIR/setup.sh"
}

teardown() {
  teardown_eval_repo
}

@test "setup_eval_repo creates EVAL_REPO with memory/MEMORY.md containing initial content" {
  setup_eval_repo "# Initial Memory"
  [ -f "$EVAL_REPO/memory/MEMORY.md" ]
  assert_grep "# Initial Memory" "$EVAL_REPO/memory/MEMORY.md"
}

@test "setup_eval_repo appends the plugin bin to PATH, last, so gitlore-commit resolves" {
  setup_eval_repo "# Memory"
  [ "${PATH##*:}" = "$PLUGIN_ROOT/bin" ]
  [ -x "$PLUGIN_ROOT/bin/gitlore-commit" ]
}

@test "setup_eval_repo copies the commit skill in as the project skill the eval names commit" {
  setup_eval_repo "# Memory"
  [ -f "$EVAL_REPO/.claude/skills/commit/SKILL.md" ]
}

@test "setup_eval_repo creates at least one memory commit" {
  setup_eval_repo "# Memory"
  run git -C "$EVAL_REPO/memory" log --oneline
  assert_ok
  [ "${#lines[@]}" -ge 1 ]
}

@test "teardown_eval_repo removes EVAL_REPO" {
  setup_eval_repo "# Memory"
  local repo="$EVAL_REPO"
  teardown_eval_repo
  [ ! -d "$repo" ]
}
