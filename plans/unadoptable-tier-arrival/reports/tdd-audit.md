# TDD audit: unadoptable tier arrival, Phases 1-4

**Scope**: tdd Items 1.1, 2.1, 2.2, 2.3, 3.1 and 4.1. Inputs are the item
reports (red, test-review, green, code-review), `phase-{1,2,3,4}-corrector.md`
and `phase-6-docs.md`, checked against `git log e60ff38..HEAD`. **Method**:

- Diffs of every test file in each commit. Only added lines are expected; every
  removed line was inspected.
- Each RED report's quoted assertions, and each test review's claimed fixes,
  grepped in the GREEN commit's blob and at HEAD.
- The gate sentinels in `.git/gitlore/gates/` compared with the gate input hash
  of HEAD, `38ab788`, `650ec53` and `af79f3f`, computed read-only the way the
  justfile's `gate-inputs-hash` does.

No suite was run.

**Verdict**: RED discipline is strong. Every non-guard test failed on an
assertion before its implementation, and every guard has a recorded mutation
red, or a red against pre-job code that the runbook's guard convention accepts.
The one exception is a single corrector guard. No assertion was loosened between
RED and GREEN or in any later commit. The findings that matter:

1. **The Phase 4 checkpoint commit `b165de3` (HEAD) has no full-suite pass on
   record.** The `test-unit` and `test-integration` sentinels hold the gate hash
   of `38ab788`, not of HEAD.
2. **Review commits changed behaviour without tests, and one review-added test
   has no red evidence.**
3. **Batched GREENs were written whole.** The loss this caused showed up as
   surviving mutants that later reviews had to close.

## Commit map

| Item | RED/review (uncommitted) | GREEN commit | Review-fix commit | Checkpoint |
|---|---|---|---|---|
| 1.1 s1 | red, test-review | `7f143cf` (tests + impl) | `9a7e277` (scripts only) | |
| 1.1 s2-6 | red (guards), test-review | `f3381c5` (tests only, guards) | none | `2077983` |
| 2.1 | red, test-review | `b0e19de` (tests + impl) | `a23d3e8` (scripts only) | |
| 2.2 | red, test-review | `7b8407f` (tests + impl) | `94687cb` (scripts + 1 test) | |
| 2.3 | red, test-review | `3287a66` (tests + impl) | `5236fe5` (scripts + 2 tests) | `2edbd1b` |
| 3.1 | red, test-review | `a59061f` (tests + impl) | `430b6ac` (scripts only) | `af79f3f` |
| 4.1 | red, test-review | `650ec53` (tests + impl) | `38ab788` (scripts + 1 test) | `b165de3` |

All reports named in the brief exist. There is no GREEN or code-review report
for Item 1.1 slices 2-6. That is by design: the orchestrator committed the
guards directly.

## Per-item findings

### Item 1.1 (K5 prevention)

**Slice 1.**

- **RED evidence**: genuine. The test failed at `[ "$status" -eq 1 ]`, and a
  probe outside bats showed the advisory arm exiting 0.
- **Test review**: found two surviving plausible-wrong implementations. One kept
  the advisory text and appended "aborted" (m4). The other changed only the
  agent arm (m5). The review added a negative on "the commit went ahead", a
  `unset CLAUDECODE` run and state pins. The test stayed red at the same
  assertion, and the recorded mutation table proves the fixes discriminate.
- **Integrity**: the RED-quoted assertions and the test review's additions
  (`unset CLAUDECODE`, "Open this project in Claude Code", the `live` pin,
  `branch -f live`) are all in `7f143cf`'s blob and unchanged at HEAD.
- **GREEN**: one test, grown in one iteration after an errexit diagnosis. The
  report is credible.
- **Code review (`9a7e277`)**:
  - Added a fail-closed arm for a failing `git status`, which restamps and
    returns 1.
  - Reordered the dirtiness read.
  - Recorded a mutation red on the committed SUT.
  - **Gap**: the new fail-closed arm has no test, and the reviewer said so. It
    is the one outcome K5 exists to prevent, so it is not decoration.

**Slices 2-6 (guards).**

- **Batching effect**: slice 1's GREEN delivered the helper (slice 6), the
  `-- MEMORY.md` pathspec (slice 4) and root attribution (slice 3). All five
  slices were therefore born green.
- **Mutation reds**: recorded for each, with scratch-and-restore and a
  `git diff --quiet` check after every mutation. The dispatch named both slice 4
  variants (pathspec dropped, no read at all), and the RED report shows which
  test each variant reds.
- **Test review**: reproduced the slice 2 and slice 5 mutations and found one
  that survived every test: root's pathspec dropped. It added "a root index
  dirty only outside MEMORY.md commits and reports" with a recorded red. It also
  tightened slices 2 and 3 to pin the abort arm. This is exactly the per-slice
  guarantee batching loses: implementation outran the tests, and only the
  review's mutation hunt closed the gap.
- **Not re-run**: the review did not re-run the slice 4 or slice 6 mutations
  against the tightened tests. It confirmed them by reading. The tightenings
  only add assertions, so a recorded red cannot turn green. Low risk.
- **Integrity**: every review addition is present in `f3381c5` and at HEAD:
  `touch -t 200001010000`, `committed_carrier_defect_store`, the rule 3 message,
  the decoy and the `b` query.

**Phase 1 corrector (`2077983`).** Two tests, each red against HEAD's script at
the named assertion. Compliant.

### Item 2.1 (`gitlore_repair_index`)

- **RED evidence**:
  - Ten tests red on their own assertions against an inert stub.
  - Three guards (slice 1, both slice 4 tests) have a mutation red.
  - The recorded mutation, `printf '\n' >> "$1"`, is weak: any edit reds it. The
    test review said so and ran targeted mutations: same-bytes rename, weld
    guard keyed on the first path, scratch file under `$TMPDIR`.
  - The review's new slice 6 row ("of several lines the pin lacks, the first
    survives") was red against the stub.
- **Test review quality**: high. It closed six real gaps before GREEN:
  - an inode check (`-ef`);
  - the second-path-only fixture;
  - `cmp` against a terminated expected file;
  - a trailer-leading blank;
  - the scratch location;
  - first versus last pin-lacking line.
- **Integrity**: every RED-quoted `[ "$output" = … ]` and every review addition
  (`-ef clean.link`, the several-lacking row, the root skip, the slice 3
  second-path-only fixture) is in `b0e19de` and unchanged at HEAD.
- **GREEN process — batching loss**: the report says the implementation was
  "written whole, not grown incrementally", and each of the 14 tests "passed on
  the first run". No test drove any part of the code. Consequences, all found
  later by review rather than by a test:
  - quadratic forks: 31 s on 200 bullets;
  - an extra subshell per bullet in every check;
  - empty-array expansions under `set -u` that abort on bash 3.2.
- **Commit verification**: the GREEN ran only `tests/index_compose.bats`, but
  `b0e19de` also refactored `gitlore_welded_path`, which every compose check
  uses. `commit_memory.bats` and `merge_memory.bats` were first run by the code
  review, on its fixed tree, so `b0e19de` itself was never run against them.
  Nothing indicates it was red. It is unverified.
- **Code review (`a23d3e8`)**: scripts only.
  - The bash 3.2 fix cannot be tested on this box (acknowledged).
  - The mode fix (`cp -p`, so a rewrite keeps 0644) is observable and testable,
    but no test was added.
  - The pin-rule mutation was recorded red. Compliant otherwise.

### Item 2.2 (repair in the take)

- **RED evidence**:
  - All seven tests red on assertions, with verbatim output. Premises were
    checked on the bare remote.
  - Slices 2 and 5 are runbook guards, recorded red against pre-job code. The
    runbook allows this.
  - Slice 3 red on the report line, not on status. The report says status and
    `gone/x.md` already passed by coincidence.
- **Weak red (slice 6)**: the red came from "feature absent" (no repair, so the
  lock is never contended), not from mishandled lock refusal. After the test
  review, the test asserts the adoption message, no report line, a clean
  `log --all --reflog` and a clean gitdir listing. No mutation of the refused
  `push .` arm was run against the green. The code review's only mutation (drop
  `rm -rf`) reds slices 4 and 6 on the scratch listing, not on the refusal
  handling. Residual: the refusal-arm assertions are unproven by a red.
- **Test review**: found parents read as `$2` only, a hand-copied fixture,
  lock-site ambiguity, reflog blindness, no scratch check and a worktree read of
  R. All were fixed, and the tests stayed red. Integrity confirmed: the exact
  parent lines, `--reflog`, `tier_gitdir_files`, `adopted them at`, the
  `line $((weld_line_n - 1)) welds` negative and `cat-file -e` are all in
  `7b8407f`.
- **GREEN**: "No test was weakened or edited" holds, since every review
  assertion is in the commit. The tests were run one at a time, but "no test
  needed a second implementation attempt" reads as one implementation checked
  per test, not grown per test.
- **Code review (`94687cb`)**:
  - `--no-filters`, the checked pin read and the scratch consolidation have no
    test (the `--no-filters` gap is acknowledged).
  - The reviewer reported a surviving mutant: pass a nonexistent pin path and
    all seven repair tests stay green. The reviewer wrote no test ("tests out of
    scope").
  - Yet `94687cb` adds "a take's repair keeps the duplicate its pin lacks".
    **No report records who wrote it or any red evidence for it.** The test is
    shaped to kill that mutant, but its red is unconfirmed.

### Item 2.3 (publication)

- **RED evidence**:
  - Slices 2 and 3 red on assertions. Slice 3's cause was diagnosed: adopting
    before the fetch makes sibling repairs.
  - Slices 1 and 4 are guards with mutation reds.
  - The test review strengthened slice 1's mutation. The original red was on
    exit status only; the stronger mutation reds on the hook snapshot, so the
    test pins publish order.
  - A satisfiability sketch confirmed that no assertion over-demands.
- **Test review**: added the memory-remote gitlink check, an appending hook
  (catches double pushes), the exact parent line and slice 3 premises.
  Integrity: `[ -s "$hookfile" ]`, the hook-content equality, `live:ddaanet = R`
  and `>>` are all in `3287a66`.
- **GREEN**: red-then-green observed for slices 2 and 3. Compliant.
- **Code review (`5236fe5`)**:
  - Test A (no remote) is red against `3287a66` with the adoption dropped.
  - Test B (failed adoption hides a failed fetch) is red against `3287a66`
    unmodified.
  - The mutation table shows the remaining mutations all red.
  - The reviewer ran two bats suites at once, against the dispatch constraint.
    It says so itself, and both came back green.
- **Phase 2 corrector (`2edbd1b`)**:
  - Three message assertions and the containment test, each red against HEAD or
    the reverted guard.
  - The resting-push guard, red under the `|| :` mutation.
  - The commit also carries a `plans/…/runbook.md` rewrap. It is harmless, but
    it is plan content in a code commit.

### Item 3.1 (continuation gate)

- **RED evidence**:
  - Slices 1 and 4 (four tests) red at `[ "$status" -eq 1 ]`, from today's
    landing behaviour.
  - Slices 2 and 3 are guards whose RED failure was premise-only (slice 1
    absent).
  - The test review removed `|| true` so they fail visibly at the premise. It
    then recorded mutation reds against a green sketch: slice 2 when the refusal
    clears state, slice 3 when a marker blocks reruns.
  - Slice 5 has mutation reds both on today's code and on the sketch.
- **Test review**: caught a wrong `mem_before` capture that would have failed a
  correct implementation. The sketch run found it. The review also added the
  flavor assertions, root `cmp` and the exact second-parent check.
- **Planned inversion**: `a59061f` removes the old "a compose refusal is
  reported but never strands the merge" assertions and adds the rewrite, as the
  runbook's slice 4 requires. This is the only assertion removal among the item
  commits and is not a weakening.
- **Integrity**: `was not committed`, the attributed line, `root-before`,
  `.flavor`, `committed uncomposed` and the renamed test are all in `a59061f`.
- **Code review (`430b6ac`)**: `return 1` became `exit 1`. There is no
  observable difference at the only call site, so no test is needed. Compliant.
- **Phase 3 corrector (`af79f3f`)**:
  - The directive test is red against HEAD's library.
  - **Gap**: "a tier merge whose incoming side welds a line is refused, and the
    split synthesis publishes" is recorded only as "a guard: it holds on HEAD".
    No mutation red is recorded. It is the one guard in the run without red
    evidence.

### Item 4.1 (per-arm exits, rest guard)

- **RED evidence**:
  - Slices 1 and 2 red on their behavioural assertions.
  - Slice 3 red as a cascade of slice 2: zero remedy lines.
  - Slice 4 born green, with a mutation red (`return 1` routes to the `*)` arm).
  - The test review ran a green sketch with a spaced `TMPDIR` and six mutations.
    Each reds for its stated reason, including unquoted and relative `abs` in
    slice 3. That makes the cascade test discriminating on its own.
- **Test review**: caught a real lint blocker (SC2030/SC2031 at default
  severity) and tightened merge identity, the lock site and an exact four-line
  remedy glob. Integrity: all present in `650ec53`.
- **GREEN**: compliant. All four checked in order.
- **Code review (`38ab788`)**:
  - The new test is red on `650ec53`: the checkout line exited 0.
  - The fix changes the runbook-pinned remedy line 2, and the exact-text
    assertion changed with it (the one removed `-` line in `38ab788`). The
    assertion is now a longer exact line, not a looser one. The change is
    recorded for prose.
- **Phase 4 corrector (`b165de3`)**: two tests, each red against the unchanged
  script. See the gate finding below.

## Cross-cutting findings

### F1 — HEAD's unit and integration gates are not on record (Major)

- **Sentinels versus hashes**:
  - The `lint` sentinel matches HEAD's input hash: `1717919746 1346281`.
  - The `test-unit` and `test-integration` sentinels both hold
    `4206970973 1343805`, which is the input hash of `38ab788`'s tree.
- **Timing**: they were written at 03:25-03:26. The gated inputs
  `tests/tier_divergence.bats`, `tests/resolve_compose.bats` and
  `scripts/resolve.sh` were last modified at 03:34, 03:35 and 03:39, and
  `b165de3` landed at 03:41.
- **Result**: the Phase 4 corrector's changes are committed without a full-suite
  pass on record. Those changes are the default-mode store order in
  `resolve.sh`, the `merge_msgfile` cleanup and two tests. The corrector ran six
  touched suites green.
- **The count**: the reported "915 unit" fits `b165de3`'s test count. The
  `@test` delta from `af79f3f` is +7 at `b165de3` and +5 at `38ab788`, against a
  constant offset from the earlier phase counts. The sentinel hash fits
  `38ab788`. Both can hold only if the run globbed extra tests from somewhere,
  for example the corrector's temporary probe copy of
  `tests/resolve_compose.bats`, which would be an untracked `tests/*.bats`
  deleted before `record-sentinel` hashed the tree.
- **Confidence**: that explanation is an inference and is unconfirmed. Either
  way, the gate ran while a corrector was editing and running bats, and it
  verified a tree that is not HEAD.
- **Earlier phases**: the 870, 900 and 908 gates cannot be checked from
  sentinels, because later runs overwrote them.

### F2 — Behaviour added in review commits without a test (Minor to Major)

| Commit | Untested behaviour | Testable here |
|---|---|---|
| `9a7e277` | failed `git status` in the rc 1 arm restamps and aborts | yes: a tier `.git` gitfile pointing nowhere (the reviewer's own suggestion) |
| `a23d3e8` | rewrite keeps `<file>`'s mode (`cp -p`) | yes: `stat` before and after |
| `a23d3e8` | bash 3.2 `set -u` empty arrays | no (no bash 3.2 on this box) |
| `94687cb` | `hash-object --no-filters` keeps CRLF bytes | yes: `core.autocrlf=true` fixture |
| `2edbd1b` | process-substitution removal in the region read | covered by the existing 81 tests (refactor) |

### F3 — Review-added tests without red evidence

- **`94687cb`**: "a take's repair keeps the duplicate its pin lacks". No author,
  no red. The mutant it targets (nonexistent pin path) is on record as surviving
  before it.
- **`af79f3f`**: "a tier merge whose incoming side welds a line is refused, and
  the split synthesis publishes". A guard with no mutation.

### F4 — Batching and whole-GREEN writing

What the batching kept:

- **Before GREEN**: each test reds on its own discriminating assertion.
- **Before commit**: a test review ran over the whole batch, and for Items 2.3,
  3.1 and 4.1 against a green sketch. This caught more than a per-slice protocol
  would have: cross-slice fixture errors such as 3.1's `mem_before`, and the
  lint blocker.

What it lost:

- **Incremental drive**: no GREEN shows a test driving code incrementally. 2.1
  is explicit about it, and 2.2, 3.1 and 4.1 read the same way.
- **Surviving mutants**: the implementation outran the tests, and later reviews
  found mutants still alive:
  - 1.1: root pathspec;
  - 2.2: pin path not reaching the repair;
  - 2.3: no-remote adoption dropped.
- **Guards born green**: 1.1 slice 1's GREEN delivered all five later slices, so
  they were green before they were written. The mutation-red protocol recovered
  the proof, but only because the test review hunted mutants beyond those the
  RED dispatch named.
- **Slice-order dependence**: no slice passed only because a later slice's
  implementation landed in the same GREEN in a way that hid a defect. Each
  batch's reds were on independent assertions.

### F5 — Intermediate commits unverified by the full suite

GREEN dispatches ran touched bats files instead of `verify-step.sh`. Suites
touching a changed library were sometimes skipped. The clearest case is
`b0e19de`: a compose-check refactor verified only by `index_compose.bats`. Every
checkpoint commit before HEAD is claimed green; intermediate commits are not
known to be red either. Bisectability is unproven, not disproven.

## Compliance summary

| Criterion | 1.1 | 2.1 | 2.2 | 2.3 | 3.1 | 4.1 |
|---|---|---|---|---|---|---|
| RED on an assertion, right reason | yes | yes | yes (slice 6 weak) | yes | yes | yes |
| Guards with mutation red | yes | yes | pre-job red (allowed) | yes | yes | yes |
| Test review strengthened, still red | yes | yes | yes | yes | yes | yes |
| No loosening RED→GREEN→HEAD | yes | yes | yes | yes | yes (planned inversion) | yes (remedy text changed, not loosened) |
| GREEN commit carries tests + impl | yes (s2-6 guard-only) | yes | yes | yes | yes | yes |
| GREEN grown one test at a time | n/a (1 test) | no (written whole) | unclear | yes | unclear | yes |
| Review fixes tested with red | partial (`9a7e277` none) | partial (`a23d3e8` none) | unconfirmed (`94687cb`) | yes | yes; corrector guard no | yes |
| Checkpoint gate on the committed tree | unverifiable | — | unverifiable | — | unverifiable | **no** (sentinel = `38ab788`) |

## Recommendations

1. **Run `just precommit` on HEAD now**, in the background, before any further
   commit. The unit and integration sentinels do not match HEAD, so the gate
   will run rather than hit the cache. Treat Phase 4 as ungated until it passes.
2. **Never run a phase gate while a corrector or reviewer is live in the tree.**
   Run it after the checkpoint's fixes are final, and confirm with the sentinel
   hash rather than the pass count. A test count can include a temporary suite
   that is gone by the time the tree is hashed.
3. **Close the F2 rows marked testable**: the `git status` failure arm, file
   mode preservation and `--no-filters`. Each is a cheap fixture in an existing
   suite.
4. **Record a mutation red for the two F3 tests.** For `94687cb`'s pin test,
   pass a missing path in place of `$scratch/pin`. For `af79f3f`'s
   weld-synthesis guard, drop the gate's `exit 1`. Record the results in a
   report, so every test in the run has red evidence.
5. **Add a refused-push mutation to Item 2.2 slice 6**: ignore the `push .`
   status and continue. Its current red proves only that the feature is absent.
6. **Grow a batched GREEN one test at a time**, or have the test review always
   run a targeted mutant hunt against the GREEN, as 2.3, 3.1 and 4.1's reviews
   did against a sketch. The reviews that did so closed the gaps whole-GREEN
   writing opened. The RED-only reviews (1.1 s1, 2.1, 2.2) left mutants for
   later reviewers.
7. **Run every suite that sources a changed library in GREEN**, not just the
   file whose tests changed. For `index-compose.sh` that is at least
   `commit_memory`, `merge_memory` and `resolve_compose`. Alternatively, run
   `verify-step.sh` as the per-slice protocol intends.
8. **Name the author of review-added tests.** When the orchestrator writes a
   test into a review-fix commit, it should write a short report with the red,
   as the correctors did.
