# TDD audit — `plans/index-edit-propagation/runbook.md`

Closing audit of the runbook's nineteen tdd slices across Phases 1–3. Phase 4
carries four `general` items (4.0–4.3) and no tdd work, so it is outside the
red/green contract and is audited here only for commit shape.

Sources: the 77 reports under `plans/index-edit-propagation/reports/`, the
committed test diffs, and `git log`. The bats suites were not run and
`just precommit` was not invoked, per the dispatch.

**Verdict.** The RED contract holds on eighteen of nineteen slices. Every
born-green case carries a mutation proof except one, and that one was closed at
code review rather than at RED. The test-review step earned its place: it found
and fixed genuine vacuity in at least five slices, including two assertions that
were vacuous in *both* phases. The defects below are, with one exception,
discipline lapses rather than holes in the shipped suite. The one standing hole
is three ship-green mutation gaps declared at Item 3.1 slice 1, two of which
later slices closed and one of which nothing closes.

## Per-item compliance

| Item | Slices | RED evidence | Born-green proof | Commit discipline | Test integrity |
|---|---|---|---|---|---|
| 1.1 | 1, 2, 3, 4 | Pass — s1/s3/s4 each red on a named assertion with the failing line quoted; s2 has no RED phase by design | Pass — s2's whole case rests on an in-place hoist of the compose call, restored and verified byte-identical; s4's two characterization cases are redded by flipping `CLAUDECODE` | **Partial** — review fixes split into four extra commits, one of them (`62258fa`) SUT-only | Pass — two real defects found and fixed at s4 test review |
| 1.2 | 1, 2, 3 | Pass — s1 reds on `[ "$status" -ne 0 ]` through both entry points; s2/s3 are born-green with per-mutation reds | Pass — s3 carries a per-assertion mutation table, four assertions, four isolating mutations. The strongest evidence in the run | Pass — one commit per slice, tests + impl + all reports together | Pass, one noted residual (see D3) |
| 1.3 | 1, 2 | Pass — s1 cases 1/2/4/5 red on their own assertions; s2 both cases red on `*"ahead of"*` | **Partial** — s1 case 3's naive-predicate proof went stale (see D2) | Pass — one commit per slice | Pass — s1 code review found the up-projection gap and added two cases |
| 2.1 | 1, 2, 3, 4 | Pass — every slice reds on a quoted assertion; s2 case 3, s3 case 1 and s4's pairs each redded by in-place mutation with sha-verified restore | Pass | **Partial** — review fixes split into four extra commits (`999b17d`, `d4c4f47`, `28ef6e6`, `a7dd433`), one adding untested SUT (see D4) | Pass — assertion-order swaps run on s3/s4 to prove each assertion independently discriminating |
| 3.1 | 1, 2, 2.5, 3, 4, 5 | **Partial** — slice 1's red is against stubs the RED agent itself landed (see D1); slices 2–5 pass | Pass — s4 Group B and s5 case 2 each red under a named single-line mutation, restored and re-confirmed green | Pass — one commit per slice, tests + impl + reports together | Pass — s2.5 test review found two assertions vacuous in both phases and replaced them with exact-block equality; s5 test review found a negative that an empty `$output` satisfied |
| 4.0–4.3 | n/a | n/a (`general`) | n/a | Pass — `2fa5328`, `ba68af9`, `ac3735f`, `06e2323` | n/a |

## Defects

### D1 — Item 3.1 slice 1's RED is a stub gap, not a genuine red

*Process defect. No hole left in the suite.*

`item-3-1-s1-red.md` opens: "Stubs landed in `scripts/lib/index-sync.sh`" —
`gitlore_relay_marker_file` printing the bare path, `gitlore_relay_write`
returning 0 and writing nothing, `gitlore_relay_drain` returning 0 with both
variables empty. The tests were then written against those stubs. Case 1 reds on
`[[ "$output" == *-a1 ]]` and case 2 on `[ -f "$marker" ]`; both are syntactic
assertions, but what they observe is the stub's inertness. This is the "stub
gap" the RED contract excludes, and it is the only slice in the run where the
SUT was *added* by the RED agent rather than left untouched.

The consequence showed immediately. Case 3
(`relay_drain on an empty store sets both variables empty and returns 0`)
asserts verbatim what the dispatch specified the stub to do, so it could not be
redded at all. `item-3-1-s1-test-review.md:29-40` works through four candidate
mutations and concludes "the only way to red this case against the specified
stub is to assert something the stub is specified not to do" — a correct
diagnosis of a problem that the stub-first shape created.

**Why it left no hole:** `item-3-1-s1-code-review.md:123-155` ran thirteen
mutations against the *real* implementation after GREEN. Case 4 (the empty-store
case) reds under M1 (drain glob widened to `gitlore-*`) and M9 (drop the two
`=""` initializations). Discrimination was therefore established — one phase
later than the contract asks, and by the reviewer rather than the test author.

### D2 — Item 1.3 slice 1, case 15's mutation proof went stale mid-slice

*Process defect. Hole is narrow and covered elsewhere.*

`recovery: the same recovery for the memory root stages nothing in the parent repo`
was born-green and its comment named the naive predicate (stage whenever
`--show-superproject-working-tree` is non-empty) as the mutation that reds it.
The code review then changed the implementation to stage a *pair*
(`git add -- MEMORY.md memory`) rather than the gitlink alone, and
`item-1-3-s1-code-review.md:172-178` records the consequence: under the naive
predicate a parent with no root `MEMORY.md` now fails the pathspec and stages
nothing, so the case passes for the wrong reason. The reviewer flagged it and
left it — "Flagging it because case 15's own comment claims a proof that is now
weaker than when it was written", repeated in §7 as a residual.

The tree records the correct state: `tests/resolve_recovery.bats:408-411`
carries a paragraph saying the case no longer reds under the naive predicate and
should be read as a characterization. The exclusion clause itself is pinned by
case 18 (`a host project keeping a root MEMORY.md is not a memory store`), which
the same review added. So the clause is covered; what is lost is case 15's own
discrimination, and it is now labelled honestly rather than silently.

The generalisable failure is that **nothing re-runs a born-green case's mutation
proof when the implementation moves underneath it.** The proof was correct when
written and rotted inside the same slice.

### D3 — Item 1.2 slice 2, a negative assertion never observed failing

*Discipline lapse. No hole.*

`tests/commit_memory.bats`,
`a mid-merge tier is reported as a merge, not as a moved pin`, closes with
`[[ "$stderr" != *"moved off the commit the memory store records for it"* ]]`.
The mutation that makes that string appear is the guard hoist, and under that
hoist the *preceding* assertion (`*"holds a merge gitlore did not prepare"*`)
fails first, so the body never reaches the negative. `item-1-2-s2-red.md` states
this plainly — "The second assertion … never executes, because the first already
failed the test — and would also have failed here".

The assertion is falsifiable and its proving mutation is identified; it was
simply never *observed* red. The pairing argument the test's own comment makes
(the positive over the same induction in the neighbouring case) is sound. Listed
because it is the one negative in the run whose red was reasoned rather than
measured — contrast Item 1.2 slice 3, which isolated a narrower mutation
specifically to reach its own negative past the death point.

### D4 — review fixes that ship SUT with no test

*Discipline lapse. One left a real gap, later closed.*

Two review-fix commits change the implementation and nothing else:

- `62258fa 🐛 Item 1.1/3 — code-review fixes` — `scripts/lib/resolve.sh` only,
  41 insertions / 14 deletions. It added the two `touch "$msgfile"` restamps.
  Nothing tested them until Item 1.1 slice 4 was added to the runbook for that
  purpose, and slice 4's RED had to *back them out in place* to get a red
  (`item-1-1-s4-red.md`, "SUT back-out"). That is the runbook recovering from a
  gap it created, and it worked — but the fix shipped untested first.
- `999b17d 🐛 Item 2.1/1 — code-review fixes` — `scripts/lib/index-sync.sh`
  only, 31 lines, adding `_gitlore_agent_suffix`'s `tr -c 'A-Za-z0-9-'`
  sanitization. Item 2.1 slice 2 case 3 pinned it one slice later by mutation.

Both were caught by the following slice. The pattern is what to fix, not either
instance.

### D5 — commit shape changes mid-run

*Discipline lapse. No hole.*

Phase 1 items 1.1/1–1.1/3 and all of Phase 2 split each slice into a slice
commit plus a separate `code-review fixes` commit (`84b5132`, `4042bc0`,
`62258fa`, `999b17d`, `d4c4f47`, `28ef6e6`, `a7dd433`). From Item 1.2 onward
every slice is a single commit carrying tests, implementation and all four
reports (`719b84d`, `e04cb19`, `313cf5d`, `fd43912`, `74dac38`, `2df5283`,
`5462366`, `09e1085`, `ef28a44`). The later shape is the one the contract
describes; the earlier one is not wrong, but the run does not say why it
changed, and the split commits are where the untested-SUT instances in D4 sit.

Two further inconsistencies in the report set, both in Phase 1:

- Item 1.1 slice 2 has **no test-review report** — its evidence lives inside
  `item-1-1-s2-green.md`. Every other slice has one.
- Item 1.2 slices 2 and 3 have **no code-review report**. Both are born-green
  test-only slices with no implementation to review, so this is defensible, but
  Item 1.1 slice 2 — also born-green — *did* get one. The rule was not applied
  consistently.

### D6 — three declared ship-green mutation gaps at Item 3.1 slice 1

*Real hole at the time; two closed by later slices, one standing.*

`item-3-1-s1-code-review.md:133-155` names four mutations no case caught:

| Mutation | Status now |
|---|---|
| M3a — `ls \| grep` instead of `find -print0` | **Standing.** The reviewer argues the case cannot catch it (marker basenames contain no whitespace by construction of `_gitlore_agent_suffix`, and `ls` prints basenames, so the spaced gitdir never reaches the pipeline). Unenforceable by this test, and the runbook's "never an `ls` pipeline" clause is style, not behaviour. |
| M7a — `gitlore_relay_write` returns 0 on a failed open | Closed by Item 3.1 slice 4 case 1 and slice 5 case 1, which pin a failed write's reporting through both hooks. |
| M7b — write leaves a partial file | **Standing.** No case in the suite observes a partially written marker. |
| M12 — drop `-type f` from the drain's `find` | Closed by Item 3.1 slice 5 case 2, whose isolating mutation reds it on the framing assertion. |

M7b is the one worth a decision: the merge semantics Item 3.1 slice 2.5 added
make a partial marker a reachable state, and nothing asserts what a drain does
with one.

## What could not be audited

1. **Per-commit suite greenness for eleven of nineteen slices.** Phase 1
   (`item-1-1-s1/s2/s3/s4-green.md`) and Phase 2 slices 1–3 record gate sentinel
   paths and mtimes. No report for
   **Item 1.3 (both slices) or Item 3.1 (all six slices)** records
   `just precommit`, a gate sentinel, or a full-suite run — each records only
   its own targeted `scripts/run-bats.sh` invocation over two or three suites.
   Item 2.1 slice 4's green report says the gate was "left for the orchestrating
   session"; whether the orchestrator ran it before `e26a7ef` is recorded
   nowhere in `reports/`. The dispatch forbids running the suites here, so this
   cannot be closed from inside the audit.

   What *is* checkable: `.git/gitlore/gates/` at HEAD holds `test-unit` and
   `test-integration` at 15:05/15:06 and `lint`/`check-distribution` at
   15:27/15:26 on 2026-09-11, all postdating the newest gated input
   (`scripts/lib/index-sync.sh`, 14:47). The tree is green **now**; whether each
   intermediate commit was, is undocumented for those eleven.

2. **Whether the reports describe what was actually run.** The audit is
   documentary by instruction. Restore claims are unusually well evidenced —
   `git hash-object`, `sha256sum` and `git diff --exit-code` appear in the
   mutation sections of Items 1.2/2, 1.2/3, 2.1/2, 2.1/3, 3.1/1 and 3.1/4 — but
   the runs themselves are taken on the reports' word.

3. **Subagent transcripts** were not read, per the dispatch — so where a report
   is the only witness to a run, it is also the only witness available.

## Recommendations, ordered by what would most change the next run

1. **Forbid the RED agent from landing stubs in the SUT.** Item 3.1 slice 1 is
   the one slice whose red does not mean what a red is supposed to mean, and the
   reason is that the dispatch asked for stubs to avoid a missing-symbol red.
   The alternative that the rest of this run demonstrates works: treat the slice
   as born-green from the start and require the mutation round against the
   *real* implementation as the deliverable — which is what the code review
   ended up doing anyway, one phase late.

2. **Re-run a born-green case's mutation proof whenever its slice's
   implementation changes.** D2 is a proof that rotted inside its own slice,
   between GREEN and code review. Make the code-review step's mutation matrix
   explicitly re-execute every mutation the RED and test-review reports named,
   and fail the slice when one no longer reds — rather than noticing it in
   passing and filing it as a residual.

3. **Require a test in the same commit as any review fix that changes the SUT.**
   D4's two instances both shipped behaviour that nothing exercised, and both
   were only covered because a later slice happened to reach them. The Item 1.1
   slice 4 back-out is the cost: a subsequent slice had to un-write the fix to
   obtain a red for it.

4. **Record the gate verdict in the green report, not just in the orchestrator's
   session.** Eleven of nineteen slices have no auditable evidence that the
   suite was green when they were committed. The Phase 1 and Phase 2 reports
   show the format that works — gate path, mtime, and the input it postdates —
   and it costs one paragraph.

5. **Prefer the isolating mutation over the pairing argument for a negative
   assertion.** Item 1.2 slice 3 shows the technique: when the dispatch's
   literal mutation kills an earlier assertion first, construct a narrower one
   that leaves the earlier text intact so the negative is reached and observed.
   D3 is the case where that was not done, and Item 3.1 slice 5 case 2 shows the
   same technique applied successfully two phases later.

6. **Settle M7b** (Item 3.1: a partially written relay marker) or record it as
   an accepted gap in the design node. It is the only mutation gap from this run
   that no later slice closed and that is not argued to be unenforceable.

7. **Fix the report-set inconsistencies** (D5): one test-review per slice
   including born-green ones, and a stated rule for whether a test-only slice
   gets a code review.

## What the process got right, worth keeping

- **Item 1.2 slice 3's per-assertion mutation table** — four assertions, four
  isolating mutations, each observed failing on its own line, plus a note on
  which fragment discriminates what. This is the standard the rest of the run
  should be measured against.
- **Assertion-order swaps in scratch copies** (Items 2.1/3, 2.1/4, 3.1/2, 3.1/3)
  to prove assertions behind a death point independently discriminate, with the
  scratch file appended in place rather than relocated so `load helpers/…` still
  resolves.
- **The three-`CLAUDECODE`-world runs** (Items 1.2/3, 1.3/1, 1.3/2) — the
  subagent's ambient `CLAUDECODE=1` is exactly the environment that hides a
  broken `unset` in a test body, and running all three worlds catches it.
- **The `jq -r` null trap handled explicitly**, with the reasoning in the test:
  `tests/cc_hook_session_start.bats:390-396` pins `[ "$sysmsg" != "null" ]` and
  `[ "$ctx" != "null" ]` *before* two refutations, and says why.
- **Guarded fixture restores placed immediately after `run`**, with comments
  explaining that an assertion inserted above them would strand a 0500 gitdir
  and defeat teardown (`tests/index_sync.bats:1200-1205, 1248-1256`).
- **Visible runbook revision.** Eight commits revise the test lists mid-run and
  each names what revealed the change: `78aa16a` (slice 3's rc-1 induction after
  slice 1's guard), `05f2bfd`, `b3ca090` (Item 1.2 scheduled, Item 4.0 added),
  `fab33d4`, `7800151` and `32b2fbb` (slice 2.5 added and recorded), `2f5aa12`,
  `50b3fca` (slice 5 added). The proofed runbook (`aed4254`) carried only Items
  1.1, 2.1, 3.1, 4.1, 4.2 and 4.3 — Items 1.2, 1.3 (which landed inside its own
  slice commit `e04cb19`), 4.0, Item 3.1 slice 2.5 and Item 3.1 slice 5 were all
  added as slices revealed them. The plan was kept honest as it executed, which
  is the audit criterion for revision and it is fully met.
