#!/usr/bin/env bats

load helpers/setup
load helpers/fixtures

SHIM_SRC="$PLUGIN_ROOT/scripts/install/launcher-shim"

setup() {
  setup_tmp_repo
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

@test "exit 127 when no real claude is reachable" {
  # PATH = shim dir + a minimal toolbox (the utilities the shim needs) but no claude.
  tools="$TMP_REPO/.tools"; mkdir -p "$tools"
  for t in sh tr grep paste git jq dirname env; do ln -s "$(command -v "$t")" "$tools/$t"; done
  run env -i HOME="$HOME" PATH="$SHIMDIR:$tools" "$SHIMDIR/claude"
  [ "$status" -eq 127 ]
}
