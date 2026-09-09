# Item 3.1 slice 4 — test review (RED phase)

Reviewed: `tests/index_sync.bats`, `tests/cc_hook_index_compose.bats`,
`tests/cc_hook_session_start.bats` as submitted by
`reports/item-3-1-s4-red.md`. Every claim below was measured, not read. No SUT
file is left modified; `git diff -- scripts/` is empty.

**Headline: two of the six cases could not have passed at GREEN.** Both fail on
their own fixture rather than on the behaviour they name, and neither failure is
visible in the RED run — each sits behind a death point. Both are fixed. A third
gap (a drain that skips an unreadable marker instead of removing it satisfies
every submitted assertion) is closed with one added assertion.

Case count moved from 6 to 7: `relay_write refuses an empty agent id and a
squatted marker path` is split in two. Rationale in §3.

---

## 1. Defects found and fixed

### D1 — `a failed relay write leaves the subagent's own report intact` could not pass at GREEN (blocking)

`tests/cc_hook_index_compose.bats`. The case captured the hook with bare
`run feed a1`, which **merges stderr into `$output`**. This fixture's whole
mechanism is a redirect that fails, and bash prints
`…/index-sync.sh: line 148: …/gitlore-relay-a1: Is a directory` on stderr on
every run. So at GREEN `$output` is that diagnostic *followed by* the JSON, and
`run jq -r '.systemMessage' <<<"$output"` fails to parse.

Measured, with the minimal plausible GREEN fix applied in place
(`gitlore_relay_write … || true` in `scripts/cc-hooks/index-compose.sh`):

```
not ok 1 a failed relay write leaves the subagent's own report intact
# (in test file tests/cc_hook_index_compose.bats, line 430)
#   `[ "$status" -eq 0 ]' failed        <- the status of the jq parse
```

and the merged capture itself, from an isolating probe over the same fixture:

```
STATUS=0
----OUTPUT-BEGIN----
/Users/david/code/gitlore/tests/../scripts/lib/index-sync.sh: line 148: \
  /tmp/claude-1000/gitlore-test.jZmPu8/.git/modules/gitlore-memory/gitlore-relay-a1: Is a directory
{
  "systemMessage": "gitlore: recomposed tier pointers (1 index)",
  …
}
----OUTPUT-END----
```

The hook exits 0 and reports exactly as the case requires, and the case reds
anyway. Invisible in RED because the death point is the *first*
`[ "$status" -eq 0 ]`, upstream of the jq call.

**Fix:** `run --separate-stderr feed a1`. The file already declares
`bats_require_minimum_version 1.5.0`. Applied to the sibling Group B case
`an unkeyed run survives a non-file squatting on a marker name` for the same
reason — its fixture is the same directory squat, and any GREEN or later change
that emits a diagnostic there would red it for a reason it does not name. The
`-type f` mutation still reds that case with the separation in place (M1 below),
so nothing was weakened.

### D2 — `an unreadable marker costs the relay, not the hook` (library half) could not pass at GREEN (blocking)

`tests/index_sync.bats`. The case restored the fixture with an **unconditional**
`chmod 0600 "$marker"`. A fixed drain folds the unreadable marker as an empty
block and `rm -f`s it, so at GREEN that path no longer exists and the test dies
on its own cleanup line, under errexit, before any assertion:

```
not ok 1 an unreadable marker costs the relay, not the hook
# (in test file tests/index_sync.bats, line 1173)
#   `chmod 0600 "$marker"' failed
# chmod: cannot access '…/gitlore-relay-a1': No such file or directory
```

Measured with the minimal plausible GREEN fix in place
(`sysblock=$(_gitlore_relay_sysblock "$marker") || sysblock=""` and the same for
`ctxblock`). The SessionStart half already guards its restore with
`[ -e "$marker" ] &&`; the library half did not, and it is the half that reaches
the removal.

**Fix:** the same guard, `[ -e "$marker" ] && chmod 0600 "$marker"`, with the
reason inline. (Errexit-safe: a non-final element of an `&&` list.)

### D3 — a drain that strands the marker satisfies every submitted assertion (gap, closed)

The runbook states what the fix must do: "fold an empty block and `rm -f` it".
Neither half asserted the removal. A drain fixed by *skipping* unreadable
markers instead — `sysblock=$(…) || continue` — leaves the file behind, so the
same abort recurs at every later session and no test notices. Measured (M6):

| case | drain skips-and-strands |
|---|---|
| `an unreadable marker costs the relay, not the hook` (index_sync, submitted form) | **GREEN** |
| `an unreadable marker costs the relay, not the hook` (session_start) | **GREEN** |
| index_sync half with the added assertion | **RED**, line 1210, `[ ! -e "$marker" ]` |

**Fix:** one added assertion, `[ ! -e "$marker" ]`, in the library half. It reds
against the committed tree too (verified by reordering: line 1204,
`` `[ ! -e "$marker" ]' failed ``), so it is not a born-green addition. Not
duplicated into the SessionStart half — that half's job is the hook's survival
and its `additionalContext`, and the removal is a library property.

---

## 2. Question 1 — the Group B mutation proofs, re-run and probed

Every mutation applied **in place** to the working-tree SUT, run over all three
suites (131 cases after the split), then restored and re-confirmed with
`git diff --stat -- scripts/`. Baseline against the committed tree: **128
passed, 3 failed** — the three Group A cases and nothing else, identical on two
consecutive runs.

### Mutation table

| # | mutation | file | result | cases that red |
|---|---|---|---|---|
| — | baseline (committed tree) | — | 128/3 | the 3 Group A cases |
| M1 | `find … -maxdepth 1 -type f -name 'gitlore-relay-*'` → `-type f` dropped | `lib/index-sync.sh` | **RED +1** | `an unkeyed run survives a non-file squatting on a marker name` (line 454, status) |
| M1b | M1 **plus** both block readers made tolerant (`\|\| sysblock=""`) | `lib/index-sync.sh` | **RED** | same case, same line — so the `rm` path alone still kills it |
| M1c | M1b **plus** `rm -f "$marker" \|\| true` | `lib/index-sync.sh` | **GREEN** | — (the case's whole discrimination is "the drain must not hand a non-file to `awk` *or* `rm`") |
| M2 | ctx join guard `if [ -n "$old_ctx" ]` removed | `lib/index-sync.sh` | **RED +1** | `relay_write joins a channel only when the old body is non-empty` (line 1163, the exact-block equality) |
| M2b | **sysmsg** join guard removed, ctx guard intact | `lib/index-sync.sh` | **GREEN — gap** | — (see §5) |
| M3 | `gitlore_relay_drain "$mempath" \|\| true` → bare call | `cc-hooks/session-start.sh` | **RED +1** | `an unreadable marker costs the relay, not the hook` (session_start, line 431, status) |
| M3b | that call → `\|\| exit 0` | `cc-hooks/session-start.sh` | **GREEN — not a mutation** | — the drain *returns 0* once errexit is suspended, so the `\|\|` branch never fires; recorded because it looks like a mutation and is not |
| M3c | `emit_session_json` emits a literal `additionalContext`, protocol_ctx dropped | `cc-hooks/session-start.sh` | **RED 1** | session_start case at **line 432**, the `jq -e … test("never commit")` — status stays 0, so that assertion is a second independent pin, not decoration |
| M4 | trailing `return 0` in `gitlore_relay_write` | `lib/index-sync.sh` | **RED +1** | `relay_write refuses a squatted marker path` (line 1134, status) |
| M5 | empty-id guard **misplaced after** the write (writes, then returns 1) | `lib/index-sync.sh` | **RED 1** | `relay_write refuses an empty agent id` at **line 1104**, `[ ! -e "$bare" ]` — the "without writing" half, pinned independently of the status half |
| M5b | M5 **plus** the write diverted to `"$marker-fallback"` | `lib/index-sync.sh` | **RED 1** | same case at **line 1113**, `[ "$count" -eq 0 ]` — the gitdir-wide sweep is not dead weight; it catches a leaked or differently-suffixed file the single-name check misses |
| M6 | drain **skips** an unreadable marker (`\|\| continue`, no fold, no `rm`) | `lib/index-sync.sh` | **RED 1** | index_sync unreadable-marker case at line 1210, `[ ! -e "$marker" ]` (D3) |
| M7 | simulated GREEN (`\|\| true`) **plus** keyed branch suppresses the hook's own report | `cc-hooks/index-compose.sh` | **RED 1** | `a failed relay write…` at **line 435**, the `recomposed tier pointers` substring — the post-death assertion discriminates |
| SG | simulated GREEN: empty-id guard + compose `\|\| true` + tolerant drain | 2 files | **131 passed, 0 failed** | — |

**Attribution.** Each of M1, M2, M3, M4 reds exactly one case beyond the
baseline three. No Group B pin turned out to belong to another case.

### What each Group B case actually discriminates

- **`an unkeyed run survives a non-file squatting on a marker name`** — reds on
  removing `-type f` (M1) and *still* reds with the `awk` failures swallowed
  (M1b); goes green only once the `rm` is also swallowed (M1c). It therefore
  pins the whole property "the drain must not abort on a directory marker",
  which is stronger than "the `find` carries `-type f`". It does **not**
  discriminate *how* a surviving drain treats the directory: it is a substring
  check on the compose report, so an implementation that folded the directory in
  as an empty block would pass. That residual is acceptable — the directory is
  the write's own failure debris, and the runbook asks only that the unkeyed run
  survive it.
- **`relay_write joins a channel only when the old body is non-empty`** — reds
  on the ctx guard only (M2), stays green on the sysmsg guard (M2b), so the
  attribution the RED report claims holds. Its exact-block equality also catches
  a trailing-newline or framing drift on the ctx channel. It does **not**
  discriminate a corruption of the join *itself* (dropping the separating
  newline inside the guarded branch is invisible, because this fixture's
  `old_ctx` is empty); that is covered by slice 2.5's
  `relay_write merges a second report into an existing marker`, which asserts
  both channels as exact blocks over non-empty old bodies. It asserts nothing
  about `GITLORE_RELAY_SYSMSG`; see §5.
- **`an unreadable marker costs the relay, not the hook` (SessionStart)** — reds
  on removing `|| true` (M3, on the status) and, separately, on any loss of the
  standing commit-protocol `additionalContext` (M3c, on the jq assertion, with
  status still 0). Two independent pins. It does **not** discriminate the
  marker's removal (M6 leaves it green) — that is D3, closed on the library
  side. `|| exit 0` is *not* a mutation of it (M3b): once errexit is suspended
  the drain runs to completion and returns 0, which is worth knowing because it
  is the "fix" a future reader is most likely to reach for.
- **`relay_write refuses a squatted marker path`** (new, split out) — reds on
  `return 0` (M4). Its `[ -d "$squat" ]`, `[ ! -f "$squat" ]` and gitdir-sweep
  assertions have no *minimal* mutation that reds them alone: any edit that
  writes through the squat also returns 0 and trips the status assertion first.
  They discriminate a non-minimal but plausible rewrite — a write-to-temp-then-
  rename implementation leaving `gitlore-relay-a1.tmp` behind, which the
  `gitlore-relay*` sweep catches and the two named-path checks do not.

---

## 3. Question 3 — mechanical checks and the wrong-reason hunt

### Group A cases all failed on an assertion

Confirmed against the final tree, from the full TAP log, not the summary. All
three carry `` #   `<assertion>' failed `` with no `failed with status N`
suffix — an assertion failure, never a missing symbol or an ERROR:

```
not ok 59 relay_write refuses an empty agent id
# (in test file tests/index_sync.bats, line 1102)
#   `[ "$status" -ne 0 ]' failed
not ok 62 an unreadable marker costs the relay, not the hook
# (in test file tests/index_sync.bats, line 1206)
#   `[ "$status" -eq 0 ]' failed
not ok 99 a failed relay write leaves the subagent's own report intact
# (in test file tests/cc_hook_index_compose.bats, line 432)
#   `[ "$status" -eq 0 ]' failed
```

### The two sub-cases in one body: split

Split, not reordered. Reordering (squatted half first) would have given both
halves execution in the RED run and preserved the runbook's single case name,
but the two halves are in different evidence classes — one reds by absence of a
guard, the other is born green and needs a mutation pin — and a body that is
half Group A and half Group B cannot be attributed cleanly by either the RED
report or a mutation table. Two bodies:

- `relay_write refuses an empty agent id` — Group A, red today.
- `relay_write refuses a squatted marker path` — Group B, born green, pinned by
  M4.

Each keeps its own gitdir-wide `gitlore-relay*` sweep; the joint sweep the
submitted body ended with was doing both jobs at once. **This diverges from the
runbook's slice-4 bullet, which names one case over both inputs** — the bullet's
content is fully covered, but the orchestrator may want to reconcile the wording
in the runbook or leave it as a recorded deviation.

### Assertions positioned after a death point

Enumerated across all seven cases. Only two cases have any — the other five run
to the end today. Each verified by an isolating measurement, never by reading:

| case | assertion after the death point | verified by | result |
|---|---|---|---|
| `a failed relay write…` (line 432 dies) | `[ "$status" -eq 0 ]` after `run jq` (434) | D1's probe: at GREEN with a merged capture it reds here | discriminates, and was the D1 bug |
| ″ | `[[ "$output" == *"recomposed tier pointers"* ]]` (435) | M7 | reds alone |
| `relay_write refuses an empty agent id` (1102 dies) | `[ ! -e "$bare" ]` (1104) | M5 | reds alone |
| ″ | `[ "$count" -eq 0 ]` (1113) | M5b | reds alone |
| `an unreadable marker…` index_sync (1206 dies) | `[[ "$output" == *"OWN REPORT"* ]]` | reorder: placed first against the committed tree | reds (`$output` is empty) |
| ″ | `[ ! -e "$marker" ]` (1210) | reorder: placed first against the committed tree; and M6 | reds both ways |

`rmdir "$squat"` in the two compose cases is also post-death; it is cleanup, not
an assertion, and teardown covers it (below).

### Fixture hygiene

- **No mode-0200 directories are planted.** The dispatch's premise is half
  right: the two `chmod 0200` calls target regular files
  (`gitlore_relay_write`'s marker); the directories come from bare `mkdir` at
  the default umask. Nothing needs a directory-mode restore.
- **`teardown_tmp_repo` copes with a 0200 file left mid-body.** `rm -rf` on a
  tree containing `--w-------` succeeds — removal depends on the containing
  directory's mode, not the target's. Measured directly:
  `rm -rf` on a fixture tree holding a 0200 file removed it, exit 0.
- **Every case is self-contained.** `setup_tmp_repo` mints a fresh `mktemp -d`
  per test and `teardown_tmp_repo` `rm -rf`s it, so a body that dies before its
  cleanup line leaks nothing into the next case. Both `chmod 0600` restores are
  now guarded, so neither can itself become the failure. `rmdir "$squat"` in the
  two compose cases is redundant against that teardown and is left as-is in the
  compose file (minimal diff); the split index_sync case drops it, with the
  reason in a comment.
- **Two consecutive full runs are identical**: `128 passed, 3 failed`, same
  three cases, same line numbers, both times. No leftover fixture directories
  from this session (`/tmp/gitlore-test.*` holds one entry, dated 2026-08-25,
  predating this review).

### Standard hunt

- **Whitespace safety.** Both new sweeps are `find … -print0` into
  `while IFS= read -r -d ''`, running in the current shell via process
  substitution so the counter survives. Every path variable
  (`$gitdir`, `$marker`, `$bare`, `$squat`, `$SRC`) is quoted at every use. No
  word-splitting anywhere in the diff.
- **Quoting / `run` vs bare calls under errexit.** Every status-bearing call is
  either `run`-wrapped or captures explicitly:
  `gitlore_relay_drain memory || rc=$?` in the ctx-join case (which must keep
  its two variables, so `run` is not an option), and
  `if gitlore_relay_write …; then write_status=0; else write_status=$?; fi` in
  the SessionStart case. The two `[ … ] && chmod` and
  `[ "$(id -u)" -eq 0 ] && skip` lines are non-final elements of `&&` lists and
  mid-body, so errexit does not fire on them — confirmed by the suites running.
- **Substring vs exact.** The ctx-join case is an exact block, deliberately. The
  two compose cases match `recomposed tier pointers`, the literal every other
  case in that file already pins, and reached only via `jq -r '.systemMessage'`
  rather than over raw stdout — so a match cannot come from `additionalContext`.
  `OWN REPORT` is a literal no diagnostic on either channel supplies.
- **bash 3.2 / BSD.** Nothing in the diff is GNU-only: `find -maxdepth -type
  -name -print0`, `chmod`, `mkdir`, `rmdir`, `id -u` are all POSIX/BSD-safe;
  `read -d`, `[[ … == *glob* ]]`, `<<<`, `$((…))` and `< <(…)` are all bash 3.2.
  `run --separate-stderr` needs bats ≥ 1.5.0, which both edited files declare.
  `tests/helpers/bsd-stubs.bash` shadows `sed`, `grep` and `mktemp` only, none
  of which this diff uses, so no lock-in is owed to `tests/bsd_portability.bats`.
- **Each fixture reaches the path it names.** Not asserted from reading — each
  is proved by a mutation of exactly that path redding exactly that case: the
  compose keyed case reaches `gitlore_relay_write` (D1's probe shows the write's
  own stderr line), the compose unkeyed case reaches `gitlore_relay_drain` (M1),
  the SessionStart case reaches `session-start.sh:402` (M3). The four
  library-level cases call the SUT directly. No case is satisfied by an upstream
  early exit.

---

## 4. Question 2 — the two claims

### 2.1 Case 6's null-channel argument: **verified, no hole**

The RED report's claim is correct as written, and the earlier `jq -r` hole does
not apply to this idiom. Measured against jq-1.7, running the exact expression
the case uses:

| input | exit |
|---|---|
| `additionalContext` **absent** | **5** — `null (null) cannot be matched, as it is not a string` |
| `additionalContext: null` | **5**, same message |
| `hookSpecificOutput` absent entirely | **5**, same message |
| hook emitted **nothing** (`$output` empty) | **4** — no valid result was ever produced |
| present, non-matching | **1** (`false`) |
| present, matching | **0** (`true`) |

Every non-happy shape is non-zero, and the pipeline's status is jq's, so the
bats body reds on all of them. The earlier finding was about `jq -r`, which
prints the literal `null` into a string comparison; `jq -e … | test(…)` errors
instead. Nothing to close.

Positively pinned as well, not merely argued: M3c drops the protocol context
while leaving the exit status at 0, and the case reds on that line alone.

### 2.2 Case 3's synthetic caller: **faithful, and now improved**

The model is faithful, for four reasons that were checked rather than assumed.
`bash -c 'script' _ "$SRC" "$PWD/memory"` runs the script with `$0="_"`, `$1` the
library and `$2` the memory path, so the sourcing and the call are the real
shapes. `set -euo pipefail` is byte-identical to `scripts/cc-hooks/index-compose.sh:2`
and `scripts/cc-hooks/session-start.sh:2`, and the drain is invoked as a bare
simple command in no condition context — exactly `index-compose.sh:87`. Bats'
own `run` wraps only the outer `bash -c`, so the errexit under test is the inner
script's, which is the point of the shape: `run gitlore_relay_drain memory`
would suspend errexit and mask the defect entirely. And `printf "OWN REPORT\n"`
after the call occupies the position `index-compose.sh`'s `jq -n` emission
occupies — the thing an aborting drain destroys.

The two directions of the fidelity question both check out. A library-side fix
that makes the real hooks survive makes this case pass: measured, the simulated
GREEN (`|| sysblock=""`) turns it green along with all 130 others. The converse
— a *caller*-side fix that leaves this case red — is real but correct rather
than a flaw: adding `|| true` to `index-compose.sh` alone would leave the
library still aborting any bare caller, and this case is the one in
`tests/index_sync.bats` whose job is the library contract the runbook assigns to
this slice ("asserts the drain returns 0 and the calling hook still emits its own
report"). The SessionStart case is the caller-side half of the same fixture.

One change made anyway, and one deliberately not:

- **Made:** the unconditional `chmod 0600` restore is now guarded (D2). Without
  it the synthetic caller was faithful and the case still could not pass.
- **Not made:** left as plain `run`, not `run --separate-stderr`. `awk`'s
  "Permission denied" lands in `$output`, but the assertion is a substring on
  the synthetic hook's own line, which no diagnostic supplies. The tradeoff is
  concrete: with `--separate-stderr` shellcheck stops recognising `bash -c` and
  stops linting the embedded script, and emits SC2016 on the quoted body —
  measured, `shellcheck -s bash tests/index_sync.bats` is clean with `run bash -c`
  and reports SC2016 with `run --separate-stderr bash -c`. The reason is in a
  comment on the line.

---

## 5. Residuals — recorded, not closed

1. **The sysmsg join guard in `gitlore_relay_write` is pinned by nothing.** M2b
   removes it and all 131 cases stay green. Recommend leaving it that way: both
   production call sites guard on a non-empty sysmsg before calling the write
   (`index-compose.sh:83`, `index-sync-post.sh:257-258`), so a marker on disk
   always has a non-empty sysmsg channel and the guard's empty branch is
   unreachable from the real pipeline. A test for it would exercise a read path
   the write path cannot produce. The ctx guard is *not* in that class — the
   `failed` branch of `index-sync-post.sh` sets a sysmsg with no ctx — which is
   exactly why case 5 exists and this one should not.
2. **The compose cases' `rmdir "$squat"` never runs on a failing body** and is
   redundant against `teardown_tmp_repo`'s `rm -rf`. Left in place to keep the
   diff to the defects; noted so it is not read as load-bearing cleanup.
3. **Neither unreadable-marker case asserts what reaches the user.** After the
   fix the body is unrecoverable by construction and only the framing line
   arrives; nothing pins that the framing line arrives at all. `[ ! -e "$marker" ]`
   (D3) covers the stranding, which is the failure with a cost that compounds.
   Adding a framing-line assertion is a judgement call for GREEN, not a defect
   here.

---

## 6. Checks that passed, by name

- `./scripts/run-bats.sh tests/index_sync.bats tests/cc_hook_index_compose.bats tests/cc_hook_session_start.bats`
  — **128 passed, 3 failed**, the three Group A cases and no others, against the
  committed tree.
- The same command a second time — **identical** result, same cases, same line
  numbers.
- The same command under a simulated GREEN (empty-id guard + compose `|| true` +
  tolerant drain, all applied in place and restored) — **131 passed, 0 failed**:
  every case in this slice is reachable at GREEN, which two of them were not
  before this review.
- `shellcheck -s bash tests/index_sync.bats tests/cc_hook_index_compose.bats tests/cc_hook_session_start.bats`
  — clean.
- `./scripts/lint-shell.sh` — **137 files clean**.
- Fourteen mutation runs (M1, M1b, M1c, M2, M2b, M3, M3b, M3c, M4, M5, M5b, M6,
  M7, SG), each applied in place to the working-tree SUT and restored.
- `git diff -- scripts/` — **empty** after every mutation and at the end.
- `git status --porcelain` — only the three test files modified, plus the
  untracked RED and review reports. Nothing committed, nothing staged.
- `jq -e … | test("never commit"; "i")` exit-status matrix over six input shapes
  (§4.1).
- `rm -rf` over a fixture tree containing a mode-0200 file — removed, exit 0.
