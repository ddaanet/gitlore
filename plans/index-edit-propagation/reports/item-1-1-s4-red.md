# Item 1.1 slice 4 — RED

Four tests, split as the runbook predicts: two reds proving Major 1's fix is
load-bearing, two characterizations that pass unchanged.

## SUT back-out

Per the dispatch's one deliberate exception to the standing RED contract, the
two `touch "$msgfile"` restamps `62258fa` added (rc-2 arm and the `*)` arm of
`gitlore_sync_memory_to_live` in `scripts/lib/resolve.sh`) are deleted in place;
their comments and everything else in the file are untouched. Exact diff, left
in the tree uncommitted:

```diff
--- a/scripts/lib/resolve.sh
+++ b/scripts/lib/resolve.sh
@@ -954,7 +954,6 @@ gitlore: the commit was aborted so the half-written carrier is not committed. Op
         # lines it approved, never new content. Restamping restores the state
         # this run started from. Reaching here means $fresh was "yes", so the
         # file exists and this cannot create an empty one.
-        touch "$msgfile"
         return 1
         ;;
       *)
@@ -971,7 +970,6 @@ gitlore: the commit was aborted rather than commit a memory store in an unknown
           "$unknown
 gitlore: the commit was aborted rather than commit a memory store in an unknown state. Open this project in Claude Code and ask it to repair the memory store, then retry." >&2
         # Same approval-freshness reason as rc 2 above.
-        touch "$msgfile"
         return 1
         ;;
     esac
```

GREEN restores both lines unchanged and commits them with the tests.

## The four tests and their actual outcome

1. **`an aborted compose keeps the approved summary usable`**
   (`tests/git_hook_pre_commit.bats`) — **FAILS on its assertion**, as required.
   Two tiers (`alpha`, `beta`) via `set_tier_manifest alpha beta`; established
   from a run (not assumed) that `gitlore_active_tiers` walks the manifest in
   order and `gitlore_compose` composes in that same order, so `beta` is the
   tier that composes second — `chmod a-w memory/beta` lets `alpha`'s write land
   (staling the tree) before `beta`'s write fails, giving `gitlore_compose` rc
   2. `sleep 1` after writing the summary, before the induction, per the
   second-granularity mtime rule. First run: non-zero, msgfile still present
   (passes even backed out — slice 3's own assertion). Second run, no new
   summary: expected exit 0 and `HEAD` advanced; got exit 0 assertion failing.
   Bats output:
   ```
   not ok 33 an aborted compose keeps the approved summary usable
   # (in test file tests/git_hook_pre_commit.bats, line 371)
   #   `[ "$status" -eq 0 ]' failed
   ```
   (Backed out, the second run's freshness check reads the restamped `beta`
   carrier as newer than the never-rewritten summary and refuses the commit as
   if it were still dirty-and-unapproved.)

2. **`an unrecognised compose status aborts and keeps the approval`**
   (`tests/commit_memory.bats`) — **FAILS on its assertion**, as required. A
   driver script under `$BATS_TEST_TMPDIR` sources `util.sh`, `log.sh`,
   `resolve.sh` in that order (`gitlore_sync_memory_to_live`'s own header names
   it), redefines `gitlore_compose` afterward to print a problem line,
   `touch memory/MEMORY.md`, and `return 7`, then calls
   `gitlore_sync_memory_to_live memory` directly. Fixture: memory dirty (one
   uncommitted local fact), fresh approved summary, no tier. Non-zero exit and
   unchanged `HEAD` both hold; the freshness assertion — this test's "half of
   the red" per the dispatch — fails:
   ```
   not ok 14 an unrecognised compose status aborts and keeps the approval
   # (in test file tests/commit_memory.bats, line 251)
   #   `[ "$(gitlore_commit_msg_freshness memory)" = "yes" ]' failed
   ```

3. **`the rc-1 user arm does not tell a user to retry a commit that succeeded`**
   (`tests/commit_memory.bats`) — **PASSES**, as predicted (characterization;
   the pinned text is already correct). Slice 3's off-pin induction verbatim,
   with an explicit `unset CLAUDECODE` before `run` — needed because this
   agent's own shell has `CLAUDECODE=1` in its ambient environment, which bats
   inherits unless cleared; a bare bats run leaves it unset, but relying on that
   here would make the test's outcome depend on who invokes it. Confirmed by
   first running without the `unset`: the run picked the agent arm and both text
   assertions failed. With `unset CLAUDECODE`: exit 0, `HEAD` advanced,
   `$stderr` carries `ask it to repair the memory store.` and not
   `repair the memory store, then retry`.
   ```
   ok 1 the rc-1 user arm does not tell a user to retry a commit that succeeded
   ```

4. **`the rc-2 user arm tells a user to retry`** (`tests/commit_memory.bats`) —
   **PASSES**, as predicted. Slice 3's write-failure induction verbatim
   (`chmod a-w memory/ddaanet`, `id -u` root skip, `chmod u+w` restore
   immediately after `run`), same explicit `unset CLAUDECODE`, own fixture
   rather than appended to test 3 (bats body runs under errexit). Non-zero exit,
   `$stderr` carries `ask it to repair the memory store, then retry.`.
   ```
   ok 1 the rc-2 user arm tells a user to retry
   ```

No test errored (missing helper / bad fixture) — every outcome above is the
assertion the induction was built to hit.

## Full suite run

`scripts/run-bats.sh tests/commit_memory.bats tests/git_hook_pre_commit.bats`:

```
not ok 14 an unrecognised compose status aborts and keeps the approval
# (in test file tests/commit_memory.bats, line 251)
#   `[ "$(gitlore_commit_msg_freshness memory)" = "yes" ]' failed
not ok 33 an aborted compose keeps the approved summary usable
# (in test file tests/git_hook_pre_commit.bats, line 371)
#   `[ "$status" -eq 0 ]' failed

bats: 31 passed, 2 failed
```

31 passed / 2 failed out of 33 total = exactly the pre-existing suites (29 green
per slice 3's own record) plus this slice's 4 new tests split 2 red / 2 green.
No other test regressed.

## Scope

Changed: `tests/commit_memory.bats`, `tests/git_hook_pre_commit.bats`,
`scripts/lib/resolve.sh` (two-line back-out only, per the dispatch's exception).
Nothing else touched. No commit, no staging — `scripts/lib/resolve.sh` is left
backed out for GREEN to restore.
