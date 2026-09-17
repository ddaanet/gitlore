# Item 1.1 slice 4 — code review

Commit under review: fa823fc. The review covers `gitlore_adopt_repair_arrival`
and its two walk-back helpers in `scripts/lib/resolve.sh`, as they stand after
slices 1–4.

## Verdict

Item 1.1's Changes and Interfaces are implemented. One Minor defect: the repair
function's header comment went stale over slices 2–4. It is fixed. No code
defects in scope.

## Checks

1. **Full refusal passed through.** `gitlore_adopt_tier_into_root` passes
   `"$composed"` as the seventh argument.
2. **Unrepairable arm.**
   - The `live:MEMORY.md:` lines keep their header.
   - The other lines are the lines of `$composed` that
     `gitlore_compose_problems_in "$tierpath/MEMORY.md"` does not select. They
     print under `the root index could not take tier '<t>''s lines:`, each with
     a `gitlore:   ` prefix.
   - The two-fix remedy string matches the runbook byte for byte. With no other
     lines, the remedy is unchanged.
   - This arm still calls `gitlore_adopt_walk_back_tier` directly. It is not a
     transient arm, so that is correct.
3. **Transient arms.**
   - Arrival read, pin read, rewrite and commit build each print their own
     `could not …` line. They then reach the shared `[ -z "$repair" ]` call to
     `gitlore_adopt_report_refusal_and_walk_back … "$composed" "Run /gitlore:merge again."`.
   - The `live` advance and checkout follow arms each print their own line, then
     make the same call.
   - The checkout follow arm also passes `"the repair"`.
   - The `mktemp` arm still makes a bare walk-back. That is Item 1.2's, and out
     of scope.
4. **Walk-back wording.**
   - `gitlore_adopt_walk_back_tier` takes `[<remedy>] [<live_holds>]`, with the
     defaults `Fix the store, …` and `what arrived`, both through `${n:-}`.
   - The report helper takes `<composed> [<remedy>] [<live_holds>]` and passes
     both through.
   - The retry refusal passes `"" "the repair"`.
   - Every other caller omits `live_holds`. In each of those arms `live` still
     holds the arrival: the advance either failed or was never reached.
5. **Interfaces.** The argument order matches all three signatures. Return
   codes:
   - `gitlore_adopt_repair_arrival` returns 1 on every walk-back. On adoption it
     returns `gitlore_adopt_stage_pair_and_commit`'s status, which is
     best-effort 0 by design (`gitlore_commit_tier_bookkeeping`).
   - Both helpers return 1.
6. **Header wording for the checkout follow arm.** The arm prints the first
   refusal under `the root index could not take tier '<t>''s lines:`. That stays
   true: those problems are what the root index refused from the arrival. The
   walk-back line that follows says `live` keeps the repair, and the next take
   adopts the repair through `gitlore_adopt_advanced_live`, so
   `Run /gitlore:merge again.` holds. The reader does see carrier problems that
   `live` has already fixed. That is the spec's choice, and the wording does not
   contradict it.
7. **Whitespace.** `$tierpath` is matched through a quoted `case` prefix in
   `gitlore_compose_problems_in`. No word splitting on paths.

## Mutant

In the checkout follow arm, the call was replaced by
`gitlore_adopt_walk_back_tier … "Run /gitlore:merge again." "the repair"`. This
mutant has the right walk-back wording but prints no refusal.
- Command:
  `scripts/run-bats.sh tests/merge_memory.bats --filter 'checkout follow fails'`
- Result: `not ok 1`, line 664. The refusal-header assertion failed.
- The SUT was restored from `HEAD`.
  `git status --porcelain scripts/lib/resolve.sh` was empty afterwards.

## Fix applied

The `gitlore_adopt_repair_arrival` header comment:
- **`$7`** said the full text was passed "for the problems it raised beyond the
  carrier". Since slice 2 the transient arms print it whole. It now reads:
  printed whole when the repair fails on something the next take redoes, and for
  its problems beyond the carrier when the repair cannot fix it.
- **Returns** listed every walk-back cause except the checkout follow. Added:
  "the worktree cannot follow it".

The `Args:` blocks of the two helpers are accurate as they stand. Nothing else
changed.

## Verification

- `git diff`: the comment lines above only.
- `shellcheck scripts/lib/resolve.sh tests/merge_memory.bats`: clean.
- `scripts/run-bats.sh tests/merge_memory.bats`: 38 passed, 0 failed.
- Nothing committed.

## Refactoring flagged

None.
