# Item 2.2 / slice 2 — test review

Test: `tests/push_behind_vs_diverged.bats`, last test, "a post-loop publication
push refused by policy is worded as a non-divergence failure, not as a moved
remote". The helper is renamed to `decline_tier_pushes_after_first`. Fixes are
applied in place. Nothing is committed.

## Findings and fixes

1. **Major: the "between" pin was weaker than slice 2.2/1's.** A ledger reading
   `aa aa ` only counts pushes. It does not say which commit the second push
   offered, and "`bb` took its fact" only shows that the take ran at some point.
   The report's reasoning is correct, and I checked it against
   `gitlore_push_stores`:
   - `bb` fetches `origin/live` before its push, so git's client refuses the
     non-fast-forward before any pack is sent, and `bb`'s `pre-receive` never
     runs.
   - The retry in the behind arm pushes `$tierpath`, which is `bb`, and is
     skipped once the take fast-forwards `bb`.
   - The ahead-of-HEAD arm is a take, not a push.
   - `gitlore_git` retries only on lock errors, and `aa`'s first push is
     accepted anyway.

   So the test was not wrong, but its pin rested on that argument rather than on
   something it observed. **Fix:** the hook now reads `old new ref` from stdin
   and logs the sha offered for `refs/heads/live`. The test asserts that the
   ledger reads `$P $aa_live `: the declined push offers the repair commit,
   which does not exist until `bb`'s take creates it. This is stronger than
   slice 1's order pin. The comment now states this argument.
2. **Minor: the refusal's origin was only half-asserted.** **Fix:** added
   negative assertions that stderr contains neither `(non-fast-forward)` nor
   `(fetch first)`. `bb`'s own client-side refusal is captured in `tier_err` and
   never printed, so these hold on the current code.
3. **Minor: the name and doc were inaccurate.** "second push" together with
   "shared ledger … tier name" did not fit a helper that declines every push
   after the first and that only one tier writes to. **Fix:** renamed the
   helper, rewrote the doc with an `Args:` line as its siblings have, and
   renamed the file to `$BATS_TEST_TMPDIR/aa-pushed`.
4. **Hygiene, no change needed.**
   - **Counter:** it lives under `$BATS_TEST_TMPDIR`, and the count uses
     `grep -c ""`. I avoided `wc -l`, whose output BSD pads with spaces.
   - **Quarantine:** the hook runs no git command, so it does not need to unset
     the quarantine variables.
   - **Merging with `decline_tier_pushes_recording`:** not done. That helper
     takes a snapshot of another tier's remote and declines every push. This one
     counts and accepts the first. A merged helper would need mode flags and
     would be less clear.
   - **`case " $* "`:** does not apply, because there is no stub.
   - **Comments:** no line numbers or plan ids.
   - **Shellcheck:** clean.

## Checks

1. **Guard holds:** `scripts/run-bats.sh tests/push_behind_vs_diverged.bats`
   gives 20 passed, 0 failed, after the fixes.
2. **The refused push is the pass's:** pinned by the offered sha (finding 1).
   **Mutant: post-loop pass disabled** (`if false; then … fi` around it). The
   test fails on the precondition `[ "$status" -eq 1 ]`, at line 736. It does
   not pass vacuously.
3. **Teeth:**
   - **Mutant 1** (the helper's divergence pattern replaced by `*)`): fails at
     line 744, the positive `not because of divergence` assertion.
   - **Mutant 2** (the pass bypasses the helper and `echo`es the divergence
     wording directly): fails at line 744.

   Every precondition passes under both mutants. The first mutation attempt
   stacked mutants 1 and 2, because `$TMPDIR` was unset in that shell and the
   backup `cp` failed. I restored with `git checkout scripts/lib/resolve.sh`,
   which had no uncommitted changes, and re-ran mutants 2 and 3 in isolation.
   The results above come from the isolated runs. `git diff --stat scripts` is
   empty after the restore.
4. **The refusal is the hook's:** the test asserts that `declined by policy` is
   relayed, and that `(non-fast-forward)` and `(fetch first)` are absent.
5. **Hygiene:** see finding 4.

Nothing is UNFIXABLE.
