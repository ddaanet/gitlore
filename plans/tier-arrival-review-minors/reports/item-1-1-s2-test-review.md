# Item 1.1 / slice 2 — test review

**Test:** `a repair whose commit build fails walks back and points upstream`
(`tests/merge_memory.bats:594-623`). **Verdict:** approved, no edits.

## 1. Mechanical

`scripts/run-bats.sh tests/merge_memory.bats --filter "commit build fails walks back and points upstream"`
fails on an assertion, not in setup:

```
not ok 1 a repair whose commit build fails walks back and points upstream
# (in test file tests/merge_memory.bats, line 619)
#   `[[ "$stderr" == *"gitlore: the root index could not take tier 'ddaanet''s lines:"$'\n'"gitlore:   memory/ddaanet/MEMORY.md: duplicate pointer path a.md"* ]]' failed
```

Stderr under today's code, dumped with a temporary `printf` that was then
reverted:

```
fatal: shim refuses commit-tree
gitlore: tier 'ddaanet' — its arrival could not be repaired: building the repair commit failed.
gitlore: nothing was recorded, and tier 'ddaanet' is back on the commit the memory store records; its local 'live' keeps what arrived. Fix the store, then run /gitlore:merge again.
```

The status 1, stub-hit and `building the repair commit failed` premises pass. The
first missing behavior is the header.

## 2. Wrong-reason hunting

- **Stub conformance.** The stub is `$BATS_TEST_TMPDIR/fakebin/git`. It matches
  with `case " $* "` and `exec`s the real git otherwise, as the :415 idiom does.
  It is on `PATH` only for `run … bash "$CMD"`, so the later `rev-parse` uses
  the real git. `rg commit-tree scripts/` finds one call,
  `gitlore_adopt_commit_repair` (`scripts/lib/resolve.sh:1998`), so the stub
  matches only the intended call. Its message text cannot contain
  ` commit-tree `.
- **Listed assertions.** All five are present: build-failed line, header followed
  by the carrier line, `Run /gitlore:merge again.`, no `Fix the store`, and tier
  `HEAD` on the pin. The header check requires the carrier line to come right
  after the header. That is stricter than "then a line containing". It matches
  the helper's output, since the composed refusal here is exactly one line, and
  slice 1's style at :828.
- **Pin assertion is not vacuous.** `pin` is the real tier `HEAD`, captured
  before `push_tier_fact`, which commits in a throwaway clone. Reaching the
  build-failed arm requires the take to have checked out the arrival: the arm
  reads the duplicate from `HEAD:MEMORY.md`. So `HEAD = pin` proves the
  walk-back ran.
- **Right-reason pass (probe, reverted).** The probe patched the commit-build arm
  to print the header and `$composed` and to set
  `remedy="Run /gitlore:merge again."`, which is the report helper's output
  shape. The test passed, with stderr:
  ```
  fatal: shim refuses commit-tree
  gitlore: tier 'ddaanet' — its arrival could not be repaired: building the repair commit failed.
  gitlore: the root index could not take tier 'ddaanet''s lines:
  gitlore:   memory/ddaanet/MEMORY.md: duplicate pointer path a.md
  gitlore: nothing was recorded, and tier 'ddaanet' is back on the commit the memory store records; its local 'live' keeps what arrived. Run /gitlore:merge again.
  ```
- **Mutant: header printed, default remedy kept.** Killed, at
  `[[ "$stderr" == *"Run /gitlore:merge again."* ]]`, line 622 of the probe
  copy. The default remedy's `run` is lowercase, and `[[ == ]]` is
  case-sensitive.
- **Mutant: both remedies printed.** Killed, at
  `[[ "$stderr" != *"Fix the store"* ]]`, line 622 of the probe copy.

The probe edits to `scripts/lib/resolve.sh` and the test file were restored from
byte copies. `git diff --quiet scripts/` holds, and the test file's diff is the
original 31 lines.

## 3. Fixes

None needed. `shellcheck tests/merge_memory.bats` is clean. The re-run is still
red on the header assertion at line 619. Nothing committed.
