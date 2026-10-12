#!/usr/bin/env bats
# gitlore_batch_hook_guard when it cannot report, on a clean exit, and for the
# files named in GITLORE_HOOK_OWNED. The reporting death is in
# tests/hook_guard.bats; the fixture and its assertions are in
# tests/helpers/hook-guard.bash.
#
# The capture file is assumed to sit directly in the memory worktree's git dir.
# The "unwritable" tests make every directory under it read-only, so they hold
# for any capture name there, and fail for a capture placed elsewhere.
# shellcheck disable=SC2016,SC2154  # fixture bodies are literal; $status/$output come from `run`

bats_require_minimum_version 1.5.0   # `run --separate-stderr`

load helpers/setup
load helpers/fixtures
load helpers/hook-guard

setup()    { hook_guard_setup; }
teardown() { hook_guard_teardown; }

# The fixture appends a claimed name AFTER the guard call, as T3's hooks do.
claim() {
  printf '%s' 'GITLORE_HOOK_OWNED="$GITLORE_HOOK_OWNED"$'"'"'\n'"'"'"$OWNED_FILE"'
}

# --- a guard that cannot report keeps the status, 2 remapped to 1 -----------

# Every directory under the git dir loses its write bit, so a capture file
# cannot be created whatever it is called. The probe proves the bit is in force.
make_gitdir_unwritable() {
  find "$GITDIR" -type d -exec chmod a-w {} +
  run ! touch "$GITDIR/probe"
}

# A jq that always fails: the report cannot be encoded.
make_broken_jq() {
  mkdir -p "$TMP_REPO/.stub"
  printf '#!/bin/sh\nexit 3\n' > "$TMP_REPO/.stub/jq"
  chmod 755 "$TMP_REPO/.stub/jq"
}

@test "guard: an unwritable capture directory keeps status 5, replays stderr, writes no stdout, removes its owned file" {
  OWNED="$TMP_REPO/claimed-by-hook"
  : > "$OWNED"
  write_fixture '' "$(claim)
sh -c 'echo boom-unwritable >&2; exit 5'"
  make_gitdir_unwritable
  run_fixture OWNED_FILE="$OWNED"
  [ "$status" -eq 5 ]
  [[ "$stderr" == *boom-unwritable* ]]
  [ -z "$output" ]
  [ ! -e "$OWNED" ]
}

@test "guard: an unwritable capture directory remaps status 2 to 1, replays stderr, writes no stdout" {
  write_fixture '' "sh -c 'echo boom-unwritable >&2; exit 2'"
  make_gitdir_unwritable
  run_fixture
  [ "$status" -eq 1 ]
  [[ "$stderr" == *boom-unwritable* ]]
  [ -z "$output" ]
}

@test "guard: a broken jq keeps status 5, replays stderr, writes no stdout, removes its owned file and capture" {
  OWNED="$TMP_REPO/claimed-by-hook"
  : > "$OWNED"
  write_fixture '' "$(claim)
sh -c 'echo boom-no-jq >&2; exit 5'"
  make_broken_jq
  before=$(gitdir_listing)
  run_fixture PATH="$TMP_REPO/.stub:$PATH" OWNED_FILE="$OWNED"
  [ "$status" -eq 5 ]
  [[ "$stderr" == *boom-no-jq* ]]
  [ -z "$output" ]
  [ ! -e "$OWNED" ]
  [ "$(gitdir_listing)" = "$before" ]
}

@test "guard: a broken jq remaps status 2 to 1, replays stderr, writes no stdout" {
  write_fixture '' "sh -c 'echo boom-no-jq >&2; exit 2'"
  make_broken_jq
  run_fixture PATH="$TMP_REPO/.stub:$PATH"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *boom-no-jq* ]]
  [ -z "$output" ]
}

# --- a clean exit is untouched ----------------------------------------------

@test "guard: a clean exit leaves stdout byte-for-byte and replays stderr" {
  write_fixture '' "printf 'obj one\n\n  two  \n{\"k\":\"v\"}'
echo fixture-stderr-text >&2"
  rc=0
  env CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" CLAUDE_PROJECT_DIR="$TMP_REPO" \
    bash "$FIX" > "$TMP_REPO/out" 2> "$TMP_REPO/err" || rc=$?
  [ "$rc" -eq 0 ]
  printf 'obj one\n\n  two  \n{"k":"v"}' > "$TMP_REPO/want"
  cmp "$TMP_REPO/out" "$TMP_REPO/want"
  [ "$(cat "$TMP_REPO/err")" = "fixture-stderr-text" ]
}

@test "guard: a clean exit leaves no file in the memory git dir" {
  write_fixture '' 'echo fine'
  before=$(gitdir_listing)
  run_fixture
  [ "$status" -eq 0 ]
  [ "$output" = "fine" ]
  [ "$(gitdir_listing)" = "$before" ]
}

# --- owned files go on any exit ---------------------------------------------

@test "guard: a file named in GITLORE_HOOK_OWNED, space in its path, is gone after a clean exit" {
  OWNED="$TMP_REPO/claimed dir/baseline with space"
  mkdir -p "${OWNED%/*}"
  : > "$OWNED"
  write_fixture '' "$(claim)
echo fine"
  run_fixture OWNED_FILE="$OWNED"
  [ "$status" -eq 0 ]
  [ ! -e "$OWNED" ]
}

@test "guard: files named in GITLORE_HOOK_OWNED, one with a space, are gone after a death" {
  OWNED="$TMP_REPO/claimed dir/baseline with space"
  PLAIN="$TMP_REPO/claimed-plain"
  mkdir -p "${OWNED%/*}"
  : > "$OWNED"
  : > "$PLAIN"
  cmd=$(death_cmd 5)
  write_fixture '' "$(claim)
GITLORE_HOOK_OWNED=\"\$GITLORE_HOOK_OWNED\"\$'\\n'\"$PLAIN\"
$cmd"
  run_fixture OWNED_FILE="$OWNED"
  assert_death_report 5 boom-from-child "$cmd"
  [ ! -e "$OWNED" ]
  [ ! -e "$PLAIN" ]
}
