# Item 3.1 / Slice 1 — test review

Test: `tests/index_compose.bats` "a duplicate dropped from the end terminates
the new last line". Verdict: **the red is valid.** Two minor fixes applied, no
UNFIXABLE findings.

## Checks

1. **Mechanical.** `scripts/run-bats.sh tests/index_compose.bats` gives 81
   passed and 1 failed. The failure is the new test at line 1361,
   `cmp -s file.md expected.md`. It is the same after the fixes.
2. **Right reason.** The unterminated precondition, the duplicate count (2),
   `$status` 0 and the report line all pass before the `cmp -s`. The empty pin
   comes from `touch pin.md`. The expected file is the input minus its last
   line, and the new last line ends in exactly one `\n`, as the spec requires.
   The RED report's `od -c` shows the actual output is short by exactly that
   newline.
3. **Spec fidelity.** It uses `cmp -s` against a `printf`-built `expected.md`,
   like "welds are split before duplicates are resolved". The call is
   `gitlore_repair_index file.md pin.md tier`, with the same argument order as
   the sibling and as `scripts/lib/resolve.sh:1966` (file, pin, tier dir). The
   output lands in place in `<file>`, and the test reads it from there. The
   sibling passes a `pin.md` that does not exist, while this test uses an empty
   file. Both read as an empty carrier, and production can produce either. Not a
   finding.
4. **Constrains the fix.** I tested both fixes in a scratch copy
   (`/tmp/claude-1000/probe.*`, removed afterwards):
   - **Spec rule** (index-tracked provenance): the output stays unterminated
     only when the input was unterminated and the last element of p3 is the
     input's last p1 element that survived. Result: 82/82 pass, the new test and
     the weld sibling included.
   - **Lazy fix** (always write `'%s\n'`): the new test passes, but the sibling
     fails at line 1343 (`cmp -s`). The two tests together rule this fix out.
5. **Hygiene.** Quoting is sound, shellcheck is clean and the test name is
   accurate. No line numbers or plan ids appear.

## Fixes applied

- **Comment inaccuracy.** The comment said the new last line "must gain the
  newline the input never gave it". It is wrong: that line was terminated in the
  input, and the repair strips its newline. The comment now reads: "the line
  before it becomes last and keeps the newline it had in the input."
- **Comparison form.** The unterminated precondition was
  `[ "$(tail -c 1 file.md | wc -l | tr -d ' ')" = 0 ]`. It is now
  `[ "$(tail -c 1 file.md | wc -l)" -eq 0 ]`. An integer test ignores BSD `wc`'s
  padding, so no `tr` is needed.

Re-run after the fixes: 81 passed, 1 failed, still on the `cmp -s` at line
1361. `shellcheck tests/index_compose.bats` exits 0.

## Out of scope, noted

Production code (`scripts/lib/index-compose.sh`) uses the same
`wc -l | tr -d ' '` / `=` form. It is correct there, and this slice does not
touch it.
