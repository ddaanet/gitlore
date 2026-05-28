#!/usr/bin/env bats

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
  [ "$status" -eq 0 ]
}

@test "judge.sh exits 1 when claude outputs 'fail'" {
  _make_mock_claude "fail message is too generic"
  run "$JUDGE_SCRIPT" "some rubric" "some diff" "memory: update"
  [ "$status" -eq 1 ]
}

@test "judge.sh handles uppercase PASS output" {
  _make_mock_claude "PASS the message is specific"
  run "$JUDGE_SCRIPT" "some rubric" "some diff" "memory: add eval suite note"
  [ "$status" -eq 0 ]
}
