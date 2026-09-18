# TDD audit — tier-arrival-review-minors, Phases 1–4

Scope: the tdd Items 1.1, 1.2, 2.1, 2.2, 3.1 and 4.1 (with slice 4.1/3 added in
`b7962b3`), audited from the per-slice reports, the phase checkpoint reports and
the job's commits (`3502a86..HEAD`). No test was re-run for this audit; the
evidence below is what the reports and the diffs show.

## Verdict

The discipline held. Every non-guard slice has a RED that failed on an assertion
rather than an error, and every GREEN commit carries test and implementation
together. The three guards were each proven by mutation. No assertion was
weakened between RED and GREEN or in any later commit. The reviews caught real
defects before they landed: a test that could never go green (2.1/1), a
regression that removed publication on an early return (2.1/1 → slice 2.1/2), an
errexit ordering defect (4.1/1), an untested arm (1.1/2 → guard 1.1/5), and a
lookalike fix that passed (2.1/2).

The gaps are in the record, not in the code:

1. Item 1.2 skipped per-slice review. Slice 1.2/1 has no code review, and 1.2/2
   has neither a test review nor a code review. The Phase 1 corrector then found
   a **Major** regression that 1.2/1 introduced.
2. Guard 1.1/5 has no test review, although the runbook said "The test review
   proves it".
3. The `.claude/handoff-task.md` summary (as of `ae91e12`) misstates both of the
   gaps above.
4. No slice has a whole-suite green record at its own commit. GREEN is
   file-scoped, and whole-suite runs are claimed only at phase boundaries, in
   handoff prose, with no artifact.

## Per-slice ledger

Commit = the slice commit. CR fix = the separate code-review fix commit.

| Slice | RED on assertion | Test review | GREEN commit (test + impl) | Code review / fix commit | Notes |
|---|---|---|---|---|---|
| 1.1/1 | yes (`:795`, header) | yes, 2 fixes (a negative that tells the filtered refusal from the full one; premise asserts) | `390344e` | yes / `7a85e34` | CR mutant (predicate → `false`) killed |
| 1.1/2 | yes (`:619`, header) | yes, no edits; 2 mutants killed | `25a6428` | yes / `a193a89` | GREEN also rewired the `live`-advance arm with no test; CR mutant B survived → list revision `d0e5343` added 1.1/5 |
| 1.1/3 | yes (`:753`, `keeps the repair.`) | yes, `$all`→`$stderr` | `2dd5bc9` | yes / `48999a6` | existing test tightened; CR mutant killed |
| 1.1/4 | yes (`:662`) | yes, 4 strengthenings (header, arm-specific line, joined remedy, repair subject) | `fa823fc` | yes / `bd47643` | CR mutant (bare walk-back with right wording) killed |
| 1.1/5 | **guard** | **none** | `875e9c3` (test only) | n/a | mutant proof by the RED executor itself; independently re-run by the Phase 1 corrector (red at `:798`) |
| 1.2/1 | yes (`:656`) | yes, 3 fixes | `c12acff` | **none** | the Phase 1 corrector found scratch cleanup unobserved after this slice (Major) |
| 1.2/2 | yes (`:693`) | **none** — the orchestrator added the `mktemp-hit` premise (present in `b070dd6`) | `b070dd6` | **none** | |
| 2.1/1 | yes, both variants, on the final `cat-file -e` | yes, 3 Major (never-green hook assertion, errexit-blind setup, inferred preconditions) + 2 minor; a probe proved green for the intended fix | `50405f0` | yes — Major regression, reproduced against `50405f0~1` | CR comment fix superseded by 2.1/2; no fix commit of its own (see Commit discipline) |
| 2.1/2 | yes (`:624`), proven green against pre-change code | yes, Major: a pass-rerun lookalike went green → snapshot pin added, mutant killed | `f04626f` | yes (reviewed the item's net diff) / `3c1339d` | restores the removed retry |
| 2.2/1 | yes (`:690`, wording) | yes, Major: stubbed call not proven to be the pass → push-order pin | `cf4ccde` | yes / `7751eb3` | GREEN also routed the behind retry through the helper, a wording change with no test (CR noted it) |
| 2.2/2 | **guard** | yes, strengthened (offered-sha pin, origin denials); 2 mutants + a pass-disabled mutant | `3ca6ee1` (test only) | n/a | also mutant-proven in the RED report |
| 3.1/1 | yes (`:1361`, `cmp -s`) | yes; probe showed the lazy fix fails the `:1334` sibling | `a631b6e` | yes, 14 edge probes / `7298769` | |
| 3.1/2 | **guard** | yes, 4 fixes; mutants A and C red on `cmp -s`, B red on status only | `4cb36cd` (test + runbook list revision) | n/a | the Phase 3 corrector added a trailer fixture that closes B's byte-level residual |
| 4.1/1 | yes (`:405`); the `-eq 1` tightening already held | yes; ordering glob replaced line arithmetic, both orders probed | `08d4d01` | yes, errexit defect / `366b0ff` | the fix is untestable (fd 2 unwritable); recorded as such |
| 4.1/2 | yes (`:449`/`:457`) | yes, stub pinned to the concrete range, arm denial, 3 state invariants, rerun | `08cc793` | yes / `52305c2` | CR mutant (drop `rm -f`) killed |
| 4.1/3 | yes (`:510`/`:518`) | yes, 4 fixes; 2 test and 8 production mutants | `1e9a6e1` | yes / `0282578` | GREEN commit carries no reports; all four landed in the fix commit |

No slice was born green. Every non-guard slice had a RED.

## RED evidence

- Every non-guard RED names the failing line and assertion text from bats'
  `not ok` block. No RED failed on setup, a missing helper, or a shell error.
- Preconditions sat ahead of the red line in each test. The test reviews moved
  post-conditions above the wording line where RED had left them unexecuted
  (4.1/3 finding 1). Where assertions after the red line stayed unexecuted, they
  validated them by a reverted probe (1.1/2, 4.1/1, 4.1/2).
- Existing-test tightenings (1.1/3, 4.1/1) were red on the new assertion. The
  4.1/1 report states that its `-ne 0 → -eq 1` change held on unchanged code and
  was not the red.
- 2.1/2's red was against the slice 1 commit. The report also shows the test
  passing on `50405f0~1`, as the runbook required.

## Commit discipline

- **Subjects.** Every slice, guard and fix commit carries `Item N.M/k`. Plan
  edits have their own subjects (`d0e5343`, `b7962b3`).
- **Review fixes separate.** They are separate for 1.1/1–4, 2.1/2, 2.2/1, 3.1/1
  and 4.1/1–3. There are three exceptions:
  - **2.1/1**: its code-review report was committed inside the 2.1/2 GREEN
    commit `f04626f`, together with the runbook's slice-2 revision. The review's
    comment fix never landed as written. Slice 2 reverted the shape it
    described, and `f04626f`'s diff shows the pre-review comment as context. So
    one slice commit carries two slices' records and a plan change. The
    substance is sound (the item was re-reviewed whole in 2.1/2's review), but
    the history does not show the 2.1/1 review fix being dropped.
  - **4.1/3**: the GREEN commit `1e9a6e1` holds only the script and the test.
    The RED, test-review and GREEN reports arrived in the fix commit `0282578`.
  - **Runbook edits inside slice or fix commits**: `f04626f` (the 2.1/2 slice),
    `4cb36cd` (the guard marking) and `366b0ff` (ordering prose). Each is a list
    revision tied to that commit, but 1.1's revision got its own commit
    (`d0e5343`) and these did not.
- **Reports edited after commit**: `663068c` reflowed the Phase 1 reports. A
  word-diff sample shows rewrapping only.

## Test integrity

Removed assertion lines across every slice, guard and checkpoint commit that
touched `tests/`:

- **Checkpoints.** `e333de6` replaced three bare `Run /gitlore:merge again.`
  matches with the joined walk-back sentence, and a status-clobbering
  `run ! grep` with `[[ != ]]`. `7639748` folded four copies of the repair-shape
  assertion into `assert_aa_live_repairs`, which is stricter for the two wording
  tests: they gain the bullet count. It also dropped
  `[ "$aa_live" != "$aa_fact" ]`, which the parent check implies.
- **Slice commits.** `08d4d01`'s only removal is `-ne 0`, replaced by `-eq 1`.
- **Conclusion.** None of these weakens a test. GREEN executors report no test
  edits, except 2.1/2, which reworded a comment only.

Mutation proofs:

- **Guards:** 1.1/5 (executor, then re-run by the Phase 1 corrector), 2.2/2 (RED
  plus test review) and 3.1/2 (RED, test review, Phase 3 corrector).
- **Code reviews:** each ran at least one mutant against the committed shape.
- **Phase 5:** mutant-proven work touching tdd tests. Item 5.2 first edited Item
  1.1/1's test by mistake (`6aedc78`) and reverted it in `0bd0c98`. That test's
  span nets to nothing (`item-5-2.md`).

## Green-at-commit

**No slice has an auditable whole-suite green at its own commit.** Every GREEN
report records `scripts/run-bats.sh` over the touched file, and usually its
neighbours. Per-slice breadth varies:

- **1.1/1–4 and 1.2/1–2**: `tests/merge_memory.bats` only, justified by a grep
  for the changed strings. `scripts/lib/resolve.sh` is sourced by far more
  suites than that.
- **2.1/1–2 and 2.2/1**: 9–11 files.
- **3.1/1**: 5 files.
- **4.1/1**: 15 files. **4.1/2**: 9. **4.1/3**: 2 (`resolve_compose`,
  `bsd_portability`), for a change to `scripts/resolve.sh`.
- **Guards and review fixes**: the touched file.
- **Phase 3 checkpoint `ecccc1e`**: a production refactor of
  `gitlore_repair_index`, verified by `index_compose.bats` plus a 22-input
  differential probe. `merge_memory.bats` also exercises the repair and was not
  run there.

The runbook assigns whole-suite runs to the orchestrator at phase boundaries.
The only record of them is handoff prose:

- `663068c`'s handoff says Phase 1 passed `just precommit`;
- `ae91e12`'s says Phases 1–4 each did.

No log or gate sentinel from those runs survives. The current sentinels
(`test-unit` 14:16, `test-integration` 14:17) postdate the last `scripts/` or
`tests/` commit (`81febc1`, 13:57), so the final tree is green. Any individual
slice commit is unverified beyond its file-scoped run.

## Record accuracy

`ae91e12`'s handoff says every Phase 1–4 slice has RED, test review, GREEN and
code review "except where a slice was a guard (1.1/5, 2.2/2, 3.1/2 — each proven
by mutation, each with a test review) or born green". That claim is wrong on
three counts:

- 1.1/5 has no test review;
- 1.2/1 has no code review;
- 1.2/2 has neither.

The earlier `663068c` handoff stated all three correctly. The later summary
compressed them away. The run's closing summary should not inherit the later
wording.

## Process incidents

- **Mutation runs with `$TMPDIR` unset** hit five reviews, in four ways:
  - 2.1/2 code review: an unmutated run read as a mutant result until it was
    noticed;
  - 2.2/2 and 3.1/2 test reviews: mutants stacked, with no backup;
  - 4.1/3 test review: the backup went to `/`;
  - Phase 3 corrector: the backup command aborted.

  Each recovered with `git checkout --`. That was safe only because the
  production file had no uncommitted edits at the time. A code review mutating
  over its own unfixed edits would have lost them.
- **4.1/1 test review** piped a full-file bats run through `tail -30`, against
  the dispatch constraints. The reviewer self-reported it, and the crop was
  lossless.

## Recommendations (priority order)

1. **Give every GREEN and fix commit a whole-suite record, or record the phase
   run as an artifact.** The cheapest fix is at phase boundaries: have the
   orchestrator write the `just precommit` recap line, with the tip sha and the
   gate mtimes, into `reports/phase-N-gate.md` and commit it. Then "green at
   phase boundary" can be audited rather than asserted in a handoff. Per-slice,
   require GREEN reports to list every bats file that sources the changed
   script, not a grep for changed strings.
2. **Do not skip the per-slice reviews for a "small" item.** Item 1.2 is the one
   item run without them, and it is the one that shipped a Major test regression
   to the checkpoint. If the orchestrator substitutes its own check (as for
   1.2/2's stub premise), write it down as a report file so the ledger shows it.
3. **Run a guard's mutation proof in an independent test review**, as the
   runbook specified for 1.1/5. The author proving their own guard is weaker
   evidence, even when a later corrector repeats it.
4. **Replace ad-hoc mutation shells with a script**, for example
   `scripts/mutate-and-run.sh <file> <patch> <bats-file> <filter>`. It should
   refuse when the target has uncommitted edits or the patch applies empty,
   restore by `git stash` or copy, and verify `git diff` is empty afterwards.
   Five reviews worked around an unset `TMPDIR` by hand.
5. **Keep one slice per commit.** The 2.1/1 review report, the 2.1/2 slice and a
   runbook revision should have been three commits. 4.1/3's reports should have
   ridden its GREEN commit. When a review fix is superseded, commit the report
   with a line saying so, so the history shows why the fix never landed.
6. **Add the one routing change no test pins.** 2.2/1's GREEN sent the behind
   arm's retry push through `gitlore_report_tier_push_failure`. A
   non-fast-forward refusal of that retry now gets the divergence wording, and
   no test exercises it. A stubbed second `bb push -q origin live` in the
   behind-arm fixture would pin it. More generally, a GREEN that changes
   behaviour beyond its slice's test (1.1/2's `live`-advance arm, 2.2/1's retry)
   should be flagged in its report so that the code review turns it into a
   slice, as 1.1/2's review did.
7. **Correct the handoff's slice-coverage claim** before the closing summary is
   written from it.
