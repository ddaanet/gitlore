# Item 2.2 / slice 1 — test review

Test: `tests/push_behind_vs_diverged.bats`, last test, renamed to "a post-loop
publication push refused as a non-fast-forward is worded as a moved remote, not
as a non-divergence failure". Fixes applied in place. Nothing committed.

## Findings and fixes

1. **Major: the test could not show that call 2 is the pass's push.** The stub
   only counted `aa` pushes. The RED report's trace is also partly wrong. It
   says `aa`'s `origin/live` was still stale at P when the pass ran. In fact the
   mid-loop take fetches `aa`, so `origin/live` is D. The pass pushes because R
   (whose parent is D) is not an ancestor of D, not because the tracking ref is
   stale. Its conclusion holds anyway, and I checked it independently. Only
   three places push `-q origin live` to a tier: `resolve.sh` :1378 (the loop),
   :1406 (the behind arm's retry) and :1466 (the pass). The take itself only
   pushes to `.`. The retry pushes `$tierpath`, which is `bb` at that point.
   `aa`'s loop push runs in `aa`'s own iteration, before `bb`'s. `gitlore_git`
   retries only on lock errors, and the stub's message is not one. **Fix:** the
   stub now writes one line to `$BATS_TEST_TMPDIR/tier-pushes` for each
   `aa`/`bb` push, and the test asserts the order `aa bb aa`. That rules out
   `aa`'s own iteration and any retry of it. The test also asserts that `bb`
   took its fact (the take ran before the failure) and that `aa`'s remote `live`
   is still D (the repair was never published). The comment now gives this
   argument instead of the inaccurate trace.
2. **Minor: the stub's pattern was loose.** `*"aa push -q origin live"*` also
   matches paths like `.../xaa` and pushes with extra arguments. **Fix:** it is
   now anchored as `*"/aa push -q origin live ")`, the pattern "ending"
   requires.
3. **Minor: the name was misleading.** "not by policy" suggested a policy
   refusal, which is slice 2's case. The negative assertion is really about the
   "not because of divergence" wording. **Fix:** renamed as above.
4. **Minor: the counter file became a log.** The count is now `grep -c '^aa$'`
   on the log, not `wc -c`. It works the same on bash 3.2 and BSD.
5. **Minor: the rejection line lacked git's leading space.** The stub now prints
   ` ! [rejected] ...`, as git does. This is cosmetic, because the match is on
   `(non-fast-forward)`.

Hygiene checks passed: `case " $* "`, `exec` of the real git, `PATH` set only
for `run`, state kept under `$BATS_TEST_TMPDIR`, quoting correct. Comments
contain no line numbers or plan ids. `shellcheck` is clean.

## Checks

1. **Mechanical:** `scripts/run-bats.sh tests/push_behind_vs_diverged.bats`
   passes 18 and fails 1. The new test fails on an assertion, at line 692:
   `[[ "$output$stderr" == *"The remote moved during the push"* ]]`.
2. **Right reason:** the assertions before the wording all pass on current code:
   status 1, push order `aa bb aa`, `bb` took its fact, `aa`'s `live` is the
   repair with parent D, and `aa`'s remote is still at D.
3. **The stubbed call is in the pass:** pinned by the push order and the
   argument in finding 1.
4. **The negative assertion can fail:** in a scratch copy with the positive
   assertion removed, current code fails at
   `[[ "$output$stderr" != *"not because of divergence"* ]]`. The pass currently
   emits that wording.
5. **Only the intended fix turns it green** (scratch copy under `/tmp/claude/`,
   since `$TMPDIR` was unset; removed afterwards):
   - Adding `gitlore_report_tier_push_failure <tier> <git_stderr>`, which picks
     the wording by `(fetch first)`/`(non-fast-forward)`, and calling it from
     only the outer `*)` arm leaves the test red on the positive wording
     assertion.
   - Also calling it from the pass turns it green without editing the test. The
     whole file then passes 19 of 19.
6. **Name and hygiene:** fixed as above.

Nothing is UNFIXABLE.
