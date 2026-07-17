#!/usr/bin/env bats
# Tests for run-evals.sh pre-flight behaviour and the two-turn eval runner.

# Consumed by the sourced setup.sh (`${EVAL_LIB_DIR:-…}`); export so it crosses.
export EVAL_LIB_DIR="$BATS_TEST_DIRNAME"
RUN_EVALS="$BATS_TEST_DIRNAME/../run-evals.sh"
RUNNER="$BATS_TEST_DIRNAME/claude-runner.sh"

setup() {
  MOCK_BIN="$(mktemp -d "${TMPDIR:-/tmp}/runner-mock.XXXXXX")"
  export MOCK_BIN
  export PATH="$MOCK_BIN:$PATH"
}

teardown() {
  rm -rf "$MOCK_BIN"
}

# Mock claude: logs argv, prints one JSON result per call.
# $1.. — the `subtype` value for each successive call, in order.
_make_mock_claude() {
  local subtypes=("$@")
  printf '%s\n' "${subtypes[@]}" > "$MOCK_BIN/subtypes"
  cat > "$MOCK_BIN/claude" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$MOCK_BIN/argv.log"
# Log whatever claude received on stdin — nothing, iff the runner redirected
# </dev/null. `read -t` rather than `cat`: on a regression the mock must not
# inherit a live stdin and hang the suite.
if IFS= read -r -t 1 _line; then printf '%s\n' "$_line" >> "$MOCK_BIN/stdin.log"; fi
n=$(wc -l < "$MOCK_BIN/argv.log" | tr -d ' ')
subtype=$(sed -n "${n}p" "$MOCK_BIN/subtypes")
printf '{"subtype":"%s","session_id":"sid-%s","result":"canned"}\n' "$subtype" "$n"
EOF
  chmod +x "$MOCK_BIN/claude"
}

@test "run-evals: exits 1 with sandbox hint when the runner probe fails" {
    local fake_lib="$BATS_TEST_TMPDIR/lib"
    mkdir -p "$fake_lib"
    # Replace the runner with one that always fails (simulates a sandboxed env)
    printf '#!/usr/bin/env bash\necho "probe: API not accessible" >&2\nexit 1\n' \
        > "$fake_lib/claude-runner.sh"
    chmod +x "$fake_lib/claude-runner.sh"

    run env LIB_DIR="$fake_lib" bash "$RUN_EVALS"

    [ "$status" -eq 1 ]
    [[ "$output" =~ "sandbox" ]]
}

@test "claude-runner: is executable" {
  [ -x "$RUNNER" ]
}

@test "claude-runner: probe exits 0 on a success result" {
  _make_mock_claude success
  run "$RUNNER" --probe --cwd "$BATS_TEST_TMPDIR"
  [ "$status" -eq 0 ]
}

@test "claude-runner: probe exits 1 on an error result" {
  _make_mock_claude error_during_execution
  run "$RUNNER" --probe --cwd "$BATS_TEST_TMPDIR"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "probe" ]]
}

@test "claude-runner: two turns, turn 2 resumes turn 1's session" {
  _make_mock_claude success success
  run "$RUNNER" --cwd "$BATS_TEST_TMPDIR" --prompt "do the thing" --approval "looks good"
  [ "$status" -eq 0 ]

  local turn1 turn2
  turn1=$(sed -n 1p "$MOCK_BIN/argv.log")
  turn2=$(sed -n 2p "$MOCK_BIN/argv.log")
  [[ "$turn1" =~ "do the thing" ]]
  [[ "$turn1" != *"--resume"* ]]
  [[ "$turn2" =~ "looks good" ]]
  [[ "$turn2" =~ "--resume sid-1" ]]
}

@test "claude-runner: passes project-only settings and bypass permissions" {
  _make_mock_claude success success
  run "$RUNNER" --cwd "$BATS_TEST_TMPDIR" --prompt "p" --approval "a"
  [ "$status" -eq 0 ]
  local turn1
  turn1=$(sed -n 1p "$MOCK_BIN/argv.log")
  [[ "$turn1" =~ "--setting-sources project" ]]
  [[ "$turn1" =~ "--permission-mode bypassPermissions" ]]
}

@test "claude-runner: turn 1 failure exits 1 without running turn 2" {
  _make_mock_claude error_during_execution success
  run "$RUNNER" --cwd "$BATS_TEST_TMPDIR" --prompt "p" --approval "a"
  [ "$status" -eq 1 ]
  [ "$(wc -l < "$MOCK_BIN/argv.log" | tr -d ' ')" -eq 1 ]
  [[ "$output" =~ "turn 1" ]]
}

@test "claude-runner: turn 2 failure exits 1" {
  _make_mock_claude success error_during_execution
  run "$RUNNER" --cwd "$BATS_TEST_TMPDIR" --prompt "p" --approval "a"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "turn 2" ]]
}

# `claude -p` waits 3s for piped stdin that never arrives, warning and stalling
# every turn. The runner redirects </dev/null; nothing of ours may reach claude.
@test "claude-runner: gives claude an empty stdin" {
  _make_mock_claude success success
  run bash -c "printf 'LEAK\n' | '$RUNNER' --cwd '$BATS_TEST_TMPDIR' --prompt p --approval a"
  [ "$status" -eq 0 ]
  [ ! -s "$MOCK_BIN/stdin.log" ]
}

@test "claude-runner: --prompt without --approval is a usage error" {
  _make_mock_claude success
  run "$RUNNER" --cwd "$BATS_TEST_TMPDIR" --prompt "p"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "--approval" ]]
}
