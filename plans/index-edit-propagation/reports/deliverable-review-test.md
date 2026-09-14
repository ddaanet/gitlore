# Deliverable review — test partition (fresh, post fix pass)

## Scope

Plan `plans/index-edit-propagation`, range `b6dbe92..HEAD` (HEAD `7d20aab`).
Files: the thirteen suites and three helpers the dispatch names;
`justfile_gates`, `check_docs_links` and `check_memory_hygiene` excluded. Code
under test read where a test's claim depended on it.

Baseline, in precedence order: `relay-redesign.md` §Slices for the relay;
`runbook.md` with its as-executed notes for Items 1.1–3.1; `outline.md` §B–D;
the fix-pass changelog entries `docs/changelog/2026-09-13-*.md`.

Method. Every case was run as a single `bats -f` call, sequentially. Mutation
probes ran against a copy of `scripts/`, `tests/` and `hooks/` under
`/tmp/claude/drt-test`, never in the tree. The fix-pass tests were also run
against the pre-fix scripts (`git archive <fix>^ scripts`) with the HEAD tests.
Each finding says whether it was reproduced or read from the code. `git status`
is clean apart from this report.

**Counts:** Critical 0 · Major 2 · Minor 9

## Prior findings status

IDs from `deliverable-review.md`.

- **M6** (no concurrent test). Resolved. The library case reds on a
  race-sensitive mutation. The hook-level case runs concurrently but does not
  hit the race window (m1).
- **Minor, squat comments** (`index_sync.bats:1118`,
  `cc_hook_index_compose.bats:416-455`). Resolved: those cases were retired or
  rewritten, and the remaining `.tmp`-squat comment is accurate.
- **Minor, sideways case names the wrong red line.** Resolved (`7d20aab`).
- **Minor, `resolve_recovery.bats` predicate comment.** Resolved.
- **Minor, "bats leaves CLAUDECODE unset" comments.** Resolved. No occurrence
  remains.
- **Minor, non-final `[[ ]]` under bash < 4.1.** Unchanged; house style (m9).
- **Minor, hook-entry off-pin case asserts no reason.** Resolved
  (`git_hook_pre_commit.bats:243`).
- **Minor, untested `|| agent_id=""`.** Partly resolved. The `index-compose.sh`
  and `index-sync-post.sh` cases red when the fallback is removed. The
  `add-tier-batch.sh` fallback is still unpinned (m7).
- **Minor, failable `rev-parse` between `chmod a-w` and `run`.** Resolved.
- **Minor, unquoted adoption remedy, no spaced case.** Partly resolved. The code
  quotes the remedy, and `index_compose.bats:402-403` pins the ahead-of-pin
  remedy's quoting. There is still no spaced-root case, and `resolve.sh`'s
  quoted remedies are unasserted (m8).
- **Runbook drift** (retired slice-4 case, superseded remedy sentence).
  Resolved: both now carry as-executed notes.

## Coverage table

Verdicts: **ok** means the case exists and asserts what the baseline specifies.
**ok†** means it is conformant but has a specificity finding.

**Relay, slice 1 (library)**

| Baseline case | Test | Verdict |
|---|---|---|
| 1. two writes, two files, drained in write order, removed | `index_sync.bats:903` | ok |
| 2. 20 concurrent writers, one drain, every body once | `index_sync.bats:972` | ok (`bash -c` processes; red on race mutation) |
| 3. S2 write not drained by S1 | `index_sync.bats:1012` | ok |
| 4. `.tmp` neither folded nor removed | `index_sync.bats:1048` | ok (spaced gitdir) |
| 5. sweep: >7 days incl. `.tmp`; fresh kept | `index_sync.bats:1085` | ok |
| 6. empty agent refused; empty session → `nosession` **on both sides** | `index_sync.bats:1126` | **Major M2**: drain side unpinned |

**Relay, slice 2 (hooks)**

| Baseline case | Test | Verdict |
|---|---|---|
| 1. both reporters at once ×10, drain, each report once | `cc_hook_index_compose.bats:321` | ok† (m1) |
| 2. drain with no baseline delivers; keyed run silent, files kept | `cc_hook_index_compose.bats:362` | ok |
| 3. unkeyed `index-sync-post.sh` / `index-compose.sh` leave a marker | `index_sync.bats:771`, `cc_hook_index_compose.bats:294` | **Major M1**: vacuous against a session-scoped drain |
| 4. drain S1 leaves S2 | `cc_hook_index_compose.bats:389` | ok |
| 5. session-start drains own, not peer; sweeps >7 days | `cc_hook_session_start.bats:366`, `:401` | ok |
| 6. failed-write cases keep passing | `cc_hook_index_compose.bats:424`, `:456` | ok (compose hook only, the accepted residual) |
| `relay-drain.sh` listed once, exists, 100755 | `plugin_distribution.bats:202` | ok (run at HEAD) |

**Fix pass**

| Fix | Test | Verdict |
|---|---|---|
| C1: half-landed retry completes | `commit_memory.bats:296` | ok. Red on pre-fix scripts; red with `gitlore_stage_landed_tiers` dropped |
| C1: failed tier commit drops its landing record | `commit_memory.bats:325` | ok. Born green on pre-fix, as a guard; red with `rm -f "$landing"` dropped |
| C1: failure after compose keeps approval | `commit_memory.bats:353` | ok† (m2). Red on pre-fix scripts; red with the `add -A` restamp dropped |
| M4: ahead remedy names the carrier, quoted staging | `index_compose.bats:402-403` | ok. Red on pre-fix scripts |
| M5 take: records nothing, retaken after fix | `merge_memory.bats:354` | ok. Red on pre-fix (`status -eq 1`) |
| M5 continuation: lands, root records nothing, next take adopts | `resolve_compose.bats:137` | ok. Red on pre-fix |
| M5 continuation: `publish: no` exit rests the tier too | `resolve_compose.bats:177` | ok. Red on pre-fix |
| M5 continuation: pin not contained → stays on merge | `resolve_compose.bats:193` | ok. Red on pre-fix |
| Minor pass: adoption short-circuit | `resolve_recovery.bats:397` | ok. Red with the short-circuit removed |
| Minor pass: agent_id fallbacks | `cc_hook_index_compose.bats:160`, `index_sync.bats:300` | ok. Both red with the fallback removed |

**Items 1.1–2.1** (unchanged by the fix pass apart from comments and one added
assertion): every backticked case name in `runbook.md` matches a current
`@test`, or is recorded as re-homed or retired. The one exception is
`a tier moved off its pin aborts the commit`, renamed to
`a tier moved sideways off its pin aborts the commit` in `313cf5d`, as the prior
review accepted. The relay cases named in Item 3.1 are superseded by
`relay-redesign.md`.

## Critical

None.

## Major

### M1 — "An unkeyed run leaves a marker in place" cannot see a drain that is back in a reporting hook

- **Where:** `tests/index_sync.bats:771`,
  `tests/cc_hook_index_compose.bats:294`.
- **Axis:** vacuity (slice 2, case 3). **Reproduced.**

Both cases stage their marker under the empty session, which maps to
`nosession`. Both then run the reporting hook with a payload carrying
`session_id: "test-session"` (`batch_payload`, `feed`). Their comments say the
mismatch was chosen so the case would red against the pre-redesign drain, which
ignored sessions.

After the redesign, the regression this case exists to catch is a drain branch
returning to `index-sync-post.sh` or `index-compose.sh`. That branch would
naturally be the D51 shape, `gitlore_relay_drain "$mempath" "$session"`. It
would drain `test-session` markers and never touch a `nosession` one.

**Probe.** Added an unkeyed `gitlore_relay_drain "$mempath" "$session"` that
folds into the emitted `systemMessage`, to both hooks:

- Both "leaves a marker in place" cases stayed green.
- The concurrency, M2 and S1/S2 drain cases also stayed green.
- A control case, identical but with the marker under `test-session`, went red
  under the mutation and green at HEAD. So the mutation really drains.

That regression is C2's drain half: two parallel drains on one batch relay each
report twice. No test in the suite catches it.

**Fix shape:** write the marker under the same `test-session` the hook's payload
carries.

### M2 — The drain side of "empty session maps to nosession" is untested

- **Where:** `tests/index_sync.bats:1126`; code at
  `scripts/lib/index-sync.sh:207`.
- **Axis:** coverage (slice 1, case 6). **Reproduced.**

The baseline names the mapping "on both sides". The case writes with `""` and
asserts the `nosession` filename, which pins the write side. It then drains with
the literal `nosession`, never with `""`. Its own comment concedes the drain
half "cannot red on its own".

**Probe.** Replaced line 207 with an unconditional `_gitlore_sanitize_id`, so
`""` enumerates `gitlore-relay--*`. All 24 relay cases stayed green, across
`index_sync`, `cc_hook_index_compose` and `cc_hook_session_start`. That includes
the session-start unreadable-marker case, which drains with an empty session
(see m5).

In production the reach is small: Claude Code payloads carry `session_id`. The
guard is still a specified contract and nothing pins it.

**Fix shape:** `gitlore_relay_drain memory ""` must return the `NOSESSION-BODY`.

## Minor

### m1 — The hook-level concurrency case launches concurrently but never races the write

- **Where:** `tests/cc_hook_index_compose.bats:321`.
- **Axis:** specificity (concurrency). **Reproduced.**

**Probe.** Replaced the relay filename with a count-then-create name that is
correct when writers run sequentially and collides when they overlap:
`<S>-<A>-<n existing>-0-sync`.

- **Library case:** red at once. 20 writers, most bodies lost.
- **Hook case:** green on three consecutive runs, 30 iterations. The two hooks
  do different amounts of work, so their write windows never overlapped.

The case still discriminates the pre-fix design deterministically: a merged
marker frames once, so the frame count reads 1. It also catches any
timing-independent name collision. The race itself is carried only by
`index_sync.bats:972`.

The comment's "real separate processes at once" is true of launch, not of the
critical section. A barrier (each writer blocks on a FIFO the test opens after
both have started) would make the hook case exercise overlap. Otherwise, the
comment should say the library case owns the race.

### m2 — The "failure keeps the approval" rule is pinned on one arm of many

- **Where:** `tests/commit_memory.bats:353`; `scripts/lib/resolve.sh:923`,
  `:1151`, `:1232`.
- **Axis:** coverage. **Reproduced.**

The changelog states the rule generally: a failure after the freshness gate
keeps the approval unless it prepared a merge. The case induces only the memory
`add -A` failure (`:1140`).

**Probe.** Removed three things together:

- the restamp on a failed tier commit (`:923`);
- the restamp on a failed memory commit (`:1151`);
- the `[ "$parent" = "$recorded" ]` check in `gitlore_stage_landed_tiers`
  (`:1232`).

All three C1 cases stayed green, and so did `git_hook_pre_commit.bats`
`a failed memory commit is reported` and
`an aborted compose keeps the approved summary usable`.

The parent check is what stops a leftover landing record from adopting a foreign
commit stacked on a landed one.

The case also drives `gitlore_sync_memory_to_live` through a driver script. The
entry point whose retry depends on the restamp is
`scripts/git-hooks/pre-commit`, and no hook-level half-landed retry exists.

### m3 — Two relay guards the code argues for lost their cases in the redesign

- **Where:** `scripts/lib/index-sync.sh:178` (occupied-destination refusal) and
  `:217` (`-type f`).
- **Axis:** coverage. **Reproduced.**

D51 states "a path already occupied at install time is refused, temp removed".
The code comment calls the `-e` check, not `mv`, what stops a directory squat.
Relay slice 2 retired `relay_write refuses a squatted marker path` and
`an unkeyed run leaves a non-marker alone`. It said the `-type f` coverage "is
already carried by" the `.tmp` case, which tests `'!' -name '*.tmp'`, not
`-type f`.

**Probe.** Deleting the `-e` block, or dropping `-type f`, left all 24 relay
cases green. The squat half needs no filename prediction:

- `index_sync.bats:1268` already freezes `date` and writes twice from one
  process, so the second write can meet an occupied final name (file or
  directory).
- A drain case can `mkdir` any `gitlore-relay-s1-a1-1-1-sync`.

### m4 — The relay write's id sanitization is unpinned

- **Where:** `scripts/lib/index-sync.sh:162-163`.
- **Axis:** coverage (whitespace and traversal safety). **Reproduced.**

`an agent id outside [A-Za-z0-9-] cannot leave the gitdir` covers the pre-image
and stamp paths only. Splicing the raw session and agent ids into the relay
name, which lets a `/` or `..` from the payload walk out of the gitdir, left
every relay case green. Not a live exploit, since Claude Code mints both ids.

### m5 — The session-start unreadable-marker case never checks that the drain reached the marker

- **Where:** `tests/cc_hook_session_start.bats:458`.
- **Axis:** specificity. **Reproduced** under the M2 mutation.

With the drain enumerating nothing, the marker is never opened, yet the case
passes. It asserts only exit 0 and the commit-protocol context, both of which
hold with no drain at all.

**Fix shape:** `[ ! -e "$marker" ]` after the run, since the fixed drain removes
an unreadable marker. Its comment ("today's still-unkeyed drain (no session
concept)") is stale as well.

### m6 — RED-phase narration and false helper comments ship in the relay suites

- **Axis:** clarity. **From the code.**

**RED-stub references.**
`tests/index_sync.bats:893-897, 922-924, 1008, 1027-1030, 1073, 1083, 1149`
describe a "RED stub" and cite "gitlore_relay_write's RED STUB comment". Neither
exists.

**"Today" / "TODAY's code" framing.** Present at:

- `tests/index_sync.bats:736, 768-769`;
- `tests/cc_hook_index_compose.bats:214, 266, 290-292`;
- `tests/cc_hook_session_start.bats:18, 362, 398, 461`.

It narrates pre-GREEN code, against the present-tense rule.

**False helper comment.** `sync_feed`'s comment
(`cc_hook_index_compose.bats:64-71`) says the hook "never inspects
tool_calls/session_id" and that slice 2.5's case is the only user.
`index-sync-post.sh:29` parses `session_id` for the relay and the nudge key, and
the concurrency case is the user.

**Stale root skips.** The two failed-write cases (`:425`, `:457`) keep
`skip "root ignores permission bits"` after switching to an `mv` stub, so they
skip under root for no reason.

### m7 — `add-tier-batch.sh`'s `|| agent_id=""` is still untested

- **Where:** `scripts/cc-hooks/add-tier-batch.sh:66`.
- **Axis:** coverage. **Reproduced.**

Removing the fallback left all four agent-keyed and failure `cc_hook_add_tier`
cases green. The `7d20aab` message scopes its new cases to the compose and
post-sync hooks, so this half of the prior finding stays open.

### m8 — No in-suite spaced-root case for the fix-pass paths

- **Axis:** whitespace safety. **Reproduced (probe passes).**

The landing record, `gitlore_stage_landed_tiers`, the take walk-back and
`rest_unadopted_tier` all handle paths.

**Probe.** Re-ran the C1, M5-take, M5-continuation, short-circuit and
hook-concurrency cases with `TMPDIR="/tmp/claude/drt sp"`. The fixtures landed
under the spaced path, confirmed by printing `TMP_REPO`, and all passed. The
code is whitespace-safe on these paths.

The suite only proves that when the ambient `TMPDIR` holds a space. The quoted
`git -C "%s" checkout --detach` and `add --` remedies in `resolve.sh`
(`081e364`, `7485483`) are asserted nowhere.

### m9 — Non-final `[[ ]]` assertions go silent under bash < 4.1

House style, carried from the prior review. The added relay cases lean on it
too, for example the channel negatives at `cc_hook_index_compose.bats:409-410`.

## Checks that passed

**Fix-pass tests red on pre-fix code.** Each new case was run with its HEAD test
against the scripts of the commit before its fix:

- C1 retry and C1 approval: red.
- M4 remedy text: red.
- M5 take case: red.
- All three M5 continuation cases: red.

The C1 landing-record guard is born green on pre-fix code, by design. It is red
under its own mutation.

**Critical-fix mutations.**

- Dropping `gitlore_stage_landed_tiers` reds the retry case.
- Keeping the landing record on commit failure reds the foreign-commit case.
- Dropping the `add -A` restamp reds the approval case.
- Dropping the adoption short-circuit reds `resolve_recovery.bats:397`.

**Relay concurrency is production-shaped.**

- Library writers are `bash -c` processes, not `&` subshells.
- Hook writers are separate `bash "$HOOK"` processes.
- Channels are decoded before counting.
- The whole framing line is matched with `grep -x`.

**Invocation path.**

- `relay-drain.sh` is registered once on `PostToolBatch`, executable, and 100755
  in the index (run at HEAD).
- The other hooks keep their registration and `-x` cases.
- Every relay hook case pipes real payload JSON with an `agent_type` decoy.

**Independence.**

- The C1 cases and the hook-entry off-pin case pass with `CLAUDECODE` unset and
  with it set to 1.
- `setup_tmp_repo` unsets `CDPATH` and closes stdin.
- The `PATH` stubs (`date`, `mv`) are restored or scoped to one `run`.
- Fixtures build per test, and the hook concurrency loop uses fresh filenames
  per iteration.

**Permission cases.** The `chmod` restores sit immediately after `run` and are
guarded where the fixed code removes the target.

**macOS / BSD.** Added lines use `sed -i.bak`, `date -v … || date -d`,
`touch -t`, `find -print0` and `LC_ALL=C sort`. There is no `stat -c`, no
`-printf`, and no bare `sed -i`.

**Full run.** All 24 relay cases and all fix-pass cases pass at HEAD.
