# Item 3.1 / Slice 2 — test review (guard)

Test under review: `tests/index_compose.bats`, formerly "a moved stray at the
end keeps the newline the last bullet had", now "a stray moved past an
unterminated last bullet keeps its newline and terminates the bullet".

## Findings and fixes

1. **Name said the reverse of the bytes (fixed).** The last bullet had *no*
   newline in the input, so a stray cannot "keep the newline the last bullet
   had". The stray keeps its own newline, and the bullet gains one. Renamed.
2. **Comment said the stray "inherits the terminator" (fixed).** The input's
   terminator is "none", and the stray does not inherit it: the stray is not the
   tagged last line, so the output ends with a newline. The comment now says the
   stray keeps its own newline and the bullet, no longer last, gains the one it
   lacked.
3. **Precondition did not prove line 3 is the last line (fixed).** Added
   `[ "$(wc -l < file.md)" -eq 2 ]`. Together with the unterminated check, this
   pins the file at exactly three lines, so the bullet on line 3 is the
   unterminated last line the spec requires.
4. **No report assertion (fixed).** The slice 1 test next to it asserts
   `$output`. Added
   `[ "$output" = "moved a non-bullet line out of the pointer block: Stray line" ]`,
   so the test also proves the stray path ran and that no other repair (a drop
   or a split) fired.

## Checks

- **Spec fidelity:** holds. Expected bytes are
  `- [A](a.md) — hook\n- [B](b.md) — hook\nStray line\n`: the stray sits after
  the last bullet, and the bullet and the stray each end in one newline. This
  matches runbook slice 2 and outline case 2 exactly. The pin is empty
  (`touch pin.md`).
- **Guard holds:** after the fixes,
  `scripts/run-bats.sh tests/index_compose.bats` gives 83 passed, 0 failed.
  `shellcheck tests/index_compose.bats` is clean.
- **Hygiene:** preconditions come before the repair. The test is bash 3.2 and
  BSD safe: `tail -c`, `wc -l <`, `sed -n 'Np'` and `printf --`. Quoting is
  sound, and the test cites no plan ids or line numbers.

## Teeth (mutants, each restored with `git checkout --`)

`scripts/lib/index-compose.sh` had no uncommitted edits at the start, so
`git checkout --` is an exact restore.

- **Report mutant** (`p2last+=(1)` on the splice): red on `cmp -s`, per the RED
  report.
- **A. Pre-fix final-write rule.** Deleted
  `[ "$last_i" -ge 0 ] && [ "${p3last[last_i]}" = 1 ] || terminated=1`, which
  keys termination on "input unterminated" alone. Red on `cmp -s`, as is slice
  1's test.
- **B. Splice omits `straylast`** (tags misaligned). Red on
  `[ "$status" -eq 0 ]`: `set -u` aborts on the unset `p2last` index. It is
  caught, though not on the byte assertion.
- **C. Bullet tag appended after the splice** (the stray takes the bullet's tag,
  a natural reordering bug). Red on `cmp -s`.

After the last mutant, `git diff --stat -- scripts` is empty.

## Incident during the mutation run

My first mutation command was a multi-line Bash call. It failed at `${TMPDIR:?}`
in the `&&` chain that makes the backup, but the later newline-separated
statements still ran. Mutants A and B were applied cumulatively with no backup,
and the `--filter` variable was unset, so mutant A ran against the full file (81
passed, 2 failed: slice 1's test and this one, both on `cmp -s`). I stopped the
task and restored the script with `git checkout --`. `git diff` and
`git status --porcelain -- scripts` were then empty. B and C were re-run one per
call against the clean tree.

## Residual (not a defect in scope)

Mutant B reds only on the exit status here, because nothing follows the stray. A
fixture with a trailer line after the last bullet would show misalignment as
wrong bytes. That scenario is outside this slice's specified input, so no test
was added.

UNFIXABLE: none.
