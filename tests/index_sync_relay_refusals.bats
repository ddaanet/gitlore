#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031
# Relay marker refusals — the session/agent-id mapping, bad tags, occupied
# names, path traversal — and the robustness cases carried over from before
# the D51 revision. Continues from tests/index_sync_relay.bats.

load helpers/setup
load helpers/fixtures
load helpers/index-sync

# shellcheck disable=SC1090
setup() { setup_tmp_repo; . "$SRC"; }
teardown() { teardown_tmp_repo; }

# 6: empty agent id refused; empty session maps to "nosession" on both sides.
@test "relay_write: empty agent id refused; empty session and \"nosession\" reach each other" {
  make_parent_with_memory
  gitdir=$(git -C memory rev-parse --absolute-git-dir)

  # Born green — the refusal is unchanged pre-revision behaviour, so the
  # ordering supplies no red. Shown to discriminate by mutation: replacing
  # `[ -n "$agent" ] || return 1` in gitlore_relay_write with a no-op reds
  # this `[ "$status" -ne 0 ]`.
  run gitlore_relay_write memory s1 "" sync "S" "C"
  [ "$status" -ne 0 ]
  count=0
  while IFS= read -r -d '' _; do
    count=$((count + 1))
  done < <(find "$gitdir" -maxdepth 1 -type f -name 'gitlore-relay*' -print0)
  [ "$count" -eq 0 ]

  # Empty session maps to "nosession" on both sides — a write with no session
  # id, drained under the literal session id "nosession", must reach it.
  run gitlore_relay_write memory "" a1 sync "NOSESSION-BODY" "NOSESSION-CTX"
  [ "$status" -eq 0 ]

  # The write side of the mapping, asserted on the name D51 states:
  # `gitlore-relay-<S>-<A>-<epoch>-<pid>-<H>` with `S` = "nosession". Red on
  # the RED stub, which keys on the agent id alone and writes
  # `gitlore-relay-a1`. Without this, the "reach each other" assertion below
  # is vacuous against a stub that ignores the session argument on BOTH
  # sides: a drain that enumerates everything reaches a write that recorded
  # nothing, and neither half of the mapping is exercised.
  name=$(find "$gitdir" -maxdepth 1 -type f -name 'gitlore-relay-*' '!' -name '*.tmp' -print)
  [ -n "$name" ]
  [[ "${name##*/}" == gitlore-relay-nosession-a1-* ]]

  # The drain side. Still cannot red on its own before GREEN scopes the
  # enumeration by session — it binds on that scoping, and case 3 is what
  # proves the scoping exists at all.
  rc=0
  gitlore_relay_drain memory nosession || rc=$?
  [ "$rc" -eq 0 ]
  [[ "$GITLORE_RELAY_SYSMSG" == *"NOSESSION-BODY"* ]]
  [[ "$GITLORE_RELAY_CTX" == *"NOSESSION-CTX"* ]]

  # The reverse half: a write under the literal session id "nosession",
  # drained with an empty session, reaches it. The two halves pin the mapping
  # in both directions. The drain runs bare, not under `run`: it reports
  # through GITLORE_RELAY_SYSMSG and GITLORE_RELAY_CTX, which `run`'s
  # subshell would lose.
  run gitlore_relay_write memory nosession a2 sync "LITERAL-BODY" "LITERAL-CTX"
  [ "$status" -eq 0 ]
  rc=0
  gitlore_relay_drain memory "" || rc=$?
  [ "$rc" -eq 0 ]
  [[ "$GITLORE_RELAY_SYSMSG" == *"LITERAL-BODY"* ]]
  [[ "$GITLORE_RELAY_CTX" == *"LITERAL-CTX"* ]]
}

# 7 (flagged in relay-s1-code-review.md "The tag guard ships untested"): a tag
# outside {sync, compose} is a caller mistake, not a hook-payload field, so
# gitlore_relay_write refuses it rather than sanitizing it — validated here
# rather than merely assumed from the code review's read of the guard.
@test "relay_write: a tag outside {sync, compose} is refused and leaves no file" {
  make_parent_with_memory
  gitdir=$(git -C memory rev-parse --absolute-git-dir)
  rc=0
  gitlore_relay_write memory s1 a1 bogus "S" "C" || rc=$?
  [ "$rc" -ne 0 ]
  run find "$gitdir" -maxdepth 1 -type f -name 'gitlore-relay-*'
  [ -z "$output" ]
}

# D51 refuses an install onto an occupied name, and the `-e` check ahead of
# the `mv` is what carries it: `mv` onto a file replaces an earlier report,
# and `mv` onto a directory moves the temp inside it, both returning 0. The
# name is made predictable the way the staged-report case below makes it:
# `date` frozen and every write from this one process.
@test "relay_write refuses a final name already occupied, by a report or a directory" {
  make_parent_with_memory
  gitdir=$(git -C memory rev-parse --absolute-git-dir)
  fakebin="$BATS_TEST_TMPDIR/fakebin"
  mkdir -p "$fakebin"
  real_date=$(command -v date)
  cat > "$fakebin/date" <<EOF
#!/bin/sh
case "\$1" in
  +%s) echo 1700000000; exit 0 ;;
esac
exec "$real_date" "\$@"
EOF
  chmod +x "$fakebin/date"
  saved_path="$PATH"
  PATH="$fakebin:$PATH"

  rc=0
  gitlore_relay_write memory s1 a1 sync "FIRST-S" "FIRST-C" || rc=$?
  [ "$rc" -eq 0 ]
  marker=$(find "$gitdir" -maxdepth 1 -type f -name 'gitlore-relay-*' '!' -name '*.tmp' -print)
  [ -n "$marker" ]
  before=$(cat "$marker")

  rc=0
  gitlore_relay_write memory s1 a1 sync "SECOND-S" "SECOND-C" || rc=$?
  [ "$rc" -ne 0 ]
  [ "$(cat "$marker")" = "$before" ]
  [ ! -e "$marker.tmp" ]

  squat="$gitdir/gitlore-relay-s1-a2-1700000000-${BASHPID:-$$}-sync"
  mkdir "$squat"
  rc=0
  gitlore_relay_write memory s1 a2 sync "SQUAT-S" "SQUAT-C" || rc=$?
  PATH="$saved_path"
  [ "$rc" -ne 0 ]
  [ -z "$(ls -A "$squat")" ]
  [ ! -e "$squat.tmp" ]
}

# Only a regular file on a relay name is a report. A directory there must
# not be framed as a block for an agent that staged nothing, and `rm -f`
# cannot remove it, so framing it would repeat on every later drain.
@test "relay_drain frames no block for a directory on a relay name" {
  make_parent_with_memory
  gitdir=$(git -C memory rev-parse --absolute-git-dir)
  run gitlore_relay_write memory s1 a1 sync "REAL-S" "REAL-C"
  [ "$status" -eq 0 ]
  mkdir "$gitdir/gitlore-relay-s1-a9-1-1-sync"

  rc=0
  gitlore_relay_drain memory s1 || rc=$?
  [ "$rc" -eq 0 ]
  [[ "$GITLORE_RELAY_SYSMSG" == *"REAL-S"* ]]
  [[ "$GITLORE_RELAY_SYSMSG" != *"agent a9"* ]]
  [[ "$GITLORE_RELAY_CTX" != *"agent a9"* ]]
  [ -d "$gitdir/gitlore-relay-s1-a9-1-1-sync" ]
}

# The relay name splices both ids from the hook payload. Sanitized, a `/` or a
# `..` in either stays one filename component inside the gitdir; spliced raw,
# it walks the write out of it.
@test "relay_write sanitizes the session and agent ids into one name inside the gitdir" {
  make_parent_with_memory
  gitdir=$(git -C memory rev-parse --absolute-git-dir)
  session='../s 1/..'
  agent='../../a/b'
  s_safe=$(printf '%s' "$session" | LC_ALL=C tr -c 'A-Za-z0-9-' '_')
  a_safe=$(printf '%s' "$agent" | LC_ALL=C tr -c 'A-Za-z0-9-' '_')

  run gitlore_relay_write memory "$session" "$agent" sync "ODD-S" "ODD-C"
  [ "$status" -eq 0 ]
  name=$(find "$gitdir" -maxdepth 1 -type f -name 'gitlore-relay-*' '!' -name '*.tmp' -print)
  [ -n "$name" ]
  [[ "${name##*/}" == "gitlore-relay-$s_safe-$a_safe-"* ]]

  rc=0
  gitlore_relay_drain memory "$session" || rc=$?
  [ "$rc" -eq 0 ]
  [[ "$GITLORE_RELAY_SYSMSG" == *"ODD-S"* ]]
}

# --- relay markers: robustness cases carried over, adapted to the new signatures
#
# Behaviour that survives the D51 revision unchanged, kept as regression pins.
# `the drain survives a gitdir it cannot write` was not individually named in
# the runbook's keep-list (only the three above it were), but its own
# behaviour survives the revision the same way theirs does, so it is kept
# here too rather than dropped.

@test "relay_drain on an empty store sets both variables empty and returns 0" {
  make_parent_with_memory
  # Sentinels, not the birth state: a drain that leaves the variables alone
  # when it finds nothing would re-emit whatever the previous drain left in
  # them. The decoy is a real neighbour in the same gitdir, so a `gitlore-*`
  # glob deletes the compose baseline and fails here rather than in Item 2.1's
  # cases.
  GITLORE_RELAY_SYSMSG="STALE-SYS"
  GITLORE_RELAY_CTX="STALE-CTX"
  decoy=$(gitlore_compose_stamp_file memory)
  : > "$decoy"

  rc=0
  gitlore_relay_drain memory s1 || rc=$?
  [ "$rc" -eq 0 ]
  [ -z "$GITLORE_RELAY_SYSMSG" ]
  [ -z "$GITLORE_RELAY_CTX" ]
  [ -f "$decoy" ]
}

@test "an unreadable marker costs the relay, not the hook" {
  [ "$(id -u)" -eq 0 ] && skip "root ignores permission bits"
  make_parent_with_memory
  gitdir=$(git -C memory rev-parse --absolute-git-dir)
  run gitlore_relay_write memory s1 a1 sync "S" "C"
  [ "$status" -eq 0 ]
  marker=$(find "$gitdir" -maxdepth 1 -type f -name 'gitlore-relay-*' '!' -name '*.tmp' -print)
  [ -n "$marker" ]
  chmod 0200 "$marker"

  # Plain `run`, not `run --separate-stderr`: awk's "Permission denied" is on
  # stderr on every run of this fixture and lands in $output, but the assertion
  # below is a substring on the synthetic hook's own line, which no diagnostic
  # supplies. `--separate-stderr` would also stop shellcheck recognising
  # `bash -c` and linting the script below, trading that for nothing.
  run bash -c '
    set -euo pipefail
    # shellcheck disable=SC1090
    . "$1"
    gitlore_relay_drain "$2" s1
    printf "OWN REPORT\n"
  ' _ "$SRC" "$PWD/memory"
  # Guarded, not unconditional: a fixed drain folds the unreadable marker as an
  # empty block and removes it, and a bare chmod would then fail on a missing
  # path — killing the test on its own cleanup instead of on an assertion.
  [ -e "$marker" ] && chmod 0600 "$marker"

  [ "$status" -eq 0 ]
  [[ "$output" == *"OWN REPORT"* ]]
  [ ! -e "$marker" ]
}

@test "the drain survives a gitdir it cannot write" {
  [ "$(id -u)" -eq 0 ] && skip "root ignores permission bits"
  make_parent_with_memory
  gitdir=$(git -C memory rev-parse --absolute-git-dir)
  run gitlore_relay_write memory s1 a1 sync "S" "C"
  [ "$status" -eq 0 ]
  # r-x, no w: `find` can still enumerate and `awk` can still read the marker
  # (both need only read+execute on the directory), but the drain's `rm -f`
  # needs write on the directory it lives in, which this removes.
  chmod 0500 "$gitdir"

  run bash -c '
    set -euo pipefail
    # shellcheck disable=SC1090
    . "$1"
    gitlore_relay_drain "$2" s1
    printf "OWN REPORT\n"
  ' _ "$SRC" "$PWD/memory"

  # Guarded, not unconditional — see the marker-mode case above for why.
  [ -e "$gitdir" ] && chmod 0700 "$gitdir"

  [ "$status" -eq 0 ]
  [[ "$output" == *"OWN REPORT"* ]]
}

@test "relay_write does not destroy a staged report when its temp cannot be written" {
  make_parent_with_memory
  gitdir=$(git -C memory rev-parse --absolute-git-dir)
  # Both writes invoked directly, never through `run`: `run` forks its
  # command into its own subshell, so two `run gitlore_relay_write` calls
  # would carry two different `$BASHPID` values and land on two different
  # names — this case needs the SECOND write to target the SAME name as the
  # first, which only holds when both calls share one process.
  #
  # Same pid is not enough: the name also carries `date +%s`, so whenever the
  # two calls straddle a second boundary the second one picks a fresh name,
  # misses the squat and succeeds — measured at 4 failures in 25 runs before
  # this stub went in. Freezing the epoch makes the collision the fixture's
  # own construction rather than a coincidence of timing. The stub delegates
  # every other invocation to the real binary so nothing else shifts.
  fakebin="$BATS_TEST_TMPDIR/fakebin"
  mkdir -p "$fakebin"
  real_date=$(command -v date)
  cat > "$fakebin/date" <<EOF
#!/bin/sh
case "\$1" in
  +%s) echo 1700000000; exit 0 ;;
esac
exec "$real_date" "\$@"
EOF
  chmod +x "$fakebin/date"
  saved_path="$PATH"
  PATH="$fakebin:$PATH"

  rc=0
  gitlore_relay_write memory s1 a1 sync "S1" "C1" || rc=$?
  [ "$rc" -eq 0 ]
  marker=$(find "$gitdir" -maxdepth 1 -type f -name 'gitlore-relay-*' '!' -name '*.tmp' -print)
  [ -n "$marker" ]
  before=$(cat "$marker")

  # The atomic write builds the new marker at `$marker.tmp` and only then
  # renames it into place; squatting that path with a directory makes the
  # write fail with the marker itself never opened.
  mkdir "$marker.tmp"

  rc=0
  gitlore_relay_write memory s1 a1 sync "S2" "C2" || rc=$?
  PATH="$saved_path"
  [ "$rc" -ne 0 ]

  # The squat is untouched (nothing landed there) and the FIRST report is
  # still on disk byte for byte -- S2/C2 never overwrote it.
  [ -d "$marker.tmp" ]
  [ "$(cat "$marker")" = "$before" ]
}
