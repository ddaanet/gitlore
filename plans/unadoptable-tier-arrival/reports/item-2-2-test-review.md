# Review: Item 2.2 tests (RED), `tests/merge_memory.bats`

**Scope**: the seven uncommitted Item 2.2 tests, the suite-local
`push_tier_files` helper, and `reports/item-2-2-red.md`. `scripts/` stays
unmodified (`git diff --quiet HEAD -- scripts` holds). **Date**: 2026-09-15
**Mode**: review + fix (test review)

## Summary

The RED run was genuine: all seven tests failed on assertions, and the 23
existing tests passed. The tests were weaker than the runbook in four places,
though. The parent assertion in slices 2–6 read only the first parent, so a
merge would pass. Slice 5 used its own fixture instead of the runbook's, and
nothing proved it reached `gitlore_adopt_advanced_live`. Slice 6 had no check
that the lock bit at R's push rather than earlier. And R's carrier was checked
through the worktree instead of R's own blob. All of these are fixed. The tests
still fail only on their behavioural assertions.

**Overall Assessment**: Ready

## Mechanical check

Before the fixes: `scripts/run-bats.sh tests/merge_memory.bats` gave 23 passed
and 7 failed, all seven on assertions (lines 570, 599, 647, 674, 710, 739, 773).
None errored.

After the fixes: 23 passed and 7 failed, still all on assertions. Every premise
passes, and each test goes red on the first assertion that only the new
behaviour satisfies:

| # | Test | Red on |
|---|---|---|
| 24 | duplicate pointer arrived | `status -eq 0` (573) |
| 25 | welded line arrived | `status -eq 0` (618) |
| 26 | interleaved line arrived | `status -eq 0` (666) |
| 27 | repair beside a root problem | `repaired ddaanet's arrival: dropped …` (694) |
| 28 | unrepairable arrival | the unrepairable sentence (740) |
| 29 | local live ran ahead | `status -eq 0` (771) |
| 30 | refused live update | `live.lock` (812); the adoption-reached assertion before it passes |

`shellcheck tests/merge_memory.bats` exits 0.

## Issues Found

### Critical Issues

None.

### Major Issues

1. **The parent check cannot tell a commit on top from a merge (slices 2–6)**
   - Location: every `rev-list --parents -n 1 "$R" | awk '{print $2}'`
   - Problem: `$2` is only the first parent. A `--no-ff` merge whose first
     parent is the arrival passes. Slice 1 counted words, but the other tests
     did not.
   - Fix: every test asserts the whole line, `"$R $remote_sha"` or
     `"$R $stranded"`, which pins exactly one parent and says which one.
   - **Status**: FIXED

2. **Slice 5/6 fixture diverged from the runbook, and the reach was not proven**
   - Location: "a local live that ran ahead…" and "a refused live update…"
   - Problem: both tests copied `strand_live_ahead_of_pin` by hand with an
     `- [A](a.md) — x` pair. The runbook's fixture works as written:
     `seed_tier_bullet ddaanet local.md "committed here, never recorded"` right
     before `strand_live_ahead_of_pin ddaanet`, whose own `seed_tier_bullet`
     appends the same line again, so the stranded commit carries an identical
     duplicate. Nothing showed the take went through
     `gitlore_adopt_advanced_live`.
   - Fix: both tests now use the runbook fixture, with a premise that the
     stranded commit carries the bullet exactly twice (`grep -cx` = 2). Slice 5
     asserts the adoption message with the stranded commit's short sha
     (`adopted them at <short>.`), and that memory records R with root carrying
     the line once. Slice 6 asserts the same message, without the sha. The
     report lines now name
     `- [local](local.md) — committed here, never recorded`.
   - **Status**: FIXED

3. **Slice 6's `live.lock` could come from a lock hit before the repair**
   - Location: "a refused live update after the repair leaves no trace"
   - Problem: `live.lock` in the output only proves some update of `live` was
     refused. Suppose an implementation touched `live` earlier, for example with
     a fetch into `live:live`. Then HEAD on the pin, `live` on the stranded
     commit and no repair subject would all hold without a repair ever being
     built.
   - Fix: the test now asserts the adoption message. That message prints after
     `checkout --detach live`, and in the flow the only `live` update after it
     is R's push. The test also asserts no `repaired ddaanet's arrival:` line on
     the refused take (report lines print only once R is in `live`). That
     negative is paired with the positive on the second take, which now asserts
     the report line and that memory records R. A premise confirms
     `refs/heads/live` is a loose ref, so the lock file actually contends. The
     lock path is resolved with `rev-parse --absolute-git-dir`, which gives
     `memory/.git/modules/…`.
   - **Status**: FIXED

4. **Repair written to the worktree and committed would pass the failure paths**
   - Location: slices 4 and 6, the `log --all --format=%s` check
   - Problem: `--all` walks refs only. An implementation that commits the repair
     on a detached HEAD and then walks back leaves R reachable only from HEAD's
     reflog. That passes both `log --all` and the empty-porcelain check. Slice 4
     had no subject check at all.
   - Fix: both tests run
     `run ! grep -qxF '<repair subject>' < <(git … log --all --reflog --format=%s)`,
     an exact-line match. A probe confirmed this shape fails when the subject is
     present (`tier fact` was found).
   - **Status**: FIXED

5. **Nothing checked for leftover scratch files or a temporary index**
   - Location: slices 1, 4 and 6
   - Problem: the runbook says scratch files and the temporary index are removed
     on every path. No test checked it.
   - Fix: a new suite-local `tier_gitdir_files` helper lists every file under
     the tier's gitdir outside `objects/`, `logs/`, `refs/`, `FETCH_HEAD` and
     `ORIG_HEAD`. The listing is compared before and after the take on the
     success path (1), the unrepairable path (4) and the refused-update path
     (6). A probe against today's code confirmed the listing is unchanged by
     both a walk-back take and a remote fast-forward take, so the comparison
     starts green and flags only new leftovers.
   - **Status**: FIXED

6. **Slice 1 checked R's carrier through the worktree**
   - Location:
     `[ -z "$(gitlore_compose_check_index memory/ddaanet/MEMORY.md)" ]`
   - Problem: the runbook asks that R's carrier pass the check. The worktree
     copy is not R's blob. The pair was also not proven committed.
   - Fix: the test writes `git show "$R:MEMORY.md"` to a file and checks that. A
     positive control confirms the check refuses the arrival's own carrier, so
     an empty result means something. The test also asserts empty porcelain in
     both the tier and memory.
   - **Status**: FIXED

### Minor Issues

1. **Slice 4 could not show why the two numberings differ**
   - Location: "an arrival the repair cannot fix…"
   - Note: the fixture already puts the identical duplicate above the weld
     (lines 6–7, weld at 8, and 7 in the repaired copy), so the numbering
     assertion could tell the two apart. Nothing said so, and
     `[ ! -e memory/ddaanet/z.md ]` checked the worktree at the pin, not the
     arrival.
   - Fix: premises now show the first duplicate's line number is below the
     weld's, and that `$remote_sha:z.md` is absent (`cat-file -e`). The weld
     line is found with an exact `grep -nxF`. A negative `line $((n-1)) welds`
     sits beside the positive.
   - **Status**: FIXED

2. **Slice 3 was loose in three places**
   - Note: the report-line assertion stopped at `repaired ddaanet's arrival:`.
     The root premise read the worktree, not HEAD. The second take did not check
     the tier HEAD. The `rev-list --count` also re-read `live` instead of
     pinning it to R.
   - Fix: the test asserts the full dropped-line report and reads root through
     `git show HEAD:MEMORY.md`. It adds empty tier porcelain on the resting
     path. The second take asserts `live` = R, HEAD = R, and
     `rev-list --count "$remote_sha..live"` = 1.
   - **Status**: FIXED

3. **Weld and interleaved tests never checked R's blob**
   - Fix: the weld test asserts R's last two carrier lines are the split pair,
     byte for byte. The interleaved test asserts R's last three lines are A, B,
     then the stray line. The interleaved test also gains the subject assertion.
     The weld premise uses an exact-line count instead of a substring.
   - **Status**: FIXED

4. **Unused `gitlink` and a wrong helper comment**
   - Note: `gitlink` was assigned and never read in the first three tests.
     `push_tier_files`'s comment said `push_tier_fact` "carries one bare line",
     but it appends several lines when given a multi-line argument, which these
     tests rely on.
   - Fix: removed the unused assignments and reworded the comment, with an
     `Args:` line.
   - **Status**: FIXED

## Wrong-reason hunting (dispatch check 3)

| Wrong implementation | Caught by |
|---|---|
| merges instead of committing on top | exact `rev-list --parents -n 1` = `"$R <arrival>"` (all six slices) |
| writes the repair to the worktree, commits, walks back | `log --all --reflog` subject negative, empty porcelain, gitdir listing (4, 6) |
| pushes R to the tier remote | slice 1: the bare remote's `live` is still the arrival |
| prints the first refusal's problem list | slice 3: no `duplicate pointer path`, paired with the dropped-line positive |
| numbers the unrepairable report from the repaired copy | slice 4: `line 8` positive, `line 7` negative, duplicate proven above the weld |
| lock hit before R's push | slice 6: the adoption message and no report line on the refused take |
| second take repairs again | slice 3: `--count` = 1, `live` = R, no `repaired` line |

**`$output$stderr` joining.** bats strips `$output`'s trailing newline, so the
concatenation welds stdout's last line onto stderr's first. Every substring
assertion here matches text inside one line: a `gitlore:`-initial report line, a
path, `live.lock`, `line <n> welds`, or the adoption message that ends in
`<short>.`. None spans the join, and no negative can be satisfied or broken by
it. The suite's existing `$output$stderr` idiom is kept.

## Fixes Applied

- `tests/merge_memory.bats`: all seven Item 2.2 tests revised as described
  above.
- `tests/merge_memory.bats`: new suite-local `tier_gitdir_files` helper, placed
  after its first user.
- `tests/merge_memory.bats`: `push_tier_files` comment corrected. The helper's
  body is unchanged.

## Positive Observations

- The RED report's premises check the bare remote, not the local clone, so the
  fixture was proven before the take.
- `GITLORE_GIT_RETRY_SCHEDULE=0` is exported before the lock is created, and the
  lock is removed immediately after `run`, before any assertion can abort.
- The slice 3 negative already used `run ! grep` rather than a bare `!`.
