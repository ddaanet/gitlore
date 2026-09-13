# RED test review: relay redesign, slice 1

Review of `tests/index_sync.bats`
§`--- relay markers (Item 3.1/D51 revision) ---` and the adapted regression
cases, against `plans/index-edit-propagation/relay-redesign.md` §Slices slice 1
and `plans/index-edit-propagation/reports/relay-s1-red.md`. The RED-only stub in
`scripts/lib/index-sync.sh` was read for stub completeness and is **unchanged**
by this review (`diff` against a pre-review copy: identical). Nothing committed,
no branch touched.

Verdict: fixed, red on assertions, with two design findings for the team lead
before GREEN starts.

## Mechanical check

`scripts/run-bats.sh tests/index_sync.bats`, before any fix:
**77 passed, 7 failed**, matching the RED report exactly. Every case the report
lists as red FAILED on an assertion; none PASSED, none errored on a missing
symbol. The three hook-level casualties (`tests/index_sync.bats:740,758,803`,
status 127 on the retired `gitlore_relay_marker_file`) are slice-2 collateral as
stated, left alone.

After the fixes below: **76 passed, 8 failed** — five genuine spec reds, the
same three slice-2 casualties. Case 4 is born green with a mutation proof
recorded below.

| case | line | red on |
| --- | --- | --- |
| 1 two writes → two files | `tests/index_sync.bats:960` | `[ "$count" -eq 2 ]` |
| 2 concurrency | `tests/index_sync.bats:1027` | `[ "$output" -eq 20 ]` |
| 3 session scoping | `tests/index_sync.bats:1056` | `[[ "$GITLORE_RELAY_SYSMSG" != *"S2-BODY"* ]]` |
| 4 `.tmp` untouched | `tests/index_sync.bats:1079` | born green, mutation-proved |
| 5 sweep | `tests/index_sync.bats:1140` | `[ ! -e "$old" ]` |
| 6 empty agent / nosession | `tests/index_sync.bats:1184` | `[[ "${name##*/}" == gitlore-relay-nosession-a1-* ]]` (new) |

## Fixes applied

**Case 2 — writers are now processes, not subshells.** The 20 writers were
`gitlore_relay_write … &` background subshells of the bats shell. Every such
subshell reports the same `$$`, and `$BASHPID` — the only per-subshell
alternative — does not exist on bash 3.2, a target. Under D51's
`<epoch>-<pid>-<H>` naming all 20 would therefore have collided on one name and
the case would have failed on GREEN for a reason production never has, since
each production writer is its own hook process. Rewritten as 20
`bash -c '… . "$1"; gitlore_relay_write …' _ "$SRC" "$PWD/memory" "$i" &`
processes. Still red on `[ "$output" -eq 20 ]` across **3 consecutive runs**,
and the writers demonstrably reach the library (the stub's `mv` diagnostics
appear). Bare `wait` returns 0 whatever the children returned, which is
deliberate and now stated in a comment: a per-writer status check would red the
case on the writers' exits before the recovery assertion ran, and a lost write
shows up as a missing body regardless.

**Case 1 — a second between the two writes.** Two writes agreeing on session,
agent, tag and wall-clock second collide on one name under D51's fixed format,
and D51 refuses an install onto an occupied path, so the case as written could
not have gone green. `sleep 1` separates them on the one field the test
controls. The same field is what the write-order assertion rests on: filename
order is write order only because the epochs differ.

**Framing line pinned exactly.** Cases 1 and 2 now use `grep -c -x` on
`--- gitlore-relay agent <A> ---`. A substring match would also accept a frame
carrying the session, epoch or tag alongside the agent id, which is not the
format D51 states.

**Case 1 agent id carries a dash** (`a-1`). D51 claims the `A` recovery — strip
`gitlore-relay-<S>-`, then `${rest%-*-*-*}` — is unambiguous for a dashed id,
and nothing in the slice exercised that claim. The plausible wrong recovery,
cutting at the first dash, frames `a` and reds case 1's `-x` grep. It binds at
GREEN only: on the RED stub case 1 dies earlier, at the file count, so no
mutation can reach it this slice. Stated in the case comment.

**Case 6 — the `nosession` write side now reds.** Added an assertion on the name
D51 states, `gitlore-relay-nosession-a1-*`. Without it the "reach each other"
assertion was vacuous against a stub that ignores the session argument on both
sides: a drain that enumerates everything reaches a write that recorded nothing,
so neither half of the mapping was exercised. Also added the missing
`GITLORE_RELAY_CTX` half, and a comment naming what the drain side binds on
(GREEN's per-session enumeration, which case 3 is what proves exists).

**Case 5 — the `.tmp` and freshness assertions now name what fails them** (see
the finding below).

## Mutation proofs for the born-green cases

Each mutation was applied to `scripts/lib/index-sync.sh` **in place**, run, then
restored from a saved copy.

- **Case 4, "not folded":** dropping `'!' -name '*.tmp'` from
  `gitlore_relay_drain`'s `find` → red on
  `[[ "$GITLORE_RELAY_SYSMSG" != *"TORN-BODY"* ]]`.
- **Case 4, "not removed":** widening the per-marker `rm -f "$marker.tmp"` to
  `rm -f "$gitdir"/gitlore-relay-*.tmp`, the plausible "clean up strays" form →
  red on `[ -e "$tmp" ]`. The first mutation dies before this assertion, so both
  halves needed their own mutation; neither is decoration.
- **Case 6, empty agent:** replacing `[ -n "$agent" ] || return 1` with a no-op
  → red on `[ "$status" -ne 0 ]`.

Both mutations are recorded in the case comments so a later reader can recover
the evidence from the artifact.

## Checks that found nothing to fix

- **Out-params.** Every `gitlore_relay_drain` call that reads
  `GITLORE_RELAY_SYSMSG`/`_CTX` is invoked bare with `|| rc=$?`, never under
  `run` — `run` is a subshell and the variables would never reach the test.
- **Negative assertions are paired.** Cases 3, 4 and 6 each pair a negative with
  a positive from the same drain, so none can pass by the drain doing nothing.
- **Portability.** `touch -t YYYYMMDDHHMM` is POSIX; the fixture takes BSD
  `date -v-10d` first and falls back to GNU `date -d`, with the redirect's
  reason inline as the shell rule requires. Every `find` predicate used
  (`-maxdepth`, `-type`, `-name`, `-path`, `!`, `-print0`) is BSD/bfs-safe;
  `-delete` appears only in GREEN's implementation, not the test. `grep -c -x`,
  `seq` and `${name##*/}` are all fine on bash 3.2 and BSD.
- **Whitespace.** Every enumeration is `find -print0` into `read -r -d ''`; case
  4 runs the whole drain over a gitdir path holding a space and asserts the
  fixture really is spaced.
- **Fixtures create the real condition.** Case 4's hand-built orphan temp
  matches the shape GREEN's write path produces (`<final-name>.tmp` with all
  five fields). Case 5's aged marker is produced by a real `gitlore_relay_write`
  and then aged, not hand-authored.
- **`shellcheck -x tests/index_sync.bats`** clean; `bats --count` still 84.

## Two findings for the team lead

**1. D51's name format cannot separate two same-second writes from one
process.** `<epoch>-<pid>-<H>` collides whenever session, agent, tag and second
all agree, and `$$` is fixed at shell startup so `&` subshells share it while
`$BASHPID` is absent on bash 3.2. Production is safe — two hooks in one batch
are separate processes with different tags — and the tests now avoid the
collision deliberately (case 1 by a second, case 2 by spawning processes). But
the format has no headroom: any future caller that writes twice from one process
within a second gets a refused install. The RED report flagged this too. It
needs a decision at GREEN, not a workaround.

**2. The design's sweep sentence contradicts its own `.tmp` rule.** §D51 names
the sweep as "the same `-mtime +7 -delete` shape as the nudge markers" over
`gitlore-relay-*`, and that glob also matches `gitlore-relay-….tmp`. The same
decision says the `.tmp` suffix "stays excluded from every enumeration", and the
slice-5 case says the sweep leaves a `.tmp` alone. Case 5 keeps the strict
reading — an aged `.tmp` survives — because it is the standing invariant and the
runbook case states it, and the assertion reds against the literal sentence, so
it is real coverage rather than decoration. The residual it locks in is now
stated in the case comment:
**a temp stranded by a killed writer is never collected, by age or otherwise.**
If that is not wanted, the fix is in the design, not the test.

## Not in scope, left alone

`tests/index_sync.bats:740,758,803` still call the retired
`gitlore_relay_marker_file` and fail with status 127. They exercise
`scripts/cc-hooks/index-sync-post.sh`, which slice 2 owns. The RED report's
extension of the runbook's one named exception to all three is right: none can
pass without touching `scripts/cc-hooks/*`.
