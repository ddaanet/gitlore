# Review: Item 2.1 RED tests (`gitlore_repair_index`)

**Scope**: the uncommitted Item 2.1 tests in `tests/index_compose.bats`, the RED
report, and the inert stub in `scripts/lib/index-compose.sh` (stub completion
only). **Date**: 2026-09-14 **Mode**: review + fix (tests only; nothing
committed)

## Summary

The batch covers all eight slices, the report strings match the runbook exactly,
and every red fails on an assertion. Four gaps let a plausible wrong
implementation pass:

- a rewrite of identical bytes renamed over the file;
- a weld guard keyed on the first link's path;
- a repair that never terminates the last line;
- a scratch file in `$TMPDIR`.

Smaller gaps: slice 3's two-bullet case did not run the check, slice 5 asserted
bytes through `$(cat)`, and no test separated "the first line the pin lacks"
from "the last". All are fixed in the tests. The stub needed no change.

**Overall Assessment**: Ready

## Mechanical check

Before and after the fixes, `scripts/run-bats.sh tests/index_compose.bats` was
run on the whole file.

- **Before:** 69 passed, 10 failed. Matches the RED report.
- **After:** 69 passed, 11 failed. The extra failure is the new slice 6 row.

Every failure is on an assertion. None is a "command not found", an unbound
variable or an error.

- **Guards (PASS):**
  - "repairing a clean index changes nothing"
  - "a weld naming no file in the tier is left unchanged"
  - "a link the check does not report as a weld is left unchanged"
- **Red (FAIL on assertion):** slices 2, 3 (×2), 5, 6 (×5, including the new
  row), 7 and 8.

The recorded guard mutation (`printf '\n' >> "$1"`) is plausible but weak: any
edit reds it. The mutations below test the specific wrong implementations.

`shellcheck -x tests/index_compose.bats scripts/lib/index-compose.sh` is clean.

## Mutated-SUT runs

The SUT was saved, the stub replaced in place, the named tests run, and the file
restored. `cmp` against the saved copy confirms the restore.

| Mutation | Tests run | Result |
|---|---|---|
| `cp "$1" "$1.x" && mv "$1.x" "$1"` (same bytes, new inode) | clean index | reds on `[ clean.md -ef clean.link ]` |
| Weld split, guard on the **second** path (correct) | weld tests | slices 3, 3b, 4, 4b pass (spaced tier dir works); slice 7 reds (no dedup) |
| Weld split, guard on the **first** path | weld tests | slices 3, 3b and 4 red |
| Identical-dedup with `mktemp` beside `<file>` | slice 2, slice 8 | both pass |
| Identical-dedup with `mktemp "${TMPDIR:-/tmp}/…"` | slice 8 | reds on the `$TMPDIR` half (`[ "$status" -eq 0 ]`) |

A probe confirmed that an unwritable `$TMPDIR` makes `mktemp` fail while bash
heredocs and here-strings fall back to `/tmp`. The `$TMPDIR` half therefore
checks the scratch location, not whether bash itself can run.

## Issues Found

### Critical Issues

None.

### Major Issues

1. **Slice 1 did not detect a rewrite on every call**
   - Location: "repairing a clean index changes nothing"
   - Problem: the runbook says the scratch file is renamed over `<file>` "only
     when an edit was made". A repair that always writes the same bytes and
     renames them over the file passes `cmp`.
   - Fix: hard-link the fixture before the call and assert
     `[ clean.md -ef clean.link ]` afterwards. The same check covers the
     unterminated copy. The fixture also gained a preamble, blank lines in the
     region and a trailer, so a repair that normalizes those parts reds too.
   - **Status**: FIXED

2. **The weld guard's path was not pinned**
   - Location: slices 3 and 4
   - Problem: slice 3 created both `welded_a.md` and `welded_b.md`, and slice 4
     created neither `kept.md` nor `z.md`. A guard testing the first link's path
     passed both slices.
   - Fix:
     - Slice 3 (both tests) creates only the second and third paths.
     - Slice 4 creates `tier/kept.md`.
     - Mutation-verified in both directions.
   - **Status**: FIXED

3. **Bytes after an edit were never asserted with a terminated last line**
   - Location: slice 5 (`$(cat)`); slice 2 (`assert_bullets` only)
   - Problem: `$(cat)` strips trailing newlines. Slice 7, the only exact-bytes
     test, expects an unterminated result. A repair that drops the final newline
     on every rewrite passed slices 2 through 7.
   - Fix: slices 2, 5 and 7 compare against an expected file with `cmp -s`.
     Slice 7's `$(cat)` plus `tail -c 1` pair became one `cmp`.
   - **Status**: FIXED

4. **Slice 5 could not tell "directly after the last bullet" from "after the
   trailer's first blank line"**
   - Location: "an interleaved non-bullet line moves to the start of the
     trailer"
   - Problem: in `gitlore_index_region` and `gitlore_index_part`, the trailer is
     everything after the last bullet. The fixture's trailer started with prose,
     so an implementation that places moved lines after the trailer's leading
     blank matched the expected bytes.
   - Fix: the fixture has a `# Memory Index` preamble and a blank line opening
     the trailer. The expected bytes put the moved lines directly after the last
     bullet, ahead of that blank.
   - Already caught: moved lines at the end of the file, and blank lines moved
     or dropped.
   - The test now also asserts that the result passes the check.
   - **Status**: FIXED

5. **The scratch location was untested**
   - Location: slice 8
   - Problem: a read-only directory reds a scratch file renamed from `$TMPDIR`
     as well (the rename into the directory fails). The runbook's "written
     inside `<file>`'s directory" had no test.
   - Fix: slice 8 now has a positive second half on the same fixture. The
     directory is writable and `TMPDIR` points at a read-only directory. The
     call must return 0, report the drop and leave the deduplicated bytes, and
     the directory must hold no leftover scratch file (`ls -A dir`). This half
     also shows the first half's rc 1 comes from the directory's permissions.
   - **Status**: FIXED

6. **"The first line the pin lacks" was indistinguishable from "the last" or
   "any"**
   - Location: slice 6
   - Problem: with two variants and the pin holding one, exactly one line is
     absent from the pin. A "keep the last absent" rule passed every row.
   - Fix: new row "a differing duplicate: of several lines the pin lacks, the
     first survives". The pin holds v1 and the file holds v1, K, v2, v3. v2
     survives at its own position, and the report names v1 then v3, in file
     order, consistent with slice 5's report order.
   - **Status**: FIXED

### Minor Issues

1. **Slice 3's two-bullet case did not run the check**
   - Location: "a welded line is split before the second bullet"
   - Note: the runbook says "each result passes the check". Added
     `gitlore_compose_check_index` with an empty-output assertion.
   - **Status**: FIXED

2. **Slice 4 did not pin its fixtures' premise**
   - Location: both slice 4 tests
   - Note:
     - Weld test: a probe confirmed the check reports the fixture as
       `line 1 welds two pointer bullets … z.md is invisible`. The test now
       asserts that prefix, so the "no file in the tier" condition cannot pass
       on a fixture that is not a weld.
     - Guard test: now asserts the check prints nothing for its fixture.
   - **Status**: FIXED

3. **The pin-carrier read guard was untested**
   - Location: "a differing duplicate keeps the line the pin lacks"
   - Note: the runbook requires `|| [ -n "$line" ]` on every read. The main
     case's pin now goes through `unterminate_index`. A bare `read` loses the
     pin's only line, treats both variants as absent, keeps the first and reds.
   - **Status**: FIXED

4. **No whitespace in any path argument**
   - Location: slice 3
   - Note: the tier directory is now `the tier`, so an unquoted
     `[ -f $tier/$path ]` reds. Mutation-verified: the quoted guard passes.
   - **Status**: FIXED

## Fixes Applied

All in `tests/index_compose.bats`:

- **Slice 1:** richer clean fixture (preamble, blank lines, trailer), and hard
  links with `-ef` on both calls.
- **Slice 2:** `cmp` against the exact expected bytes.
- **Slice 3, two-bullet:** tier dir `the tier`, only `welded_b.md` created, the
  check asserted, and a comment on the fixture's intent.
- **Slice 3, three-bullet:** `welded_a.md` no longer created.
- **Slice 4, weld:** `tier/kept.md` created, and the check's weld report
  asserted on the fixture.
- **Slice 4, guard:** the check's empty output asserted on the fixture.
- **Slice 5:** preamble and trailer-leading blank added to the fixture, `cmp`
  against expected bytes, and the check asserted.
- **Slice 6, main:** `unterminate_index pin.md`.
- **Slice 6, new row:** three variants.
- **Slice 7:** one `cmp` against an unterminated expected file replaces `$(cat)`
  plus `tail -c 1`.
- **Slice 8:** positive `TMPDIR`-unwritable half, with the leftover-scratch
  check.

`scripts/lib/index-compose.sh` is unchanged.

## Requirements Validation

| Requirement (Item 2.1 slice) | Status | Evidence |
|---|---|---|
| 1 clean index, terminated and unterminated, byte-identical, empty, rc 0 | Satisfied | `cmp` plus `-ef`, both variants |
| 2 identical duplicate: exact report, result passes check | Satisfied | exact string, `cmp`, check |
| 3 weld split at its position, exact report, three-bullet ×2, check | Satisfied | K/Z neighbours, both run check |
| 4 weld with no file unchanged; bare link unchanged | Satisfied | premise asserted, `cmp` |
| 5 moved lines in order at the start of the trailer, blank stays | Satisfied | exact bytes with a trailer-leading blank |
| 6 pin-lacking line kept at its own position; three rows | Satisfied | K/Z/v2 order; rows plus the first-of-several row |
| 7 welds before duplicates, bytes of trailing-space, non-ASCII, unterminated lines | Satisfied | `cmp`, check |
| 8 unwritable: rc 1, byte-identical, root skip | Satisfied | plus the scratch-location half |

**Gaps:** none.

## Positive Observations

- Report strings match the runbook verbatim, and multi-line reports are pinned
  in order.
- Slice 6's main case puts `Z` between the variants, so "at its own position" is
  a real ordering claim.
- Slice 8 restores permissions immediately after `run`, before any assertion can
  abort the test, and skips under root.
- Scratch-file fixtures fit the function's three-path contract with no tier
  mount.

## Recommendations

- **GREEN:**
  - Take the scratch file with `mktemp` beside `<file>` and rename it only when
    an edit was made.
  - Write every report line only after the rename succeeds.

  Slice 8's first half does not require the second point: rc 1 and unchanged
  bytes hold either way. The contract ("nothing when no edit") implies it.
