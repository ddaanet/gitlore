# Review: Item 1.1 slices 2–6 — guard tests

**Scope**: uncommitted tests in `tests/git_hook_pre_commit.bats` (slice 2),
`tests/commit_memory.bats` (slices 3, 4, 5), `tests/index_compose.bats` (slice
6). SUT (`scripts/`) committed, left unmodified. **Date**: 2026-09-14 **Mode**:
review + fix (TDD test review, guard slices)

## Summary

All six tests are guards and pass against the committed SUT. The recorded
mutation-reds hold where reproduced. Three tests could pass or read as passing
on the wrong arm, and two comments cited plan identifiers; all are fixed. One K5
contract, root reports when memory is dirty only outside `MEMORY.md`, had no
test. A mutation that drops root's `-- MEMORY.md` pathspec stayed green across
the whole batch, so a guard for it is added.

**Overall Assessment**: Ready

## Mechanical check

Filtered runs, before fixes: slice 2 `1 passed`; slices 3–5 `4 passed`; slice 6
`1 passed`.

Mutation-reds reproduced (in-place mutation, run, `git checkout HEAD -- <file>`,
then `git diff --quiet HEAD -- scripts` confirmed after each):

| Mutation (`scripts/lib/resolve.sh`) | Test | Result |
|---|---|---|
| Abort arm's `touch "$msgfile"` → `:` | slice 2 | red, line 418: the mtime assertion |
| Root attribution condition → `[ -n "$compose_result" ]` | slice 5 | red, `[ "$status" -eq 0 ]` |
| Root status read without `-- MEMORY.md` only | slices 1, 3, 4, 5 | **all 5 green**: gap, Major 2 |
| Same, after fix | new root test | red, `[ "$status" -eq 0 ]` |

The slice 4 variants (whole-tree pathspec on both reads; no dirtiness read) and
slice 6's `grep "^$file: "` and word-splitting variants are not re-run. Each
recorded red targets exactly the assertion its fixture isolates, confirmed by
reading.

## Conformance

- **Slice 2:** conforms. It uses slice 1's fixture, writes the summary to
  `gitlore_commit_msg_file memory`, backdates it and every
  `find memory -type f -not -path '*/.git/*'` file with one `touch -t`, checks
  that freshness reads `yes`, runs `bash "$HOOK"`, and asserts a non-zero exit,
  the duplicate line, memory `HEAD` unchanged and a restamp newer than the
  stamp's epoch.
- **Slice 3:** conforms. The line is exactly `- [A](a.md) — a- [B](b.md) — b`.
  The expected line number comes from `wc -l`, independent of the SUT, and sits
  inside the `memory/MEMORY.md: line $n welds` anchor, so `line 1` cannot match
  `line 11`.
- **Slice 4:** conforms. The tier commit uses `GITLORE_MEMORY_COMMIT=1`, the pin
  is recorded with `commit_memory_state`, and root gets an unrelated uncommitted
  bullet. The second test adds an uncommitted `extra.md`.
- **Slice 5:** conforms. It adds a `gone/x.md` bullet, then asserts exit 0,
  `HEAD` advanced, `gone/x.md` and `the commit went ahead`.
- **Slice 6:** conforms. The four prefixed lines, including the decoy
  `my memXd/MEMORY.md`, and the rule 3 line are verbatim from
  `gitlore_compose_check`. The three queries assert exact output and status.
- **`CLAUDECODE`:** every entry-point run sets `CLAUDECODE=1` explicitly. Slice
  6 calls the helper in-process.

## Issues Found

### Critical Issues

None.

### Major Issues

1. **Slices 2 and 3 do not pin the abort arm**
   - Location: `tests/git_hook_pre_commit.bats` slice 2 test,
     `tests/commit_memory.bats` "a dirty root index with a welded line aborts
     the memory commit"
   - Problem: the asserted problem line prints on the advisory arm too. With no
     arm-naming assertion, a non-zero exit from any other refusal that prints
     the compose result, plus memory `HEAD` unchanged, satisfies both tests.
     Slice 2 is saved only because an advisory commit deletes `$msgfile`, which
     makes `_gitlore_mtime` fail. Slice 3 has no such backstop beyond its exit
     status. Neither asserts the premise that the aborted index is still dirty.
     Slice 2 also leaves the tier's `HEAD` unchecked, though the outline's S1
     postcondition says the tier stays uncommitted.
   - Fix: slice 1's idiom in both tests: `*"aborted"*` and
     `!= *"the commit went ahead"*`, plus a non-empty
     `status --porcelain -- MEMORY.md` on the aborted index. Slice 2 also
     asserts the tier `HEAD` is unchanged.
   - **Status**: FIXED

2. **Root dirtiness pathspec uncovered**
   - Location: `tests/commit_memory.bats` (missing test)
   - Problem: under K5, "problems in clean files" stay advisory. Slice 4 covers
     that for a tier dirty only outside its carrier, but nothing covers root.
     Reading root dirtiness from the whole memory tree
     (`git -C "$mempath" status --porcelain`) keeps all five
     `commit_memory.bats` tests in the batch green (reproduced). That
     implementation would abort every memory commit that adds a fact file while
     root holds a committed rule 1, 4 or 6 problem.
   - Fix: added "a root index dirty only outside MEMORY.md commits and reports".
     It commits two `dup.md` root bullets with `commit_memory_state`, then adds
     an uncommitted `memory/unrelated.md` with no index line. It asserts exit 0,
     `HEAD` advanced, `the commit went ahead` and
     `memory/MEMORY.md: duplicate pointer path dup.md`. It passes against the
     SUT and goes red under the mutation.
   - **Status**: FIXED

### Minor Issues

1. **Slice 5 asserts a bare path substring**
   - Location: `tests/commit_memory.bats` "a leftover root prefix commits and
     reports even when root is dirty"
   - Note: `*"gone/x.md"*` would match any output that echoes the path, such as
     a staged-file listing. It now asserts the rule 3 message:
     `root index line 'gone/x.md' has a prefix naming no mounted tier`.
   - **Status**: FIXED

2. **Stderr-suppressed `date` fallback in slice 2**
   - Location: `tests/git_hook_pre_commit.bats` slice 2 test
   - Note: `date -v-10d … 2>/dev/null || date -d …` hid a real `date` failure
     behind the fallback, against the project's no-`2>/dev/null` rule. A fixed
     `touch -t 200001010000` needs neither the redirect nor the GNU/BSD split.
     The comment now also states why the test backdates instead of sleeping.
   - **Status**: FIXED

3. **Test comments cite plan identifiers**
   - Location: slice 2 comment ("Item 1.1 slice 1's abort"), slice 3 comment
     ("K5's other abort path")
   - Note: the dispatch constraints forbid source files citing a runbook item,
     slice or outline decision. Both comments are reworded to state the
     behaviour.
   - **Status**: FIXED

4. **Slice 4 fixture duplicated, with an unchecked premise**
   - Location: `tests/commit_memory.bats`, both slice 4 tests
   - Note: both tests repeated the same nine-line committed-defect fixture, and
     neither checked the "clean carrier" premise. The fixture is extracted into
     `committed_carrier_defect_store`, placed after its users, following
     `committed_stale_carrier_store`'s `|| return 1` idiom and ending with a
     clean-carrier check.
   - **Status**: FIXED

## Wrong-reason hunting: checked, no finding

- **Slice 4 "compose never refuses":** ruled out.
  `duplicate pointer path shared.md` and `the commit went ahead` appear only in
  the rc 1 arm's refusal, so an exit 0 without a refusal fails both assertions.
- **Slice 2 "the hook touched the file for another reason":** the other
  restamping returns (`gitlore_stage_landed_tiers`, the pin guard, rc 2) leave
  before or instead of the compose refusal, so they cannot also print the
  duplicate line. The advisory arm deletes `$msgfile`.
- **Slice 6 unanchored `grep -F`:** it would pass, but no realistic
  `gitlore_compose_check` line contains `<mempath>/MEMORY.md: ` mid-line. Tier
  lines interpose `<tier>/`, and rules 3 and 6 quote relative paths. A fixture
  built to catch it would be unreachable from the check, so none is added.
- **Slice 3 line number:** independent of the SUT, and anchored by the
  `memory/MEMORY.md: line ` prefix and the ` welds` suffix.

## Fixes Applied

- `tests/git_hook_pre_commit.bats` slice 2: comment reworded without plan
  citations. The `date` fallback is replaced by a fixed `touch -t 200001010000`,
  with the comments merged. Added `aborted`, not `the commit went ahead`, a
  dirty-carrier check and tier `HEAD` unchanged.
- `tests/commit_memory.bats` slice 3: comment reworded. Added `aborted`, not
  `the commit went ahead`, and a dirty root `MEMORY.md`.
- `tests/commit_memory.bats` slice 4: both tests use the new
  `committed_carrier_defect_store` helper, which ends with a clean-carrier
  check.
- `tests/commit_memory.bats`: new test "a root index dirty only outside
  MEMORY.md commits and reports".
- `tests/commit_memory.bats` slice 5: asserts the full rule 3 message prefix.
- `tests/index_compose.bats` slice 6: unchanged.

## Verification

- Whole files, one at a time: `git_hook_pre_commit.bats` 20 passed, 0 failed;
  `commit_memory.bats` 34 passed, 0 failed (33 + the new root test);
  `index_compose.bats` 66 passed, 0 failed.
- `shellcheck` on the three files: clean.
- `git diff --quiet HEAD -- scripts`: holds.
  `git status --porcelain -- tests scripts` shows only the three test files
  modified. Nothing committed.

## Requirements Validation

| Requirement | Status | Evidence |
|---|---|---|
| K5 abort, dirty carrier, via `pre-commit`, restamp | Satisfied | slice 2 test |
| K5 abort, dirty root rule 6 | Satisfied | slice 3 test |
| K5 advisory, clean carrier / tier dirty outside carrier | Satisfied | slice 4 tests |
| K5 advisory, root dirty outside `MEMORY.md` | Satisfied | new root test |
| K5 advisory, root rule 3 even when dirty | Satisfied | slice 5 test |
| Helper exact-prefix attribution, space, prefix-named tiers | Satisfied | slice 6 test |
