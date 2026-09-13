# RED: relay redesign, slice 1 (library)

Per `plans/index-edit-propagation/relay-redesign.md` §Slices, Slice 1. New
argument-position stubs in `scripts/lib/index-sync.sh`:
`gitlore_relay_write mempath session agent tag sysmsg ctx`,
`gitlore_relay_drain mempath session`, inert `gitlore_relay_sweep mempath`;
`gitlore_relay_marker_file` retired (replaced by a private, unexported
`_gitlore_relay_stub_file`, RED-only). Six new/rewritten cases and four adapted
regression cases in `tests/index_sync.bats`, section
`--- relay markers (Item 3.1/D51 revision) ---`. Command:
`scripts/run-bats.sh tests/index_sync.bats` — 77 passed, 7 failed.

## The six spec cases

### 1 — `relay_write: two writes under one agent in one session yield two files, drained together in write order`

Red on **`[ "$count" -eq 2 ]`** (tests/index_sync.bats:950), counting
`gitlore-relay-*` files (excluding `.tmp`) after two writes, before the drain:
```
not ok relay_write: two writes under one agent in one session yield two files, drained together in write order
# (in test file tests/index_sync.bats, line 950)
#   `[ "$count" -eq 2 ]' failed
```
The stub still keys a relay file on the agent id alone
(`_gitlore_relay_stub_file`) and merges a second write into the first, so two
writes for the same agent land on one file, not two.

### 2 (C2) — `relay_write: 20 concurrent writes for one agent are not lost by the drain`

Red on **`[ "$output" -eq 20 ]`** (tests/index_sync.bats:989), the framing-line
count after 20 `gitlore_relay_write` calls backgrounded (`&`) then `wait`ed, one
drain:
```
not ok relay_write: 20 concurrent writes for one agent are not lost by the drain
# (in test file tests/index_sync.bats, line 989)
#   `[ "$output" -eq 20 ]' failed
```
Confirmed to fail reliably across 3 runs. The stub's 20 writers race on the
*same* `$marker.tmp` path (agent-keyed, session-blind), which produces both lost
updates and `mv: cannot stat …/gitlore-relay-a1.tmp: No such file or directory`
noise on stderr — a stronger failure than the review's 86/200 measurement for
two writers, expected from 20-way contention on one shared temp path rather than
the eventual per-call-unique name the design specifies.

**Flag for slice 1 GREEN**: the design names the file as
`gitlore-relay-<S>-<A>-<epoch>-<pid>-<H>`. Within one process, `$$` in bash is
fixed at shell startup and does **not** change inside a `foo &` background job —
only `$BASHPID` does. Two `gitlore_relay_write` calls from the same shell, same
session, same agent, same tag, landing in the same wall-clock second (very
plausible for two hooks racing in one batch, or for this suite's own concurrency
test) would collide on `$$` unless GREEN uses `$BASHPID` (or another per-call
discriminator) instead of `$$`. Not fixed here — slice 1 GREEN is out of scope
for this RED pass — but worth settling before implementing the naming scheme.

### 3 — `relay_drain: a write for session S2 is not drained by S1 and survives it`

Red on **`[[ "$GITLORE_RELAY_SYSMSG" != *"S2-BODY"* ]]`**
(tests/index_sync.bats:1018):
```
not ok relay_drain: a write for session S2 is not drained by S1 and survives it
# (in test file tests/index_sync.bats, line 1018)
#   `[[ "$GITLORE_RELAY_SYSMSG" != *"S2-BODY"* ]]' failed
```
Writes use different agent ids (`a1`/s1, `a2`/s2) so the write-side merge bug
can't also explain the failure — the case isolates the drain's blindness to its
own `session` argument: it enumerates every keyed file regardless of session, so
`gitlore_relay_drain memory s1` drains and removes S2's file too.

### 4 — `.tmp` beside the markers neither folded nor removed

**Does not red — passes today**
(`relay_drain: a .tmp beside the markers is neither folded nor removed, over a gitdir path holding a space`,
born green). The pre-revision `.tmp` exclusion in `gitlore_relay_drain`'s `find`
is unchanged by this stub, so the assertion already holds. Kept per the task's
instruction to report rather than force or drop a case that can't red against
the stub — this is real coverage of a contract clause the redesign keeps, not a
vacuous check. Built over a gitdir path holding a space, reusing the existing
spaced-path fixture shape as instructed (the only case in the new section built
out of line via `_gitlore_build_parent_with_memory`).

### 5 — `relay_sweep: removes a gitlore-relay marker older than 7 days, leaves a fresh one and an old .tmp alone`

Red on **`[ ! -e "$old" ]`** (tests/index_sync.bats:1099):
```
not ok relay_sweep: removes a gitlore-relay marker older than 7 days, leaves a fresh one and an old .tmp alone
# (in test file tests/index_sync.bats, line 1099)
#   `[ ! -e "$old" ]' failed
```
`gitlore_relay_sweep` is the inert stub the task specified (no-op, returns 0),
so the 7-day-aged marker (`touch -t`, portable via `date -v`/`date -d` fallback)
is never removed.

### 6 — `relay_write: empty agent id refused; empty session and "nosession" reach each other`

**Does not red — passes today.** The empty-agent-id refusal is unchanged
pre-revision behaviour (`[ -n "$agent" ] || return 1`), so that half was never
expected to red. The "nosession" half is explicitly **not exercised** by the
stub: both `gitlore_relay_write` and `gitlore_relay_drain` accept `session` at
its new position but ignore it entirely per the task's stub instructions, so a
write with an empty session and a drain keyed `"nosession"` trivially "reach"
each other — the stub drains everything regardless of the session argument (the
same mechanism case 3 catches). Disclosed per `craft:test-discipline` rather
than forced or dropped; the assertion is real and will bind once GREEN
implements the mapping.

## Kept regression cases (survive per the runbook's keep-list, adapted to the new signatures)

All four pass:
- `relay_drain on an empty store sets both variables empty and returns 0`
- `an unreadable marker costs the relay, not the hook`
- `relay_write does not destroy a staged report when its temp cannot be written`
- `the drain survives a gitdir it cannot write` — not individually named in the
  runbook's keep-list (only the three above were), but its own behaviour (drain
  returns 0 even when the gitdir's own `rm -f` fails) survives the revision the
  same way theirs does, so it's kept here too rather than dropped. Flagging the
  addition in case the omission was deliberate rather than incidental.

Marker discovery in all four now goes through
`find … -name 'gitlore-relay-*' '!' -name '*.tmp'` rather than the retired
`gitlore_relay_marker_file`.

## Retired cases

Per the runbook's retire-list: `relay_marker_file suffixes the agent id`,
`relay_write merges a second report into an existing marker`,
`relay_write refuses a squatted marker path`,
`relay_write joins a channel only when the old body is non-empty`,
`relay_drain folds two markers in filename order, over a gitdir path holding a space`,
and the three `.tmp` cases (`relay_drain does not fold a stranded .tmp marker`,
`relay_drain still folds a real marker standing beside a stranded .tmp`,
`relay_drain removes a .tmp stranded alongside the marker it drains`) — all
encode the old merge-or-fold-on-unkeyed contract the revision replaces.

## Collateral scope — wider than the one named exception, now narrowed back down

The runbook named one hook-level case to leave alone this slice
(`an unkeyed index-sync run with no report of its own still emits the relay`,
"slice 2 replaces it"). Changing the library signatures initially broke far more
than that one case: `scripts/cc-hooks/index-sync-post.sh` calls
`gitlore_relay_drain "$mempath"` **unconditionally on every batch** (not only a
keyed one), so under the suite's `set -euo pipefail` a bare `$2` inside the
new-signature function aborted that hook script outright — not a designed red,
just a crash — on every test that exercises `index-sync-post.sh` at all. First
full run: 37 failed, of which only 4 were genuine spec reds; the other 33 were
`post:`/`e2e:`-prefixed tests entirely unrelated to the relay (budget-warning
nudges, weak-line flagging, frontmatter propagation) plus three hook-level relay
tests.

Fixed without touching anything under `scripts/cc-hooks/*` (out of scope): both
stub functions now default every parameter past `$1` with `${N:-}` instead of a
bare `$N`, so a caller still on the old, shorter argument list gets empty
strings for the positions it doesn't supply instead of an unbound-variable
abort. This changes nothing about the stub's *behaviour* under the new contract
(session/tag were already ignored) — it only stops an out-of-scope,
not-yet-updated caller from crashing the whole hook on every run. Second full
run: 7 failed — the 4 genuine reds above, plus exactly three hook-level relay
tests that still call the now-retired `gitlore_relay_marker_file` directly and
are left alone as instructed:

```
not ok a keyed index-sync run writes its replacement report to a marker
# tests/index_sync.bats:740 — gitlore_relay_marker_file: command not found (status 127)
not ok an unkeyed index-sync run folds in the marker
# tests/index_sync.bats:758 — gitlore_relay_marker_file: command not found (status 127)
not ok an unkeyed index-sync run with no report of its own still emits the relay
# tests/index_sync.bats:803 — gitlore_relay_marker_file: command not found (status 127)
```

The first two were not individually named in the runbook's leave-alone
instruction (only the third was) — extended to all three since they're the same
category (hook-level relay tests exercising `index-sync-post.sh` through
`PRE`/`post_stdin`) and none can pass without touching `scripts/cc-hooks/*`,
which is out of scope this slice. Flagging the extension in case the narrower
reading was intended.

## Verification

- `bash -n scripts/lib/index-sync.sh` — OK.
- `shellcheck scripts/lib/index-sync.sh` and
  `shellcheck -x tests/index_sync.bats` — both clean.
- `bats --count tests/index_sync.bats` — 84 (unchanged from before the edit,
  confirming the file still parses as a whole).
- Full run: `scripts/run-bats.sh tests/index_sync.bats` — 77 passed, 7 failed (4
  genuine spec reds + 3 acknowledged hook-level casualties, see above).
- No `just precommit`, `just lint`, or commit run, per the task's scope.
