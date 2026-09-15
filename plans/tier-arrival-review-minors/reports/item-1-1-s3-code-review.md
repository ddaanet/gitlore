# Item 1.1 slice 3 — code review

Commit under review: 2dd5bc9, `scripts/lib/resolve.sh` (with its one test edit
in `tests/merge_memory.bats`).

## Verdict

Conforms to the Walk-back wording change. One Minor comment inconsistency, fixed.
No other defects in scope.

## Checks

1. **Spec conformance.**
   - `gitlore_adopt_walk_back_tier` takes `$6` as `live_holds`, defaulting to
     `what arrived` through `${6:-…}`, so an empty argument also keeps the
     default. The success message reads `its local 'live' keeps <live_holds>.`
     Matches the Interfaces line.
   - `gitlore_adopt_report_refusal_and_walk_back` takes `$6` as remedy and `$7`
     as live_holds, both `${n:-}`, and passes both through. An empty remedy
     reaches the walk-back as empty and its `${5:-…}` keeps the default.
   - The retry-refusal call in `gitlore_adopt_repair_arrival` passes `""` and
     `"the repair"`, as specified.
   - The checkout-follow arm (resolve.sh, `could not follow`) still calls
     `gitlore_adopt_walk_back_tier` with four args. That arm belongs to slice
     1.1/4 and was left alone.

2. **`Args:` comments.** The report helper said "empty keeps the default" for
   both arguments without saying where the default lives. The walk-back helper
   named `"what arrived"` for `$6` but gave no default for `$5`. **Fixed:** the
   walk-back helper now names both defaults (`"Fix the store, …"` and
   `"what arrived"`), since it owns them. The report helper says both arguments
   are optional and passed through to `gitlore_adopt_walk_back_tier`, whose
   default an empty one keeps. That way the default strings are written in one
   place only.

3. **Checkout-failure branch of the walk-back.** It prints `nothing was recorded,
   but <label> could not be returned to the commit the memory store records`,
   then git's error and a manual `git -C … checkout --detach` command. None of
   that says what `live` holds, so it takes no `live_holds`. Left unchanged.
   - Observation (outside this slice's brief, not changed): that branch
     hardcodes `fix the store, then run /gitlore:merge again.` and ignores
     `$remedy`. The transient arms (`Run /gitlore:merge again.`) and the
     unrepairable arm (fix where published) therefore get the fix-the-store
     tail when the walk-back checkout itself fails. This predates Item 1.1. The
     spec names only the success message. It needs a runbook decision before
     anything changes.

4. **Positional shift in other callers.** Every caller is in
   `scripts/lib/resolve.sh`; `grep` over `*.sh`/`*.bats` finds none elsewhere.
   - `gitlore_adopt_walk_back_tier` is called with 4 args (mktemp arm,
     checkout-follow arm) or 5 args (unrepairable arm). None passes a sixth.
   - `gitlore_adopt_report_refusal_and_walk_back` is called with 5 args
     (non-carrier refusal in `gitlore_adopt_tier_into_root`), 6 args
     (no-repair and `live`-advance arms), or 7 args (retry refusal).
   - No call site's arguments change meaning.

5. **Mutant run.** The retry-refusal call was mutated back to five args (no
   remedy, no `the repair`). With
   `scripts/run-bats.sh tests/merge_memory.bats --filter '^a repair beside a root problem lands in live and waits$'`
   the test **redded**: `not ok 1`, line 753,
   `[[ "$stderr" == *"its local 'live' keeps the repair."* ]]` failed. The SUT
   was restored from a saved copy, and `git status` was clean before the fix
   was applied.

## Verification after the fix

- `git diff`: comment lines only, in the two helpers' `Args:` blocks.
- `shellcheck scripts/lib/resolve.sh tests/merge_memory.bats`: clean.
- `scripts/run-bats.sh tests/merge_memory.bats`: 37 passed, 0 failed.

## Refactoring flagged

None.
