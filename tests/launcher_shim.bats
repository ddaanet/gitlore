#!/usr/bin/env bats
bats_require_minimum_version 1.5.0

load helpers/setup
load helpers/fixtures

SHIM_SRC="$PLUGIN_ROOT/scripts/install/launcher-shim"

setup() {
  setup_tmp_repo
  # Clean baseline: the suite may be run from inside a gitlore-launched session
  # (GITLORE_LAUNCHED=1 in the ambient env), which would make the inject test
  # see the anti-double-inject sentinel and pass through. The one test that
  # needs the sentinel sets it inline.
  unset GITLORE_LAUNCHED
  unset GITLORE_AUTO_CLAUDE_PLUGIN_DIR
  SHIMDIR="$TMP_REPO/.shimdir"; STUBDIR="$TMP_REPO/.stubdir"
  mkdir -p "$SHIMDIR" "$STUBDIR"
  cp "$SHIM_SRC" "$SHIMDIR/claude"; chmod 755 "$SHIMDIR/claude"
  # Recording stub: prints its args so we can assert what the shim forwarded.
  printf '#!/bin/sh\necho "REAL:$*"\n' > "$STUBDIR/claude"; chmod 755 "$STUBDIR/claude"
  export PATH="$SHIMDIR:$STUBDIR:$PATH"
}
teardown() { teardown_tmp_repo; }

@test "passthrough when not in a gitlore repo" {
  run "$SHIMDIR/claude" hello
  [ "$status" -eq 0 ]
  [ "$output" = "REAL:hello" ]
}

# The shim strips its own directory from PATH to find the real claude, and a
# strip that misses re-execs the shim forever. A `//` is how that arrives in
# practice: macOS `$TMPDIR` ends in `/`, so every path built from it carries
# one. The call is bounded because the regression is a hang — an unbounded
# `run` would take the suite down with it instead of failing here.
bounded() {
  local secs="$1" pid dog st
  shift
  "$@" &
  pid=$!
  # The kill is expected to find nothing on the happy path; that is the point.
  ( sleep "$secs"; kill -9 "$pid" 2>/dev/null ) &
  dog=$!
  wait "$pid"; st=$?
  kill "$dog" 2>/dev/null
  return "$st"
}

@test "finds the real claude however PATH spells the shim's own directory" {
  local spelling
  for spelling in "$SHIMDIR/" "${SHIMDIR%/*}//${SHIMDIR##*/}"; do
    PATH="$spelling:$STUBDIR:$PATH" run bounded 10 "$SHIMDIR/claude" hello
    [ "$status" -eq 0 ]
    [ "$output" = "REAL:hello" ]
  done
}

@test "passthrough when GITLORE_LAUNCHED already set (anti-double-inject)" {
  make_parent_with_memory
  mkdir -p .claude; printf '{"gitlore":{"enabled":true}}\n' > .claude/settings.json
  GITLORE_LAUNCHED=1 run "$SHIMDIR/claude" hi
  [ "$output" = "REAL:hi" ]
}

@test "passthrough when submodule present but gitlore disabled" {
  make_parent_with_memory
  mkdir -p .claude; printf '{"gitlore":{"enabled":false}}\n' > .claude/settings.json
  run "$SHIMDIR/claude" hi
  [ "$output" = "REAL:hi" ]
}

@test "injects --settings autoMemoryDirectory in an enabled gitlore repo" {
  make_parent_with_memory
  mkdir -p .claude; printf '{"gitlore":{"enabled":true}}\n' > .claude/settings.json
  run "$SHIMDIR/claude" hi
  [ "$status" -eq 0 ]
  [[ "$output" == *"--settings"* ]]
  [[ "$output" == *"autoMemoryDirectory"* ]]
  [[ "$output" == *"$TMP_REPO/memory"* ]]
  [[ "$output" == *"hi"* ]]
}

@test "no --plugin-dir by default, even in a plugin checkout" {
  mkdir -p .claude-plugin; printf '{"name":"x"}\n' > .claude-plugin/plugin.json
  run "$SHIMDIR/claude" hi
  [ "$status" -eq 0 ]
  [ "$output" = "REAL:hi" ]
}

@test "no --plugin-dir when opted in but no plugin.json" {
  GITLORE_AUTO_CLAUDE_PLUGIN_DIR=1 run "$SHIMDIR/claude" hi
  [ "$status" -eq 0 ]
  [ "$output" = "REAL:hi" ]
}

@test "injects --plugin-dir . when opted in inside a plugin checkout" {
  mkdir -p .claude-plugin; printf '{"name":"x"}\n' > .claude-plugin/plugin.json
  GITLORE_AUTO_CLAUDE_PLUGIN_DIR=1 run "$SHIMDIR/claude" hi
  [ "$status" -eq 0 ]
  [ "$output" = "REAL:--plugin-dir . hi" ]
}

@test "--plugin-dir composes with the autoMemoryDirectory injection" {
  make_parent_with_memory
  mkdir -p .claude; printf '{"gitlore":{"enabled":true}}\n' > .claude/settings.json
  mkdir -p .claude-plugin; printf '{"name":"x"}\n' > .claude-plugin/plugin.json
  GITLORE_AUTO_CLAUDE_PLUGIN_DIR=1 run "$SHIMDIR/claude" hi
  [ "$status" -eq 0 ]
  [[ "$output" == *"--settings"* ]]
  [[ "$output" == *"autoMemoryDirectory"* ]]
  [[ "$output" == *"--plugin-dir . hi"* ]]
}

@test "GITLORE_LAUNCHED suppresses --plugin-dir (anti-double-inject)" {
  mkdir -p .claude-plugin; printf '{"name":"x"}\n' > .claude-plugin/plugin.json
  GITLORE_LAUNCHED=1 GITLORE_AUTO_CLAUDE_PLUGIN_DIR=1 run "$SHIMDIR/claude" hi
  [ "$status" -eq 0 ]
  [ "$output" = "REAL:hi" ]
}

@test "exit 127 when no real claude is reachable" {
  # PATH = shim dir + a minimal toolbox (the utilities the shim needs) but no claude.
  tools="$TMP_REPO/.tools"; mkdir -p "$tools"
  for t in sh git jq dirname env; do ln -s "$(command -v "$t")" "$tools/$t"; done
  run -127 env -i HOME="$HOME" PATH="$SHIMDIR:$tools" "$SHIMDIR/claude"
  [ "$status" -eq 127 ]
}
