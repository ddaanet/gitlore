#!/usr/bin/env bats

# shellcheck source=tests/helpers/run-asserts.bash
source "$BATS_TEST_DIRNAME/../../helpers/run-asserts.bash"
# shellcheck source=tests/helpers/dogfood-shim.bash
source "$BATS_TEST_DIRNAME/../../helpers/dogfood-shim.bash"

EVAL_LIB_DIR="$BATS_TEST_DIRNAME"
JUDGE_SCRIPT="$EVAL_LIB_DIR/judge.sh"

setup() {
  MOCK_BIN="$(mktemp -d "${TMPDIR:-/tmp}/judge-mock.XXXXXX")"
  export MOCK_BIN
  export PATH="$MOCK_BIN:$PATH"
}

teardown() {
  rm -rf "$MOCK_BIN"
}

_make_mock_claude() {
  local output="$1"
  cat > "$MOCK_BIN/claude" <<EOF
#!/usr/bin/env bash
printf '%s\n' "$output"
EOF
  chmod +x "$MOCK_BIN/claude"
}

@test "judge.sh exits 0 when claude outputs 'pass'" {
  _make_mock_claude "pass the message mentions evals"
  run "$JUDGE_SCRIPT" "some rubric" "some diff" "memory: add eval suite note"
  assert_ok
}

@test "judge.sh exits 1 when claude outputs 'fail'" {
  _make_mock_claude "fail message is too generic"
  run "$JUDGE_SCRIPT" "some rubric" "some diff" "memory: update"
  assert_status 1
}

@test "judge.sh handles uppercase PASS output" {
  _make_mock_claude "PASS the message is specific"
  run "$JUDGE_SCRIPT" "some rubric" "some diff" "memory: add eval suite note"
  assert_ok
}

@test "judge.sh exits 2 when claude invocation fails" {
  cat > "$MOCK_BIN/claude" <<'EOF'
#!/usr/bin/env bash
echo "rate limited" >&2
exit 1
EOF
  chmod +x "$MOCK_BIN/claude"
  run "$JUDGE_SCRIPT" "some rubric" "some diff" "memory: update"
  assert_status 2 "rate limited"
}

@test "judge.sh exits 2 when the verdict hedges instead of a clean pass/fail" {
  _make_mock_claude "FAIL, but wait, on reflection this is fine — PASS"
  run "$JUDGE_SCRIPT" "some rubric" "some diff" "memory: update"
  assert_status 2
}

# See runner.bats: the dogfood shim re-exports CLAUDE_CODE_PLUGIN_DIRS, so the
# judge must resolve the real claude past it rather than only unsetting the var.
@test "judge.sh reaches the real claude with CLAUDE_CODE_PLUGIN_DIRS unset past a dogfood shim" {
  dogfood_shim_install "$BATS_TEST_TMPDIR" "pass looks fine"
  unset CLAUDE_CODE_PLUGIN_DIRS
  run "$JUDGE_SCRIPT" "some rubric" "some diff" "memory: update"
  assert_ok
  [ -f "$DOGFOOD_RECORD.env" ]
  [ "$(cat "$DOGFOOD_RECORD.env")" = "unset" ]
}

@test "judge.sh CLAUDE_CODE_PLUGIN_DIRS exported by the caller does not reach claude past a dogfood shim" {
  dogfood_shim_install "$BATS_TEST_TMPDIR" "pass looks fine"
  export CLAUDE_CODE_PLUGIN_DIRS="/caller/plugin dir"
  run "$JUDGE_SCRIPT" "some rubric" "some diff" "memory: update"
  assert_ok
  [ -f "$DOGFOOD_RECORD.env" ]
  [ "$(cat "$DOGFOOD_RECORD.env")" = "unset" ]
}

@test "judge.sh keeps the shim's directory off PATH for claude behind a chaining launcher" {
  dogfood_shim_install "$BATS_TEST_TMPDIR" "pass looks fine" launcher
  unset CLAUDE_CODE_PLUGIN_DIRS
  run "$JUDGE_SCRIPT" "some rubric" "some diff" "memory: update"
  assert_ok
  [ -f "$DOGFOOD_RECORD.launcher" ]
  [ -f "$DOGFOOD_RECORD.env" ]
  [ "$(cat "$DOGFOOD_RECORD.env")" = "unset" ]
}

@test "judge.sh bypasses a dogfood shim spelled with a trailing slash on PATH" {
  dogfood_shim_install "$BATS_TEST_TMPDIR" "pass looks fine" slash
  unset CLAUDE_CODE_PLUGIN_DIRS
  run "$JUDGE_SCRIPT" "some rubric" "some diff" "memory: update"
  assert_ok
  [ -f "$DOGFOOD_RECORD.env" ]
  [ "$(cat "$DOGFOOD_RECORD.env")" = "unset" ]
}

# A rubric cannot be exercised without the real claude, so what is pinned is the
# plumbing a rubric depends on: the judge's prompt carries the rubric, the diff
# and the multi-line message each verbatim, with the message under its own
# header. A summary that retells a fact body, or omits the reason for an edit,
# is graded from exactly this text.
@test "judge.sh puts the rubric, diff and a multi-paragraph summary into the prompt verbatim" {
  cat > "$MOCK_BIN/claude" <<'MOCK'
#!/usr/bin/env bash
# The prompt is the argument after --print.
while [ $# -gt 0 ]; do
  if [ "$1" = "--print" ]; then printf '%s' "$2" > "$PROMPT_FILE"; fi
  shift
done
printf 'pass fine\n'
MOCK
  chmod +x "$MOCK_BIN/claude"
  export PROMPT_FILE="$BATS_TEST_TMPDIR/prompt"
  summary=$'memory: raise the partner rate limit\n\n**Update reference_api_rate_limit:** the limit rose to 600.\nThe account moved to the Business tier (SUP-4412).'
  run "$JUDGE_SCRIPT" "Fail if it omits the reason." $'-100 per minute\n+600 per minute' "$summary"
  assert_ok
  prompt=$(cat "$PROMPT_FILE")
  [[ "$prompt" == *"RUBRIC: Fail if it omits the reason."* ]]
  [[ "$prompt" == *$'DIFF:\n-100 per minute\n+600 per minute'* ]]
  [[ "$prompt" == *"COMMIT_MESSAGE:"$'\n'"$summary" ]]
}
