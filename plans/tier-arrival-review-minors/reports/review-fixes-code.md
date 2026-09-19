# Deliverable review minors: code and test fixes

Findings 2-5 of `deliverable-review.md`'s "Minor Findings → Code / Tests" section.

## A — unreachable arm removed (`scripts/lib/resolve.sh` post-loop publication pass)

Dropped the `origin_live=$(git -C "$tierpath" rev-parse -q --verify refs/remotes/origin/live) || origin_live=""` read, the `[ -z "$origin_live" ] ||` disjunct, and the two-line comment explaining it. The condition now reads exactly like the behind arm's retry: `if ! git -C "$tierpath" merge-base --is-ancestor live origin/live; then`. Removed `origin_live` from `gitlore_push_stores`'s `local` list — nothing else in the function used it. Both `continue`/error-return skips are unchanged.

## B — one printer for the root-index refusal

Extracted `gitlore_adopt_print_root_refusal <label> <lines>` (prints the `gitlore: the root index could not take <label>'s lines:` header plus each line prefixed `gitlore:   `, all to stderr). Defined it after both its callers — `gitlore_adopt_repair_arrival`'s unrepairable arm (for `$other_lines`) and `gitlore_adopt_report_refusal_and_walk_back` (for `$composed`) — placed between the latter and `gitlore_adopt_walk_back_tier`, matching the file's "definitions after their users" convention. Both call sites now call the helper; output is byte-identical (same `printf`/`sed` pipeline, just factored out).

## C — behind arm's retry wording: already covered, verified non-vacuous

`tests/push_behind_vs_diverged.bats` already contains, at HEAD (added in commit `eabe091`, ahead of my dispatch), the test `"a behind arm's retry push refused as a non-fast-forward is worded as a moved remote, not as a non-divergence failure"`. It matches every requirement in the dispatch: single tier (`ddaanet`) behind its remote with a duplicate-bullet arrival, a `git` stub (counting matches in a file under `$BATS_TEST_TMPDIR`) that lets the first push (the real refusal) through and fails the *second* push naming the tier — the retry after the take — with `! [rejected] live -> live (non-fast-forward)` and exit 1; asserts `status -eq 1`, the push-counter premise (`"ddaanet ddaanet "`), `"The remote moved during the push"` present, and `"not because of divergence"` absent. No new test was added — adding a duplicate would have been redundant with an existing, correctly-scoped guard.

Proved it is not vacuous with `scripts/mutate-and-run.sh`. Because `scripts/lib/resolve.sh` was already dirty from A/B, I stashed my working copy aside, `git checkout --`ed the file back to HEAD (mutation target and my A/B edits sit in disjoint regions of the file, so this doesn't affect the mutation's validity), ran the mutant, then restored my working copy on top.

Mutation (sed, line 1472 of the HEAD blob — the retry's failure branch inside the behind arm):
```
1472s#gitlore_report_tier_push_failure "$tier" "$tier_err"#printf "gitlore: pushing tier %s failed, and not because of divergence. git said:\n%s\n" "$tier" "$tier_err" >\&2#
```
i.e. the retry's failure branch prints the old fixed "not because of divergence" message directly instead of calling `gitlore_report_tier_push_failure` (which would word it as a moved remote).

Result: **KILLED**. Failing assertion:
```
not ok 1 a behind arm's retry push refused as a non-fast-forward is worded as a moved remote, not as a non-divergence failure
# (in test file tests/push_behind_vs_diverged.bats, line 454)
#   `[[ "$output$stderr" == *"pushing tier 'ddaanet' was refused as a non-fast-forward"* ]]' failed
```

## D — `tests/merge_memory.bats:1025` fixed

Replaced the mid-test `run ! grep -Eq '^gitlore:   .*ddaanet/MEMORY\.md: ' <<<"$stderr"` (which clobbers `$stderr`/`$output`/`$status` via `run`, with eight more assertions still to run against them) with the suite's own non-`run` negative-assertion idiom, matching lines 855 and 858 in the same file:
```
! grep -Eq '^gitlore:   .*ddaanet/MEMORY\.md: ' <<<"$stderr" || false
```
This does not go through `run`, so `$stderr`/`$output` stay intact for the assertions that follow.

## Verify

- `shellcheck -x scripts/lib/resolve.sh tests/push_behind_vs_diverged.bats tests/merge_memory.bats` — clean, exit 0.
- `scripts/run-bats.sh tests/push_behind_vs_diverged.bats` → **21 passed, 0 failed**.
- `scripts/run-bats.sh tests/merge_memory.bats` → **42 passed, 0 failed**.
- `git status --short -- scripts tests` → only `scripts/lib/resolve.sh` and `tests/merge_memory.bats` show as modified; `tests/push_behind_vs_diverged.bats` is unchanged (item C needed no new test).

## Not done / notes

Nothing left undone. Item C required no code or test change beyond verification — the guard test the dispatch describes was already present and demonstrably discriminates the retry's wording.
