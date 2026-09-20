#!/usr/bin/env bats
# SessionStart's relay drain: a session's own marker is drained and a peer's
# left standing, aged markers are swept, no-marker runs stay quiet, and an
# unreadable marker costs only the relay, not the hook.
# $stderr is populated by bats `run --separate-stderr`; shellcheck cannot see it.
# shellcheck disable=SC2154
bats_require_minimum_version 1.5.0

load helpers/setup
load helpers/fixtures
load helpers/divergence-fixtures
load helpers/cc-hook-session-start

# The relay drain's framing line, hand-typed here rather than sourced from
# scripts/lib/index-sync.sh's gitlore_relay_drain: sourcing it would move both
# sides together and the positive case would stop pinning the actual wording.
RELAY_FRAMING="--- gitlore-relay agent"

# Drives SESSION_START with a session_id on stdin — the real payload shape,
# which the hook parses to scope its relay drain. $1 = session id.
run_session_start_with_session() {
  jq -n --arg s "$1" '{session_id:$s}' | bash "$SESSION_START"
}

# D51 (revised), slice 2 case 5: SessionStart drains its OWN session's marker
# and leaves a peer session's standing. Both markers sit under a REAL session
# — s1 or s2, neither "nosession" — so a drain that never parses its
# payload's session_id finds neither, and the first positive assertion below
# fails outright rather than passing vacuously; a session-blind drain that
# enumerates every session fails the S2 refutations instead.
@test "session-start drains its own session's marker and leaves a peer session's standing" {
  make_parent_with_memory
  gitlore_relay_write memory s1 a1 sync "S1 SYSMSG BODY" "S1 CTX BODY"
  gitlore_relay_write memory s2 a2 sync "S2 SYSMSG BODY" "S2 CTX BODY"
  s1_marker="$(relay_marker_for memory a1)"
  s2_marker="$(relay_marker_for memory a2)"
  [ -f "$s1_marker" ]
  [ -f "$s2_marker" ]
  mkdir -p .claude
  printf '{"gitlore":{"enabled":true}}\n' > .claude/settings.json
  GITLORE_LAUNCHED=1 run --separate-stderr run_session_start_with_session s1
  [ "$status" -eq 0 ]
  sysmsg="$(printf '%s' "$output" | jq -r '.systemMessage')"
  ctx="$(printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext')"
  [[ "$sysmsg" == *"S1 SYSMSG BODY"* ]]
  [[ "$ctx" == *"S1 CTX BODY"* ]]
  # The framing wording itself, on both channels: `$RELAY_FRAMING` is declared
  # at the head of this file as the string a negative refutes, and a negative
  # refuting a string no positive asserts stops watching anything the day the
  # wording moves. This is the positive that keeps "session-start with no
  # marker emits no relay framing" honest.
  [[ "$sysmsg" == *"$RELAY_FRAMING a1 ---"* ]]
  [[ "$ctx" == *"$RELAY_FRAMING a1 ---"* ]]
  [[ "$sysmsg" != *"S2 SYSMSG BODY"* ]]
  [[ "$ctx" != *"S2 CTX BODY"* ]]
  # Drained means read AND removed: a fold that emitted the block but left the
  # file would relay it again at the next compact or resume.
  [ ! -e "$s1_marker" ]
  [ -f "$s2_marker" ]
}

# D51 (revised), slice 2 case 5, sweep half: SessionStart removes a relay
# file older than 7 days regardless of session — a hook that never calls
# gitlore_relay_sweep reds this on the aged marker surviving.
@test "session-start sweeps a relay file older than 7 days" {
  make_parent_with_memory
  gitlore_relay_write memory old-session a9 sync "OLD BODY" "OLD CTX"
  old_marker=$(relay_marker_for memory a9)
  [ -f "$old_marker" ]
  # BSD `date -v` first; GNU has no `-v` and errors on it, so the `||` falls
  # back to `-d` — provoking the platform mismatch is the detection
  # mechanism, not a routine failure suppression.
  old_ts=$(date -v-10d +%Y%m%d%H%M 2>/dev/null || date -d '10 days ago' +%Y%m%d%H%M)
  touch -t "$old_ts" "$old_marker"
  # The keeper for the assertion below: a sweep that deleted every relay file
  # regardless of age would satisfy `! -e "$old_marker"` and pin nothing. This
  # one is addressed to a session nothing here drains, so only its age can
  # decide it, and its age says keep.
  gitlore_relay_write memory other-session a8 sync "FRESH BODY" "FRESH CTX"
  fresh_marker=$(relay_marker_for memory a8)
  [ -f "$fresh_marker" ]
  mkdir -p .claude
  printf '{"gitlore":{"enabled":true}}\n' > .claude/settings.json
  GITLORE_LAUNCHED=1 run --separate-stderr bash "$SESSION_START"
  [ "$status" -eq 0 ]
  [ ! -e "$old_marker" ]
  [ -f "$fresh_marker" ]
}

@test "session-start with no marker emits no relay framing" {
  # The negative that keeps the positive above honest, over the same fixture
  # differing only in whether a marker exists.
  make_parent_with_memory
  mkdir -p .claude
  printf '{"gitlore":{"enabled":true}}\n' > .claude/settings.json
  GITLORE_LAUNCHED=1 run --separate-stderr bash "$SESSION_START"
  [ "$status" -eq 0 ]
  sysmsg="$(printf '%s' "$output" | jq -r '.systemMessage')"
  ctx="$(printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext')"
  # `jq -r` prints the literal "null" for a key that is not there, so both
  # refutations below would pass on a JSON that had dropped the channel
  # entirely — the negative would keep counting as green while watching
  # nothing. Pin that each channel is present first: the positive above proves
  # this is an observable the drain path really writes to.
  [ "$sysmsg" != "null" ]
  [ "$ctx" != "null" ]
  [[ "$sysmsg" != *"$RELAY_FRAMING"* ]]
  [[ "$ctx" != *"$RELAY_FRAMING"* ]]
}

# Item 3.1 slice 4, Group A (item-3-1-s3-code-review.md "Concern 1", the
# SessionStart half of the shared fixture in tests/index_sync_relay_refusals.bats). A marker
# at mode 0200 is found by the drain's `find -type f` but cannot be opened by
# its `awk`, which exits 2 — and under this file's own `set -euo pipefail`
# that used to take the whole hook down before slice 3's `|| true` landed.
# What that fix does NOT restore is the body: the marker is folded as an
# empty block and removed, so only the drain's own return code is protected.
# This case pins the residual: the hook must still finish and still carry
# everything ELSE accumulated above the fold — the standing FR11
# commit-protocol context most of all, since losing it costs every session
# after this one, not just this batch's relay.
@test "an unreadable marker costs the relay, not the hook" {
  [ "$(id -u)" -eq 0 ] && skip "root ignores permission bits"
  make_parent_with_memory
  # Empty session on both sides: the hook below runs with no payload, so its
  # drain enumerates the `nosession` reports, and the write lands there too.
  if gitlore_relay_write memory "" a1 sync "STRANDED SYSMSG BODY" "STRANDED CTX BODY"; then
    write_status=0
  else
    write_status=$?
  fi
  [ "$write_status" -eq 0 ]
  marker="$(relay_marker_for memory a1)"
  chmod 0200 "$marker"
  mkdir -p .claude
  printf '{"gitlore":{"enabled":true}}\n' > .claude/settings.json
  GITLORE_LAUNCHED=1 run --separate-stderr bash "$SESSION_START"
  # Restore only if the drain left the marker behind — its `rm -f` removes it
  # regardless of its mode, since deletion depends on the containing
  # directory's permissions, not the target file's.
  [ -e "$marker" ] && chmod 0600 "$marker"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.hookSpecificOutput.additionalContext | test("never commit"; "i")'
  # The drain reached the marker: a drain enumerating nothing never opens it,
  # and the two assertions above hold with no drain at all.
  [ ! -e "$marker" ]
}

# A third case — "a stranded marker is the only thing SessionStart has to
# say" — is in the runbook item (emit_session_json omits systemMessage
# entirely when $sysmsg is empty, so a fold placed after that decision, or one
# appending to the wrong variable, would leave the relay unemitted on exactly
# the session where it is the only news). No fixture reaches emit_session_json
# with $sysmsg empty: every branch of the `gitlore_memory_dirty` if/elif/else
# at session-start.sh:193-212 calls add_sysmsg before falling through (or
# before its own early emit_session_json + exit 0) — "memory ready", "…
# uncommitted changes…", "diverged", or "could not be fast-forwarded" — and
# every path that reaches the bottom of the script passed through exactly one
# of those branches. A guard-failure fixture (no settings.json, disabled,
# unregistered submodule) exits before mempath is even resolved and emits no
# JSON at all (assert_session_start_did_nothing), not an empty-systemMessage
# JSON. So $sysmsg is unconditionally non-empty at every emit_session_json
# call site this hook has today, and a case asserting the relay alone drives
# systemMessage would be vacuous by construction — not a red, a tautology.
# Measured, not read: an instrumented emit_session_json driven by every fixture
# in this suite and the nine others that run the hook logged 52 emits across
# all three call sites, none with $sysmsg empty.
#
# The case is also not NEEDED for the two bugs it was specified to catch. A
# fold placed after emit_session_json, and one appending to the wrong variable,
# each red the positive above on its first assertion. What no case here pins —
# and what today's code cannot tell apart from correct — is a fold nested
# inside an `[ -n "$sysmsg" ]` guard: behaviour-identical while all four dirty
# branches report, and silently dropping the relay the day one stops.
