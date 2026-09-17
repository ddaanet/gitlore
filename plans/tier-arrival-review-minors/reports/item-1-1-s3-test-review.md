# Item 1.1 slice 3 — test review

Test: `a repair beside a root problem lands in live and waits`
(`tests/merge_memory.bats`), the two assertions added after the
`repaired ddaanet's arrival` check.

## Verdict

Sound after one fix. Still red on an assertion; shellcheck clean.

## Checks

1. **Mechanical.** Re-run with
   `scripts/run-bats.sh tests/merge_memory.bats --filter '^a repair beside a root problem lands in live and waits$'`:
   `not ok`, failing at line 753 on the positive `[[ … keeps the repair. … ]]`
   assertion. It is an assertion failure, not an ERROR.

2. **Wrong-reason hunting.**
   - **Stream (fixed).** Both assertions matched `$all` (stdout+stderr), and the
     runbook says stderr. `gitlore_adopt_walk_back_tier` prints its message with
     `>&2`. The test runs `run --separate-stderr`, so `$stderr` is available and
     still intact at these lines, which come before any later `run`. Both
     assertions now match `$stderr`. The negative's here-string is expanded
     before `run !` executes, so overwriting `$output`/`$stderr` does not affect
     it. Neither phrase has a legitimate stdout source (the stdout
     `repair is committed in its local 'live'` line does not match), so this
     tightens the test rather than fixing a false pass.
   - **Right walk-back.** In `gitlore_adopt_repair_arrival`, the only walk-back
     reachable after the stdout `gitlore: repaired <tier>'s arrival:` lines is
     the retry-refusal call (`retry_rc -ne 0` →
     `gitlore_adopt_report_refusal_and_walk_back … "$retry_composed"`). The
     build, advance and checkout-follow arms all return before those lines are
     printed. The test already asserts the
     `repaired … dropped a duplicate pointer line` line and the `gone/x.md` root
     problem, so this fixture reaches the retry refusal and no other walk-back.
   - **Negative is effective.** Probe: with the positive assertion deleted
     temporarily, the test failed at
     `run ! grep -qF 'keeps what arrived' <<<"$stderr"` with "expected nonzero
     exit code". The current code prints `keeps what arrived`, and the negative
     catches it. File restored afterwards.
   - **Satisfiable.** Probe: with a temporary mutant of `resolve.sh` whose
     walk-back prints `keeps the repair.`, the whole test passed (1 passed). So
     no other assertion in the test conflicts with the target wording.
     `resolve.sh` restored; `git status` shows only the expected files.

3. **Fixes applied.** `$all` → `$stderr` in both new assertions. Re-run: red at
   line 753 on the positive assertion. `shellcheck tests/merge_memory.bats`:
   clean.

## Not in scope, noted

The global-wording mutant also passes this test. The test cannot tell a
retry-refusal-specific `the repair` argument from a changed default. Slice 1.1/4
(checkout follow) asserts `keeps the repair.` too, so it does not cover this
either. A changed default is caught by the unrepairable-arm test, which asserts
`its local 'live' keeps what arrived. Once the index is fixed …` at
`tests/merge_memory.bats:804`. Between that test and this one, the two wordings
are pinned per arm.
