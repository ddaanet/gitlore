#!/usr/bin/env bats
# The scenario files and the fixtures they name, checked without the claude CLI:
# every scenario's setup and assert resolve to executable scripts, and the
# fact-edit scenario's fixture leaves the store in the state its prompt assumes.

# shellcheck source=tests/helpers/run-asserts.bash
source "$BATS_TEST_DIRNAME/../../helpers/run-asserts.bash"

EVAL_LIB_DIR="$BATS_TEST_DIRNAME"
EVALS_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"

setup() {
  # shellcheck disable=SC1091  # dynamic path resolved at runtime
  source "$EVAL_LIB_DIR/setup.sh"
}

teardown() {
  teardown_eval_repo
}

@test "every scenario names a setup and an assertion that exist and are executable" {
  local f setup_name assert_name n=0
  for f in "$EVALS_DIR"/scenarios/*.json; do
    n=$((n + 1))
    jq -e . "$f" >/dev/null
    setup_name=$(jq -r '.setup // ""' "$f")
    assert_name=$(jq -r '.assert // "memory-commit"' "$f")
    [ -z "$setup_name" ] || [ -x "$EVALS_DIR/setups/$setup_name.sh" ]
    [ -x "$EVALS_DIR/asserts/$assert_name.sh" ]
  done
  [ "$n" -ge 5 ]
}

@test "no scenario names the retired message file, trigger file or bare commit script" {
  run grep -l -e 'commit-memory\.sh' -e 'gitlore-commit-msg' -e 'gitlore-commit-memory' -e 'commitCommand' \
    "$EVALS_DIR"/scenarios/*.json
  [ "$status" -eq 1 ]
}

@test "the fact-edit scenario grades the memory-commit flow with a two-turn approval and a rubric on cause and body" {
  f="$EVALS_DIR/scenarios/06-fact-edit-reason.json"
  [ -f "$f" ]
  [ "$(jq -r '.setup' "$f")" = "fact-edit" ]
  [ "$(jq -r '.assert' "$f")" = "memory-commit" ]
  [ -n "$(jq -r '.approval_message // ""' "$f")" ]
  rubric=$(jq -r '.rubric' "$f")
  # The prompt states a reason the diff cannot show, and the rubric names it.
  prompt=$(jq -r '.prompt' "$f")
  [[ "$prompt" == *"SUP-4412"* ]]
  [[ "$rubric" == *"SUP-4412"* ]]
}

@test "the fact-edit fixture leaves a clean store holding the fact and its index line" {
  setup_eval_repo "# Memory Index"
  ( cd "$EVAL_REPO" && bash "$EVALS_DIR/setups/fact-edit.sh" )
  [ -f "$EVAL_REPO/memory/reference_api_rate_limit.md" ]
  assert_grep "100 requests per minute" "$EVAL_REPO/memory/reference_api_rate_limit.md"
  assert_grep "(reference_api_rate_limit.md)" "$EVAL_REPO/memory/MEMORY.md"
  [ -z "$(git -C "$EVAL_REPO/memory" status --porcelain)" ]
  [ "$(git -C "$EVAL_REPO/memory" rev-parse HEAD)" = "$(git -C "$EVAL_REPO/memory" rev-parse live)" ]
}
