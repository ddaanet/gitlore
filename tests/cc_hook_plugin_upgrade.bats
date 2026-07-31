#!/usr/bin/env bats
# $status/$output are populated by bats `run`; shellcheck cannot see them.
# shellcheck disable=SC2154
#
# The mid-session plugin-upgrade notice (D21). The session's CLAUDE_PLUGIN_ROOT
# is frozen at process start; the install record is not. When they disagree, the
# hook says so once and names the only remedy.

load helpers/setup
load helpers/fixtures

BATCH="$PLUGIN_ROOT/scripts/cc-hooks/plugin-upgrade-batch.sh"
RESET="$PLUGIN_ROOT/scripts/cc-hooks/recall-reset.sh"

# Trigger strings, defined HERE rather than sourced from the production lib, so
# that a rename in the hook turns the positive assertions red and the negatives
# move with them. Each channel gets its own phrase: dropping one message must
# fail only its own assertion.
SYS_TRIGGER='is what is installed for this repo'
CTX_TRIGGER='Do not attempt a repair'

OLD_VER='0.4.3'
NEW_VER='0.4.4'

setup() {
  setup_tmp_repo
  FAKE_PLUGINS="$TMP_REPO/.fakehome/.claude/plugins"
  CACHE_FAMILY="$FAKE_PLUGINS/cache/ddaanet/gitlore"
  mkdir -p "$CACHE_FAMILY"
  # The frozen root must still be a working plugin checkout — the hook sources
  # scripts/lib from it — while sitting under the cache prefix the guard tests.
  ln -s "$PLUGIN_ROOT" "$CACHE_FAMILY/$OLD_VER"
  export GITLORE_PLUGIN_RECORD="$FAKE_PLUGINS/installed_plugins.json"
  export CLAUDE_PLUGIN_ROOT="$CACHE_FAMILY/$OLD_VER"
}
teardown() { teardown_tmp_repo; }

# Write the install record. $1 = directory the installs sit under, $2 = version
# pinned for THIS project, $3 = version pinned at user scope (defaults to $2).
# installPath is what the hook compares; the directory it names need not exist.
write_record_under() {
  jq -n --arg proj "$TMP_REPO" --arg base "$1" \
        --arg pv "$2" --arg uv "${3:-$2}" '
    {plugins: {"gitlore@ddaanet": [
      {scope: "project", version: $pv, projectPath: $proj,
       installPath: ($base + "/" + $pv)},
      {scope: "user", version: $uv, installPath: ($base + "/" + $uv)}
    ]}}' > "$GITLORE_PLUGIN_RECORD"
}
write_record() { write_record_under "$CACHE_FAMILY" "$@"; }

run_batch() {
  printf '{"hook_event_name":"PostToolBatch","session_id":"sess-1","tool_calls":[]}' \
    | bash "$BATCH"
}
run_reset() {
  printf '{"hook_event_name":"PreCompact","session_id":"sess-1"}' | bash "$RESET"
}

sys_of() { printf '%s' "$1" | jq -r '.systemMessage'; }
ctx_of() { printf '%s' "$1" | jq -r '.hookSpecificOutput.additionalContext'; }

@test "hook is executable" {
  [ -x "$BATCH" ]
}

# The positive every negative below is paired against: same fixture, same
# record shape, only the guard's trigger input varies from here on.
@test "fires on both channels when the record names a newer install for this project" {
  make_parent_with_memory
  write_record "$NEW_VER"

  run run_batch
  [ "$status" -eq 0 ]
  sys=$(sys_of "$output")
  ctx=$(ctx_of "$output")
  [[ "$sys" == *"$SYS_TRIGGER"* ]]
  [[ "$sys" == *"$OLD_VER"* ]]
  [[ "$sys" == *"$NEW_VER"* ]]
  [[ "$ctx" == *"$CTX_TRIGGER"* ]]
  [[ "$ctx" == *"$NEW_VER"* ]]
  [ "$(printf '%s' "$output" | jq -r '.hookSpecificOutput.hookEventName')" = "PostToolBatch" ]
}

# Pairs with the test above: identical fixture, record moved back to the frozen
# version. Red here means the equality guard was deleted or widened.
@test "silent when the frozen root is the recorded install" {
  make_parent_with_memory
  write_record "$OLD_VER"

  run run_batch
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# A repo deliberately pinned behind the user-scoped install is NOT stale: the
# frozen root still matches an entry. Same record content as the firing case
# plus the matching project entry — so red here means the match stopped looking
# at every candidate entry.
@test "silent when the project pin is older than the user-scoped install" {
  make_parent_with_memory
  write_record "$OLD_VER" "$NEW_VER"

  run run_batch
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# A --plugin-dir checkout is never stale. The record here names a sibling of
# that checkout, so every later guard passes — the candidate set is non-empty
# and the frozen root is not in it — and only the cache-prefix test keeps the
# hook quiet.
#
# That layout is the point, not a contrivance. A dev checkout's parent is an
# ordinary source directory, and the family filter is a path prefix: any
# locally-installed plugin recorded under that same parent would otherwise read
# as "the version installed here" and be reported as an upgrade of gitlore.
#
# The fixture must be built to reach the guard — with the record left under the
# cache prefix, this test passes on an empty candidate set and proves nothing.
@test "silent when the frozen root is outside the plugin cache" {
  make_parent_with_memory
  dev="$TMP_REPO/src/gitlore"
  mkdir -p "$TMP_REPO/src"
  ln -s "$PLUGIN_ROOT" "$dev"
  write_record_under "$TMP_REPO/src" "$NEW_VER"
  export CLAUDE_PLUGIN_ROOT="$dev"

  run run_batch
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# Pairs with the firing test: a record that would fire, in a repo with no memory
# store. The five gitlore.* keys only exist where gitlore is installed.
@test "silent outside a gitlore repo" {
  write_record "$NEW_VER"

  run run_batch
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# The marker is per session and lives in the memory gitdir. Positive, negative
# and re-armed positive over one fixture, so the negative cannot pass by never
# reaching the guard.
@test "fires once per session, and again once the marker is cleared" {
  make_parent_with_memory
  write_record "$NEW_VER"

  run run_batch
  [[ "$(sys_of "$output")" == *"$SYS_TRIGGER"* ]]

  run run_batch
  [ "$status" -eq 0 ]
  [ -z "$output" ]

  run run_reset
  [ "$status" -eq 0 ]

  run run_batch
  [[ "$(sys_of "$output")" == *"$SYS_TRIGGER"* ]]
}

# Which entry gets named: the project-scoped one when the record holds both.
# The remedy does not depend on which, but reporting the user-scoped version to
# a repo pinned elsewhere would send the reader chasing the wrong number.
@test "names the project-scoped version, not the user-scoped one" {
  make_parent_with_memory
  write_record "$NEW_VER" "0.9.9"

  run run_batch
  [ "$status" -eq 0 ]
  sys=$(sys_of "$output")
  [[ "$sys" == *"$NEW_VER"* ]]
  [[ "$sys" != *"0.9.9"* ]]
}

# The hook is advisory. Neither absence nor corruption of the record may put
# output in front of the user or a non-zero status in front of the batch.
@test "a missing record never fails the batch" {
  make_parent_with_memory
  write_record "$NEW_VER"
  rm -f "$GITLORE_PLUGIN_RECORD"

  run run_batch
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "a malformed record never fails the batch" {
  make_parent_with_memory
  printf 'this is not json\n' > "$GITLORE_PLUGIN_RECORD"

  run run_batch
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
