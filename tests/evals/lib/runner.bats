#!/usr/bin/env bats
# Tests for run-evals.sh pre-flight behaviour and the two-turn eval runner.

# shellcheck source=tests/helpers/run-asserts.bash
source "$BATS_TEST_DIRNAME/../../helpers/run-asserts.bash"
# shellcheck source=tests/helpers/dogfood-shim.bash
source "$BATS_TEST_DIRNAME/../../helpers/dogfood-shim.bash"

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

    assert_status 1 "sandbox"
}

@test "claude-runner: is executable" {
  [ -x "$RUNNER" ]
}

@test "claude-runner: probe exits 0 on a success result" {
  _make_mock_claude success
  run "$RUNNER" --probe --cwd "$BATS_TEST_TMPDIR"
  assert_ok
}

@test "claude-runner: probe exits 1 on an error result" {
  _make_mock_claude error_during_execution
  run "$RUNNER" --probe --cwd "$BATS_TEST_TMPDIR"
  assert_status 1 "probe"
}

@test "claude-runner: two turns, turn 2 resumes turn 1's session" {
  _make_mock_claude success success
  run "$RUNNER" --cwd "$BATS_TEST_TMPDIR" --prompt "do the thing" --approval "looks good"
  assert_ok

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
  assert_ok
  local turn1
  turn1=$(sed -n 1p "$MOCK_BIN/argv.log")
  [[ "$turn1" =~ "--setting-sources project" ]]
  [[ "$turn1" =~ "--permission-mode bypassPermissions" ]]
}

@test "claude-runner: turn 1 failure exits 1 without running turn 2" {
  _make_mock_claude error_during_execution success
  run "$RUNNER" --cwd "$BATS_TEST_TMPDIR" --prompt "p" --approval "a"
  assert_status 1 "turn 1"
  [ "$(wc -l < "$MOCK_BIN/argv.log" | tr -d ' ')" -eq 1 ]
}

@test "claude-runner: turn 2 failure exits 1" {
  _make_mock_claude success error_during_execution
  run "$RUNNER" --cwd "$BATS_TEST_TMPDIR" --prompt "p" --approval "a"
  assert_status 1 "turn 2"
}

# `claude -p` waits 3s for piped stdin that never arrives, warning and stalling
# every turn. The runner redirects </dev/null; nothing of ours may reach claude.
@test "claude-runner: gives claude an empty stdin" {
  _make_mock_claude success success
  run bash -c "printf 'LEAK\n' | '$RUNNER' --cwd '$BATS_TEST_TMPDIR' --prompt p --approval a"
  assert_ok
  [ ! -s "$MOCK_BIN/stdin.log" ]
}

# Scenarios with no approval gate (recall) are a single turn. A
# synthetic second message would put the agent's reply to something the flow
# never sends into the very transcript the assertions read.
@test "claude-runner: --prompt without --approval runs exactly one turn" {
  _make_mock_claude success
  run "$RUNNER" --cwd "$BATS_TEST_TMPDIR" --prompt "p"
  assert_ok
  [ "$(wc -l < "$MOCK_BIN/argv.log" | tr -d ' ')" -eq 1 ]
}

@test "claude-runner: --cwd alone is a usage error" {
  _make_mock_claude success
  run "$RUNNER" --cwd "$BATS_TEST_TMPDIR"
  assert_fails "--prompt"
}

@test "claude-runner: --out-dir captures each turn's text and the session id" {
  _make_mock_claude success success
  local out="$BATS_TEST_TMPDIR/out"
  run "$RUNNER" --cwd "$BATS_TEST_TMPDIR" --prompt "p" --approval "a" --out-dir "$out"
  assert_ok
  [ "$(cat "$out/turn1.txt")" = "canned" ]
  [ "$(cat "$out/turn2.txt")" = "canned" ]
  [ "$(cat "$out/session-id")" = "sid-1" ]
}

@test "claude-runner: --out-dir on a one-turn run captures turn 1 only" {
  _make_mock_claude success
  local out="$BATS_TEST_TMPDIR/out"
  run "$RUNNER" --cwd "$BATS_TEST_TMPDIR" --prompt "p" --out-dir "$out"
  assert_ok
  [ -f "$out/turn1.txt" ]
  [ ! -f "$out/turn2.txt" ]
}

# The assertions grade "no memory commit before approval" from memory's HEAD
# between the turns. The mock commits in memory on EVERY call, so a snapshot
# taken before turn 1 or after turn 2 would not equal the repo's HEAD at the end
# of turn 1.
@test "claude-runner: --approval with --out-dir records memory's HEAD between the turns" {
  local cwd="$BATS_TEST_TMPDIR/proj" out="$BATS_TEST_TMPDIR/out"
  mkdir -p "$cwd/memory"
  git -C "$cwd/memory" init -q
  git -C "$cwd/memory" -c user.email=e@x.com -c user.name=E commit -q --allow-empty -m base
  cat > "$MOCK_BIN/claude" <<'MOCKEOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$MOCK_BIN/argv.log"
n=$(wc -l < "$MOCK_BIN/argv.log" | tr -d ' ')
git -C memory -c user.email=e@x.com -c user.name=E commit -q --allow-empty -m "turn $n"
# Where memory stood when this call ended, for the test to compare against.
git -C memory rev-parse HEAD > "$MOCK_BIN/head-after-$n"
printf '{"subtype":"success","session_id":"sid-%s","result":"canned"}\n' "$n"
MOCKEOF
  chmod +x "$MOCK_BIN/claude"

  run "$RUNNER" --cwd "$cwd" --prompt "p" --approval "a" --out-dir "$out"
  assert_ok
  [ -f "$out/memory-after-turn1" ]
  [ -s "$MOCK_BIN/head-after-1" ]
  [ "$(cat "$out/memory-after-turn1")" = "$(cat "$MOCK_BIN/head-after-1")" ]
  [ "$(cat "$MOCK_BIN/head-after-1")" != "$(cat "$MOCK_BIN/head-after-2")" ]
}

# `git -C <cwd>/memory` inside an unmounted memory/ resolves to the PARENT repo,
# so a naive snapshot would record the parent's HEAD as memory's.
@test "claude-runner: --approval with --out-dir where <cwd>/memory/.git is absent writes no memory-after-turn1 and exits 0" {
  local cwd="$BATS_TEST_TMPDIR/proj" out="$BATS_TEST_TMPDIR/out"
  mkdir -p "$cwd/memory"
  git -C "$cwd" init -q
  git -C "$cwd" -c user.email=e@x.com -c user.name=E commit -q --allow-empty -m base
  _make_mock_claude success success
  run "$RUNNER" --cwd "$cwd" --prompt "p" --approval "a" --out-dir "$out"
  assert_ok
  [ -f "$out/turn2.txt" ]
  [ ! -e "$out/memory-after-turn1" ]
}

# A scenario with no approval gate has no "before approval" to snapshot.
@test "claude-runner: a one-turn run writes no memory-after-turn1" {
  local cwd="$BATS_TEST_TMPDIR/proj" out="$BATS_TEST_TMPDIR/out"
  mkdir -p "$cwd/memory"
  git -C "$cwd/memory" init -q
  git -C "$cwd/memory" -c user.email=e@x.com -c user.name=E commit -q --allow-empty -m base
  _make_mock_claude success
  run "$RUNNER" --cwd "$cwd" --prompt "p" --out-dir "$out"
  assert_ok
  [ -f "$out/turn1.txt" ]
  [ ! -e "$out/memory-after-turn1" ]
}

# The transcript is how an assertion sees which TOOLS ran. Located by session id
# alone, because the projects/<dir> name is a mangling of cwd and deriving it
# here would be a second place to get that encoding wrong.
@test "claude-runner: --out-dir captures the session transcript by id" {
  _make_mock_claude success
  local home="$BATS_TEST_TMPDIR/cfg"
  mkdir -p "$home/projects/-some-mangled-path"
  printf '{"marker":"transcript"}\n' > "$home/projects/-some-mangled-path/sid-1.jsonl"
  local out="$BATS_TEST_TMPDIR/out"
  run env CLAUDE_CONFIG_DIR="$home" \
      "$RUNNER" --cwd "$BATS_TEST_TMPDIR" --prompt "p" --out-dir "$out"
  assert_ok
  assert_grep -q transcript "$out/transcript.jsonl"
}

# The dogfood shim (plugin-dev/bin/claude) re-exports CLAUDE_CODE_PLUGIN_DIRS
# and execs the next claude, so the eval repo's own settings.json hooks load a
# second time. The runner must resolve the real claude past the shim; unsetting
# the variable first is not enough, the shim sets it again.
@test "claude-runner: a turn reaches the real claude with CLAUDE_CODE_PLUGIN_DIRS unset past a dogfood shim" {
  dogfood_shim_install "$BATS_TEST_TMPDIR" '{"subtype":"success","session_id":"sid-1","result":"canned"}'
  unset CLAUDE_CODE_PLUGIN_DIRS
  run "$RUNNER" --cwd "$BATS_TEST_TMPDIR" --prompt "p"
  assert_ok
  [ -f "$DOGFOOD_RECORD.env" ]
  [ "$(cat "$DOGFOOD_RECORD.env")" = "unset" ]
}

@test "claude-runner: CLAUDE_CODE_PLUGIN_DIRS exported by the caller does not reach claude past a dogfood shim" {
  dogfood_shim_install "$BATS_TEST_TMPDIR" '{"subtype":"success","session_id":"sid-1","result":"canned"}'
  export CLAUDE_CODE_PLUGIN_DIRS="/caller/plugin dir"
  run "$RUNNER" --cwd "$BATS_TEST_TMPDIR" --prompt "p"
  assert_ok
  [ -f "$DOGFOOD_RECORD.env" ]
  [ "$(cat "$DOGFOOD_RECORD.env")" = "unset" ]
}

# The gitlore launcher sits between the shim and claude and strips only its own
# directory from PATH. Stepping past the shim once, with it still on PATH, lands
# on the launcher, which finds the shim again: its directory has to be off PATH
# for the child.
@test "claude-runner: the shim's directory is off PATH for claude behind a chaining launcher" {
  dogfood_shim_install "$BATS_TEST_TMPDIR" '{"subtype":"success","session_id":"sid-1","result":"canned"}' launcher
  unset CLAUDE_CODE_PLUGIN_DIRS
  run "$RUNNER" --cwd "$BATS_TEST_TMPDIR" --prompt "p"
  assert_ok
  [ -f "$DOGFOOD_RECORD.launcher" ]
  [ -f "$DOGFOOD_RECORD.env" ]
  [ "$(cat "$DOGFOOD_RECORD.env")" = "unset" ]
}

@test "claude-runner: a dogfood shim spelled with a trailing slash on PATH is bypassed" {
  dogfood_shim_install "$BATS_TEST_TMPDIR" '{"subtype":"success","session_id":"sid-1","result":"canned"}' slash
  unset CLAUDE_CODE_PLUGIN_DIRS
  run "$RUNNER" --cwd "$BATS_TEST_TMPDIR" --prompt "p"
  assert_ok
  [ -f "$DOGFOOD_RECORD.env" ]
  [ "$(cat "$DOGFOOD_RECORD.env")" = "unset" ]
}
