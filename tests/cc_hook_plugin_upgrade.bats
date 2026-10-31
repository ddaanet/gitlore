#!/usr/bin/env bats
# $status/$output are populated by bats `run`; shellcheck cannot see them.
# shellcheck disable=SC2154
#
# The mid-session plugin-upgrade notice (D21). The session's CLAUDE_PLUGIN_ROOT
# is frozen at process start; the install record is not. When they disagree, the
# hook says so once and names the only remedy.

bats_require_minimum_version 1.5.0

load helpers/setup
load helpers/fixtures
load helpers/hook-guard

BATCH="$PLUGIN_ROOT/scripts/cc-hooks/plugin-upgrade-batch.sh"
RESET="$PLUGIN_ROOT/scripts/cc-hooks/nudge-reset.sh"

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
#
# The USER entry comes first on purpose. The hook falls back to the first
# candidate when no project-scoped one applies, so a record listing the project
# entry first would satisfy "names the project-scoped version" by accident of
# ordering, and that test could not tell the preference from the fallback.
write_record_under() {
  jq -n --arg proj "$TMP_REPO" --arg base "$1" \
        --arg pv "$2" --arg uv "${3:-$2}" '
    {plugins: {"gitlore@ddaanet": [
      {scope: "user", version: $uv, installPath: ($base + "/" + $uv)},
      {scope: "project", version: $pv, projectPath: $proj,
       installPath: ($base + "/" + $pv)}
    ]}}' > "$GITLORE_PLUGIN_RECORD"
}
write_record() { write_record_under "$CACHE_FAMILY" "$@"; }

run_batch() {
  printf '{"hook_event_name":"PostToolBatch","session_id":"sess-1","tool_calls":[]}' \
    | bash "$BATCH"
}
run_reset() {
  printf '{"hook_event_name":"SessionStart","source":"compact","session_id":"sess-1"}' | bash "$RESET"
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
# store. The gitlore.hooksDir key only exists where gitlore is installed.
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

# The age sweep of markers other sessions left behind is best-effort garbage
# collection: a gitdir that refuses the unlink must not abort the hook, or this
# session's own markers survive the reset that was meant to clear them and both
# once-per-episode notices stay silent for the rest of it.
@test "a failing sweep does not stop the reset from clearing this session's markers" {
  make_parent_with_memory
  budget=$(gitlore_index_budget_nudge_file memory sess-1)
  upgrade=$(gitlore_upgrade_nudge_file memory sess-1)
  mkdir -p "$(dirname "$budget")"
  touch "$budget" "$upgrade"

  # A `find` stub on PATH for the hook only: it fails every call carrying
  # `-delete`, which on this path is the sweep and nothing else, and passes
  # every other call through to the real find.
  fakebin="$BATS_TEST_TMPDIR/fakebin"
  mkdir -p "$fakebin"
  real_find=$(command -v find)
  cat > "$fakebin/find" <<EOF
#!/bin/sh
for a in "\$@"; do
  if [ "\$a" = -delete ]; then
    echo "find: cannot delete" >&2
    exit 1
  fi
done
exec "$real_find" "\$@"
EOF
  chmod +x "$fakebin/find"

  PATH="$fakebin:$PATH" run run_reset
  [ "$status" -eq 0 ]
  # The second reset runs only if the first one's sweep did not abort the hook.
  [ ! -f "$budget" ]
  [ ! -f "$upgrade" ]
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

# Pairs with the firing test again: a record under the same cache family, past
# the prefix guard, whose only entry applies to a DIFFERENT project. The
# candidate set is then empty and there is no version to report — without the
# emptiness guard the hook announces an upgrade to nothing at all.
@test "silent when the record names no install that applies here" {
  make_parent_with_memory
  jq -n --arg base "$CACHE_FAMILY" --arg v "$NEW_VER" '
    {plugins: {"gitlore@ddaanet": [
      {scope: "project", version: $v, projectPath: "/somewhere/else",
       installPath: ($base + "/" + $v)}
    ]}}' > "$GITLORE_PLUGIN_RECORD"

  run run_batch
  [ "$status" -eq 0 ]
  [ -z "$output" ]
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

# D60: a PostToolBatch hook that dies reports instead of ending the turn. TMPDIR
# names a directory that is gone (a cleaned tmpfs, a stale export):
# `mktemp "${TMPDIR:-/tmp}/gitlore-upgrade.XXXXXX"`) fails with status 1 after
# the stale record was found. The hook has no consequence sentence — nothing
# depends on the notice — so additionalContext adds nothing after the death.
# bats' own `run` plumbing uses TMPDIR, so only the hook gets the bad one.
run_batch_without_tmpdir() { TMPDIR="$TMP_REPO/gone" run_batch; }

@test "a missing TMPDIR is reported on both channels, exit 0, with no consequence" {
  make_parent_with_memory
  write_record "$NEW_VER"

  run --separate-stderr run_batch_without_tmpdir
  assert_hook_died plugin-upgrade-batch 1
  sys=$(sys_msg)
  ctx=$(ctx_msg)
  # Whitespace-trimmed, since the join of description and empty sentence may
  # leave a separator: the point is that no sentence follows the description.
  trim() { printf '%s' "$1" | sed -e 's/[[:space:]]*$//'; }
  [ "$(trim "$ctx")" = "$(trim "$sys")" ]
  # And the description ends at the command's own stderr, on both channels.
  [[ "$(trim "$sys")" == *"No such file or directory" ]]
  [[ "$(trim "$ctx")" == *"No such file or directory" ]]
}

# D60: the payload parse and the marker write cost only what they key. A payload
# that is not JSON loses the session keying (the marker is then the shared
# `nosession` one); a marker that cannot be written means the notice repeats on
# the next batch. Neither withholds the notice or kills the hook.
@test "an unparseable payload still emits the notice" {
  make_parent_with_memory
  write_record "$NEW_VER"

  # shellcheck disable=SC2016  # $1 is for the inner bash -c, not this shell
  run --separate-stderr bash -c 'printf "not json" | bash "$1"' _ "$BATCH"
  [ "$status" -eq 0 ]
  assert_one_object
  [[ "$(sys_msg)" == *"$SYS_TRIGGER"* ]]
  [[ "$(ctx_msg)" == *"$CTX_TRIGGER"* ]]
  [[ "$(sys_msg)" != *"died with status"* ]]
  [[ "$(ctx_msg)" != *"died with status"* ]]
}

# The marker's directory is the memory git dir; a restored backup or another
# user's files can leave it unwritable. The stub stands in for that: every
# `touch` fails, as it would there, and nothing else is affected.
make_failing_touch() {
  STUBS="$BATS_TEST_TMPDIR/stubs"
  mkdir -p "$STUBS"
  printf '#!/usr/bin/env bash\nprintf "touch: cannot touch: Permission denied\\n" >&2\nexit 1\n' > "$STUBS/touch"
  chmod 755 "$STUBS/touch"
}
run_batch_failing_touch() { PATH="$STUBS:$PATH" run_batch; }

@test "a marker that cannot be written does not withhold the notice, which repeats" {
  make_parent_with_memory
  write_record "$NEW_VER"
  make_failing_touch

  for _ in 1 2; do
    run --separate-stderr run_batch_failing_touch
    [ "$status" -eq 0 ]
    assert_one_object
    [[ "$(sys_msg)" == *"$SYS_TRIGGER"* ]]
    [[ "$(ctx_msg)" == *"$CTX_TRIGGER"* ]]
    [[ "$(sys_msg)" != *"died with status"* ]]
    [[ "$(ctx_msg)" != *"died with status"* ]]
  done
}
