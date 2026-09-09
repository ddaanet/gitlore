# Item 1.2 slice 2 — RED

Mode: RED. Two tests added to `tests/commit_memory.bats`; nothing committed.
`scripts/lib/resolve.sh` mutated twice, transiently, and restored both times.

## Both cases are born green

Against the tree as it stands (`719b84d`), both new tests pass:

```
scripts/run-bats.sh --jobs 1 tests/commit_memory.bats
bats: 18 passed, 0 failed
```

`tests/git_hook_pre_commit.bats` (out of scope for edits, checked for fallout)
also stays green: `bats: 18 passed, 0 failed`.

## Test 1 — `a manifest refusal is reported and does not abort the commit`

**Mutation** (the "aborts on every refusal" implementation the runbook names as
slice 1's control): in `scripts/lib/resolve.sh`, the pin guard's

```
if ! pin_problems=$(gitlore_compose_check_pins "$mempath"); then
```

became

```
if ! pin_problems=$(gitlore_compose_check "$mempath"); then
```

**Verbatim failing output**
(`scripts/run-bats.sh --jobs 1 tests/commit_memory.bats tests/git_hook_pre_commit.bats`):

```
not ok 12 a tier moved off its pin aborts the commit
# (in test file tests/commit_memory.bats, line 184)
#   `[ "$status" -ne 0 ]' failed
not ok 13 a manifest refusal is reported and does not abort the commit
# (in test file tests/commit_memory.bats, line 224)
#   `[ "$status" -eq 0 ]' failed
not ok 17 the rc-1 user arm does not tell a user to retry a commit that succeeded
# (in test file tests/commit_memory.bats, line 360)
#   `[ "$status" -eq 0 ]' failed
not ok 32 the parent pre-commit hook aborts on an off-pin tier
# (in test file tests/git_hook_pre_commit.bats, line 241)
#   `[ "$status" -ne 0 ]' failed

bats: 32 passed, 4 failed
```

Target test 13 reds on its own first assertion (`[ "$status" -eq 0 ]`, line
224), as designed — replacing `check_pins` with `check` makes the manifest
refusal (which should proceed) instead fall through with nothing to catch it,
because `gitlore_compose_check` alone doesn't test pins and the manifest listing
`phantom` unmounted is exactly what it *does* catch, so this implementation now
aborts on it too.

**Other tests under this mutation:**
- Slice 2's other new case,
  `a mid-merge tier is reported as a merge, not as a moved pin` (test 14) —
  stayed green. This mutation doesn't touch the ordering it pins.
- Slice 1's two tests, `a tier moved off its pin aborts the commit` (12) and
  `the parent pre-commit hook aborts on an off-pin tier` (32) — both went red as
  collateral fallout: with `check_pins` replaced by `check`, the pin guard no
  longer catches an off-pin tier at all (rule 2's manifest branch is what fires
  instead, on a different fixture — these two tests' fixture has no manifest
  problem), so the guard passes through where it should abort, and
  `gitlore_compose`'s own rc-1 arm then fires later without stopping the commit.
  Expected: this mutation breaks the pin check's *subject*, not just its control
  flow, so slice 1's cases catch it too — confirms the guard still needs
  `check_pins` specifically, which slice 1 already established.
- `the rc-1 user arm does not tell a user to retry a commit that succeeded` (17)
  — also red as fallout, same root cause: its fixture is the manifest induction,
  and under this mutation the (wrongly-substituted) `check` call reads the same
  manifest problem the pin guard now catches unconditionally, aborting before
  the summary is consumed — flipping the exit code this test expects.

**Which assertion of test 13 is proven to execute:** only the first
(`[ "$status" -eq 0 ]`) runs under this mutation — bats stops the test body at
the first failed assertion. The remaining three (`HEAD` advanced, and the three
`$stderr` fragments) are shown to execute against the *unmutated* tree instead:
the full-suite green run above (`18 passed, 0 failed`) only passes if every
assertion in the test body ran and held, since a bats test fails loudly on any
unmet assertion — there is no other way for the test to report `ok`.

**Restore proof:**

```
git diff --exit-code scripts/lib/resolve.sh
RESTORE CLEAN
git hash-object scripts/lib/resolve.sh
320eca29c44c95bab495b08e19cb36d6f75eafda   # matches pre-mutation baseline
```

## Test 2 — `a mid-merge tier is reported as a merge, not as a moved pin`

**Mutation** (slice 1's code review mutation 8): hoisted the pin-guard block
(the `local pin_problems` / `if ! pin_problems=$(gitlore_compose_check_pins …)`
block) above the per-tier `gitlore_guard_stale_merge_state` loop, instead of
after it.

**Verbatim failing output**
(`scripts/run-bats.sh --jobs 1 tests/commit_memory.bats tests/git_hook_pre_commit.bats`):

```
not ok 14 a mid-merge tier is reported as a merge, not as a moved pin
# (in test file tests/commit_memory.bats, line 260)
#   `[[ "$stderr" == *"holds a merge gitlore did not prepare"* ]]' failed

bats: 35 passed, 1 failed
```

Only the target test reds, on its own stderr assertion — test 14's first
assertion (`[ "$status" -ne 0 ]`, the line above 260) held, since the pin guard
still aborts the commit; what fails is which message fired.

**What actually printed**, captured with a throwaway probe driving the same
fixture and echoing `$stderr` to fd 3 (probe file created, run, then deleted —
never left in the tree):

```
gitlore: a tier was moved off the commit the memory store records for it, so the commit was aborted rather than adopt the move:
tier 'ddaanet' is mid-merge and sits off the commit the memory store records for it; run /gitlore:resolve to land the merge before the indexes can be composed
gitlore: composing would have overwritten what that tier holds, and committing would have adopted the move silently. Return the tier to its pin with the command above, or run /gitlore:merge to take its content properly, then retry the commit — the approved summary is still in place.
```

`check_pins`' own mid-merge line
(`is mid-merge and sits off the commit the memory store records for it; run /gitlore:resolve to land the merge before the indexes can be composed`)
fired, wrapped in the pin guard's generic header — never
`gitlore_guard_stale_merge_state`'s orphaned-merge message
(`holds a merge gitlore did not prepare`), because the hoisted guard now runs
before the per-tier stale-merge loop ever sees the tier. The second assertion
(`!= *"moved off the commit the memory store records for it"*`) never executes,
because the first already failed the test — and would also have failed here,
since that phrase *is* present (it's the pin guard's own header, which always
prints when `check_pins` refuses for any reason, mid-merge included).

**Other tests under this mutation:** every other test in both suites stayed
green, including slice 1's two tests and slice 2's other new case (test 13) —
confirms the mutation reds exactly its own case and nothing else.

**Which assertion of test 14 is proven to execute:** the status assertion and
the first stderr assertion both run under this mutation (status passes, first
stderr assertion fails and stops the body there). The second stderr assertion is
shown to execute against the *unmutated* tree: the full-suite green run below
only passes if it ran and held.

**Restore proof:**

```
git diff --exit-code scripts/lib/resolve.sh
RESTORE CLEAN
git status --short
 M tests/commit_memory.bats   # only the test file remains modified
```

## Final state — both tests pass against the unmutated tree

```
scripts/run-bats.sh --jobs 1 tests/commit_memory.bats tests/git_hook_pre_commit.bats
bats: 36 passed, 0 failed
shellcheck -s bash tests/commit_memory.bats
(exit 0, no findings)
```

## Scope

Only `tests/commit_memory.bats` changed (the two new tests, inserted after
`a tier moved off its pin aborts the commit`). `scripts/lib/resolve.sh` carries
no diff. `tests/git_hook_pre_commit.bats` untouched, per instruction — slice 2
is single-entry-point. Slice 3's `the pin-abort user arm tells a user to retry`
was not written.
`the rc-1 user arm does not tell a user to retry a commit that succeeded` was
not touched.

**Note on that test's overlap with the new manifest-refusal case:** both now
share the same induction (tier on its pin, `set_tier_manifest ddaanet phantom`)
— the new test reads it under `CLAUDECODE=1` (agent arm, asserting
`tier composition refused`, the `'phantom'` fragment, and the agent remedy
sentence), the existing one reads it with `CLAUDECODE` unset (user arm,
asserting the `ask it to repair the memory store.` / `…, then retry` contrast).
They pin different arms of the same rc-1 branch off the same fixture, so they do
not duplicate each other's coverage — each would go red on its own message
assertion if the other arm's wording changed. Flagging as instructed; changed
neither.

## Precommit

Not run, per instruction — the orchestrator runs the gate. Nothing committed.
