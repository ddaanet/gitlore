# Item 1.1 — TDD audit

Both slices of Item 1.1, across `4dd02bc`, `0cce041`, `16abc35`, `6790195`,
`9188da5`. Nothing committed; nothing in the tree changed by this pass.

**Verdict: the RED discipline held on both slices and is well evidenced. The
gap is not in RED — it is that the runbook's slice specs named only the states
the design had already reasoned about, so every state the design missed
(empty, blank, consumed) reached a commit before any test saw it, and was
caught by a review rather than by the suite.** Three of the four review passes
found a MAJOR correctness defect in code that had gone green.

Runs made for this audit:

- `bash scripts/run-bats.sh tests/commit_memory.bats
  tests/commit_memory_approval.bats tests/cc_hook_memory_commit_batch.bats
  tests/commit_memory_retry.bats` — **43 passed, 0 failed**, matching the
  corrector report's count.
- `just lint` — `lint: cached (inputs unchanged)`, so the lint gate is valid
  for the scripts as they stand at `HEAD`.

## Per-slice RED evidence

### Slice 1 — sound, and the review earned its place

`item-1-1-s1-red.md` names two tests, each with the failing assertion, its
file:line and the TAP block: `[ "$status" -eq 0 ]` at :63 and the
`no approved commit summary` match at :86. Both are assertion failures, not a
missing command and not a bats error, and the report states which pre-existing
behaviour makes each red.

`item-1-1-s1-test-review.md` re-ran the suite *before editing* and reproduced
16/2 with the same two assertions — an independent observation of the red,
which is the strongest form of RED evidence in this set. It then found a
CRITICAL: the runbook's own discriminating negative, `does not contain -m`
(runbook.md:26-27), is unsatisfiable, because the sync's refusal names
`gitlore-memory-message` and that basename contains `-m`. Verified empirically
with a scratch bats probe over the real fixture rather than by reading, and
narrowed to `!= *"Pass it with -m"*`. Two further fixes closed vacuous passes
(HEAD-moved + commit-subject on the fresh test; byte-exact `cmp` + an mtime
marker on the stale one). Final red re-run recorded at the shifted lines.

One residual, correctly recorded by the slice-1 code review and re-confirmed by
the corrector: no mutation of `commit-memory.sh` can isolate the stale test's
`[ ! "$msgfile" -nt "$TMP_REPO/before-run" ]` restamp guard, because any
restamp on that path also flips the exit status. It is belt-and-braces, not
vacuous; the discriminating assertions are the status and the `cmp`.

### Slice 2 — sound

`item-1-1-s2-red.md` names one test, one assertion
(`[ "$(git -C memory rev-parse HEAD)" = "$head_before" ]` at :191), with the
TAP block and a paragraph tracing why unchanged code commits there. The two
tests required to stay green unchanged are named and confirmed among the 11
passing.

`item-1-1-s2-test-review.md` again re-ran before editing and reproduced the
failure at the same line, then fixed three real holes: `[ -f "$msgfile" ]`
could not see a restamp (the defect moved one batch later), the third batch did
not prove the commit was on the *rewritten* approval, and a GREEN that
discarded the fix would have passed. Its "checked, no defect" section verified
the satisfiability of the `retries by itself` negative by grepping the tree
rather than reading the design — the discipline the slice-1 `-m` finding
called for, applied.

The runbook's slice-2 spec was revised before dispatch to carry that lesson
(runbook.md:39-40 names the same shape and points at slice 1's review). **The
slice-1 spec was not corrected**: runbook.md:26-27 still specifies the
unsatisfiable `-m` negative, so the runbook now misdescribes what shipped. Low
severity — `plans/` is frozen and the reports carry the correction — but a
reader reconstructing the slice from the runbook alone gets a test that cannot
pass.

## Commit discipline

Five commits, all gitmoji-prefixed by the commit-msg hook, which is positive
evidence that no commit ran with `--no-verify`.

| Commit | Contents |
|---|---|
| `4dd02bc` | slice-1 tests + impl + design.md, runbook.md, recall-artifact.md, 3 reports |
| `0cce041` | slice-1 review fixes + the empty-file test + review report |
| `16abc35` | slice-2 tests + impl — **no reports** |
| `6790195` | slice-2 review fixes + the consumed-approval test + 4 reports |
| `9188da5` | corrector fixes + 3 tests + the suite split + report |

Four observations, in descending order of weight.

1. **The Phase 1 checkpoint was committed without a completed `just
   precommit`.** `phase-1-corrector.md` states it plainly ("`just precommit`
   was not run, per the dispatch"; `test-integration`, `check-memory-hygiene`
   and `check-version` "were not exercised"), and the orchestrator committed
   `9188da5` at 17:26:43 anyway — a commit that changed both production scripts
   and split a test suite. The gate directory shows `test-unit` at 17:25 (the
   corrector's own 95-suite run, so unit coverage did precede the commit) but
   `test-integration` at 17:28, i.e. **90 seconds after the commit**. Coverage
   exists now; it was established post-hoc. The repo rule is that `precommit`
   is the gate before every commit, so this is a real departure, cleanly
   recoverable and correctly self-reported by the corrector.
2. **Slice 2 shipped one commit ahead of its own RED evidence.** `16abc35`
   carries the implementation with no report in the tree; `item-1-1-s2-red.md`,
   `-test-review.md` and `-green.md` first appear in `6790195`. For the
   duration of one commit the repository held an implementation whose red
   evidence was not in it. Self-corrected, but it is the one place the history
   alone cannot vouch for the order of work.
3. **The plan artifacts were first committed with the code they specify.**
   `design.md`, `runbook.md` and `recall-artifact.md` are all new files in
   `4dd02bc`. Nothing in history shows the spec predating the implementation;
   the reports' own timestamps (RED at 14:18 vs the commit at 15:20) are the
   only ordering evidence.
4. **Slice 1's GREEN was written and verified by the same actor that finished
   it.** `item-1-1-s1-green.md` says so in its first paragraph — the dispatch
   stalled on a gate-file Monitor after launching `just precommit`, and the
   orchestrator re-hashed the gates and committed. Honest, and the gate
   mechanism is exactly what makes a stalled dispatch recoverable. The
   independent check that would otherwise be missing is supplied by the
   slice-1 code review, which found a MAJOR in that tree.

No commit bundles a red task into a green one, no test file was edited in a
commit whose message claims otherwise, and every report's "the only tracked
change in the tree is X" claim matches the diff of the commit that carried it.

## Test integrity

**No test was weakened or lost.** The checkpoint's split of
`tests/commit_memory.bats` (399 → 320) into `tests/commit_memory_approval.bats`
(128) moves the six-test approval group **byte-identically** — the deleted
block and the new file's bodies are the same text, verified by diff. The new
suite carries `bats_require_minimum_version 1.5.0` and its three `load` lines,
and the discovery check is real: `just test-unit` went 94 → 95 suites and
1020 → 1024 tests, which reconciles exactly (+1 from `6790195`, +3 from the
checkpoint).

The corrector's mutation table is internally consistent and reconstructible.
Row 3's "19 passed, 2 failed" with the failures at `not ok 9`/`not ok 10` only
adds up against the **pre-split** file (19 tests at `0cce041`, plus the two new
blank tests landing at positions 9 and 10) — so that mutation was run before
the split, not after. The split being byte-identical makes that fine, but it is
worth knowing that no mutation was re-run against the current file layout.

One pre-existing weak assertion survives the move, in `refuses dirty memory
with no summary`:

```
  [[ "${output}${stderr}" == *"approved summary"* ]] || \
    [[ "${output}${stderr}" == *"-m"* ]]
```

A disjunction passes on either arm, and the second arm matches any message
containing `-m` — including, now, the sync's own refusal naming
`gitlore-memory-message`. It does not discriminate the entry point's directive
from the refusal the bare path routes to. Pre-existing, untouched by this item,
and cheap to tighten to the first arm alone.

## Tests that never had a watched red

Five, in three groups. None is decoration; two rest on something weaker than a
mutation.

**Adequate — mutation applied in place, red observed on the named assertion,
edit inverted and `git diff` confirmed empty.** The three blank-approval tests
added at the checkpoint (`a blank approval file is no approval and does not
become a per-batch retry loop` in the hook suite; `bare invocation refuses a
blank approval file, which -s alone admits` and `-m with a blank summary
refuses instead of dying on git's empty message` in the approval suite) are
covered by mutation rows 1 and 3, each reverting the exact predicate under
test. That is a full substitute for a watched red: the mutation *is* the
pre-fix code.

**Adequate, with the discrimination carried by assertions added later.** The
three assertions the checkpoint added to `a commit that landed but could not
advance live …` (`the memory commit landed`, not `retries by itself`, not
`approved summary preserved`) are covered by mutation row 2, which makes the
arm unreachable and reproduces the `!= "no"` routing.

**Weaker — red by construction, never observed, and no standing mutation.**

- *`bare invocation refuses an empty approval file as no approval at all`*
  (`0cce041`, orchestrator-added). The substitute offered is the slice-1 code
  review's empirical probe against the committed `-e` code, which recorded
  `ERR: Aborting commit due to empty commit message.`, status 1, HEAD unmoved,
  `msgfile size: 0` over the same fixture shape. The test asserts `Pass it with
  -m` present and `empty commit message` absent, so that probe pins the exact
  strings and establishes two assertions would have been red. That is good
  evidence — but it was gathered from a scratch bats file before the test
  existed, and nobody watched *this* test fail.

  **The corrector's claim that the mutation table closes this is an
  overclaim.** `phase-1-corrector.md` says "the empty-file test and the
  landed-then-failed test both exist and both discriminate (mutation table
  above)". Row 3 reverts the screen to `-s` alone, and a zero-byte file still
  fails `-s`, so that mutation leaves this test **green**. The mutation that
  isolates it is `-s` → `-e`, and it is not in the table. Verified by reading
  the current predicate at `scripts/commit-memory.sh:70` against the test's
  `: > "$msgfile"` fixture. The test does discriminate against an `-e`
  regression; the table just does not show it.

- *the original three assertions of `a commit that landed but could not advance
  live …`* (`6790195`, orchestrator-added): `Reason:` present, `memory merge
  prepared` present, `no longer covers` absent. Against the pre-fix
  `[ "$fresh" = "yes" ]` routing all three would have been red, and the
  slice-2 code review traced exactly that path through
  `resolve-sync-memory.sh:245` and its three `return 1` arms — but did not run
  it. Under the code as it now stands, after the checkpoint moved the
  consumed-approval state to its own `[ ! -s "$msgfile" ]` arm tested first,
  mutation row 2 leaves all three **passing** (the fall-through arm still
  carries `$out`). The corrector saw this and added the three discriminating
  assertions above; so the arm is guarded, but by the checkpoint's assertions
  rather than by the ones committed with the fix.

## The pattern worth carrying forward

Every MAJOR found in this item was a state the design had not enumerated, and
in each case the suite was green over it:

| Found by | State the suite could not see |
|---|---|
| slice-1 code review | approval file exists and is **empty** |
| slice-2 code review | approval file **consumed** by a commit that then failed to advance `live` |
| phase-1 corrector | approval file **all-whitespace** (one byte past the previous fix) |
| phase-1 corrector | the deferred message is **false** on the consumed path |

RED cannot catch these, because RED writes the tests the spec names and the
spec named the states the design had reasoned about. What caught them was a
review instructed to probe rather than read — and every one of those probes was
empirical, which is why they landed. The lever for the next tdd item is at
runbook-writing time: for an entry point guarded by a predicate, have the slice
spec enumerate the predicate's boundary states (absent / empty / blank /
consumed) rather than only the two the design's narrative discusses.

## Flagged, for whoever closes Phase 2

1. **The design's third state is uncommitted.** `design.md` gained a 14-line
   paragraph describing the consumed-approval arm, and it is still a
   working-tree change. At every commit of Item 1.1 the shipped hook emitted
   three failure messages against a committed design that described two. The
   corrector flagged this; the fix is in flight, not landed.
2. **runbook.md:26-27 still carries the unsatisfiable `-m` negative** for
   slice 1.
3. **`phase-1-corrector.md`'s "both discriminate (mutation table above)"**
   should be narrowed, or an `-s` → `-e` mutation run and added as a fourth
   row.
4. The three defects the corrector flagged as pre-existing and out of scope —
   a prepared merge met with a request for approval, the clean-memory branch's
   overstated "Both IPC files are gone", and the blank-approval predicate
   duplicated across two scripts instead of living in `scripts/lib/util.sh` —
   are unaddressed and belong on a follow-up, not in this item.
