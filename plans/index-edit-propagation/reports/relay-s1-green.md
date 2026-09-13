# GREEN: relay redesign, slice 1 (library)

Per `plans/index-edit-propagation/relay-redesign.md` §Slices, Slice 1, and
`plans/index-edit-propagation/reports/relay-s1-red.md` /
`relay-s1-test-review.md`. Implements `gitlore_relay_write`,
`gitlore_relay_drain`, `gitlore_relay_sweep` in `scripts/lib/index-sync.sh` per
D51 (revised); retires `_gitlore_relay_stub_file`. One test fix (below). Nothing
committed, no branch touched, `just precommit` not run — orchestrator owns the
commit and full gate per the task frame.

## Per-test result, `tests/index_sync.bats` §relay markers

All six spec cases pass, made green one at a time in the RED report's order,
then confirmed together:

1. `relay_write: two writes under one agent in one session yield two files, drained together in write order`
   — pass
2. `relay_write: 20 concurrent writes for one agent are not lost by the drain` —
   pass (3 consecutive runs, no flake)
3. `relay_drain: a write for session S2 is not drained by S1 and survives it` —
   pass
4. `relay_drain: a .tmp beside the markers is neither folded nor removed, over a gitdir path holding a space`
   — pass (was already green against the RED stub)
5. `relay_sweep: removes relay files older than 7 days, temps included, and leaves fresh ones alone`
   — pass
6. `relay_write: empty agent id refused; empty session and "nosession" reach each other`
   — pass

Kept regression cases, all pass:
- `relay_drain on an empty store sets both variables empty and returns 0`
- `an unreadable marker costs the relay, not the hook`
- `the drain survives a gitdir it cannot write`
- `relay_write does not destroy a staged report when its temp cannot be written`
  — required a test fix, see below.

## A real bug, caught by the last kept-regression case

Initial implementation folded `${BASHPID:-$$}` directly into the argument of
`marker=$(git -C "$mempath" rev-parse --git-path "...-${BASHPID:-$$}-...")`. A
command substitution forks, and that fork happens before its argument list is
expanded — so `${BASHPID:-$$}` was being read *inside the forked subshell*,
giving every single call to `gitlore_relay_write` its own fresh PID, even from
one process, rather than the calling process's PID. Two sequential writes from
the same shell landed on two different names instead of the one collision the
"does not destroy a staged report" case (and D51's own same-second/same-process
residual) depends on.

Fixed by capturing `pid=${BASHPID:-$$}` as a bare assignment (no fork) before
the `git rev-parse` call, so it reflects the calling process throughout.
Confirmed against `tests/index_sync.bats:1288-1310` and a scratch debug case run
standalone (now deleted) that printed the two marker names directly.

## Test fix: `relay_write does not destroy a staged report when its temp cannot be written`

`tests/index_sync.bats:1285` (now 1288-1310). Both `gitlore_relay_write` calls
were wrapped in `run`, which itself forks a subshell per invocation — so even
with the PID bug above fixed, two `run gitlore_relay_write` calls would still
carry two different `$BASHPID` values and never collide on the name the test
squats. This case's whole mechanism depends on the SECOND write landing on the
SAME name as the first (same session/agent/tag/epoch/ pid), so it needs both
calls in one process with no subshell in between. Changed both
`run gitlore_relay_write ...` / `[ "$status" -eq/-ne 0 ]` pairs to direct
invocation with `rc=$?`, the pattern already used elsewhere in this file for
calls whose status must be checked in the current shell. No assertion content
changed — verified failing on the RED stub's shorter argument shape is
unaffected (the stub's key was agent-only, so the pre-fix form happened to pass
by accident; this fix makes the pass mechanism match what the case's own
comments already claimed).

Flagging this as an edit to a test, per the task's instruction, since it touches
assertion mechanics rather than pure formatting — though the assertions
themselves (`[ "$rc" -eq 0 ]` / `[ "$rc" -ne 0 ]` and everything after) are
unchanged in meaning from `[ "$status" -eq 0 ]` / `[ "$status" -ne 0 ]`.

## Full suite

`scripts/run-bats.sh tests/index_sync.bats`, 3 consecutive runs, identical
result each time:

```
81 passed, 3 failed
```

The 3 failures are exactly the expected slice-2 collateral (hook-level cases
still calling the retired `gitlore_relay_marker_file`, out of scope —
`scripts/cc-hooks/*`):

```
not ok 44 a keyed index-sync run writes its replacement report to a marker
# tests/index_sync.bats:738 — [ "$status" -eq 0 ] failed
not ok 45 an unkeyed index-sync run folds in the marker
# tests/index_sync.bats:758 — gitlore_relay_marker_file: command not found (status 127)
not ok 46 an unkeyed index-sync run with no report of its own still emits the relay
# tests/index_sync.bats:803 — gitlore_relay_marker_file: command not found (status 127)
```

Case 44 (`a keyed index-sync run writes its replacement report to a marker`) now
fails one line earlier than the RED report predicted (738: a `jq` parse failure
on `$json`, rather than 740's `command not found`). Cause: this case drives
`index-sync-post.sh`, still calling `gitlore_relay_write` with its OLD 4-arg
shape (`mempath agent_id sysmsg ctx`). Under the new signature that maps to
`session=agent_id, agent=sysmsg-text, tag=ctx-text`, so `tag` (H) — passed
through unsanitized per D51 — ends up holding the hook's full, unsanitized
`additionalContext` body, hundreds of bytes with a newline. That overruns the
filesystem's per-component name limit and the write fails with a bash-level
`File name too long` message on stderr, which `run` merges into `$output` ahead
of the hook's own JSON, breaking `jq`'s parse before the test even reaches its
`gitlore_relay_marker_file` call. Same root cause the RED report named (the
OLD-shape callers are out of scope this slice, slice 2 updates them), just a
different symptom of it — still within the accepted collateral, not a new
regression outside it. `bats --count tests/index_sync.bats` is unchanged at 84,
confirming no case was dropped.

## Lint

`shellcheck scripts/lib/index-sync.sh` and
`shellcheck -x tests/index_sync.bats`: clean. `just lint`:
`lint-shell: 137 files clean`. `bash -n scripts/lib/index-sync.sh`: OK.

## Scope

Touched: `scripts/lib/index-sync.sh`, `tests/index_sync.bats` (one test's
invocation mechanics, per above). Nothing under `scripts/cc-hooks/*`,
`hooks/hooks.json`, `tests/cc_hook_*.bats`, `tests/plugin_distribution.bats`, or
`docs/` — `git diff --stat` confirms exactly the two files.
