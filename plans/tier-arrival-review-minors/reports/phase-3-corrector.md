# Phase 3 corrector: terminator preservation

Scope: `gitlore_repair_index` (tagging and final write), the M8 comment, and the
Phase 3 tests in `tests/index_compose.bats`. Diff base `7639748`.

## Verdict

The phase implements the rule, and the M8 wording is exact. No critical or major
findings. There are two findings, both applied.

## Findings and fixes

1. **Minor, simplification (applied).** The four parallel tag arrays (`p1last`,
   `p2last`, `straylast`, `p3last`) track one fact: where the input's last
   element ends up. Every `+=` site has to stay aligned with its partner. The
   slice-2 test review's mutant B showed what a missed site does: it aborts
   under `set -u`, or it shifts the tag without an error. Two scalars now carry
   the same information:
   - `tagged` is that element's index in p2. It is set when `n` reaches
     `${#p1[@]}`. p1's last element is the input's last line or that line's weld
     tail. It is never a stray, because a stray needs `n < last <= ${#p1[@]}`.
   - `p3tagged` is its index in p3. It stays -1 when a drop retires the element.
   - The final check is `[ "$p3tagged" -eq "$last_i" ] || terminated=1`.

   The change removes 15 lines and adds 12, and deletes every append-alignment
   site. The existing tests pass without edits.

   **Proof.** A differential probe ran HEAD's function and the rewritten one on
   22 inputs, with mode 640, in a scratch dir under `/tmp/claude-1000`. It
   compared the output bytes, the report, the status, the mode, and the leftover
   files in the directory. All 22 matched. The inputs were the 14 edge cases
   from `item-3-1-s1-code-review.md` plus:
   - a stray with a terminated trailer;
   - a stray and a duplicate of the last bullet;
   - a duplicate whose first copy is last, with both copies in the pin;
   - an input made only of duplicates;
   - leading prose, a weld, and a duplicate together;
   - no bullet;
   - a whitespace-only unterminated trailer;
   - a single unterminated bullet.

2. **Minor, test gap (applied).** None of the Phase 3 tests or :1334 separates
   "the input's last line" from "the last bullet", because in each fixture they
   are the same line. The new test "a stray moved ahead of an unterminated
   trailer leaves the trailer unterminated" uses an unterminated trailer after
   the region. It expects the stray between the last bullet and the trailer, and
   the trailer still unterminated.

   **Teeth.** Each mutant was applied in its own call, with a backup copy and a
   `cmp` restore. Filtered to the four terminator tests:
   - `tagged` keyed to the last bullet (`-ne "$last"`) failed only the new test,
     on `cmp -s`. Slice 1, slice 2 and :1334 all pass that mutant. It is the
     byte-level alignment residual the slice-2 test review named.
   - Replacing the final check with `:` (the pre-fix rule) failed slice 1 and
     slice 2 on `cmp -s`.
   - `tagged` keyed to `-lt "$last"` turned out equivalent: the last assignment
     wins at `n == ${#p1[@]}`. That is not a gap.

## Lifecycle

- **Scratch files.** Every failure path after `mktemp` removes the scratch file.
  The no-repair path returns before `mktemp`. In the probe, no
  `.gitlore-repair-index.*` file remained in any case.
- **File mode.** `cp -p` onto the scratch file happens before either write
  branch, so both the terminated and unterminated writes keep the mode. The
  probe confirmed 640 in all 22 cases.

## Verification

- `shellcheck scripts/lib/index-compose.sh tests/index_compose.bats`: clean.
- `scripts/run-bats.sh tests/index_compose.bats`: 84 passed, 0 failed (83
  existing plus the new test).
- After the mutants, `cmp` confirmed the script matched the backup. `git diff`
  holds only the two changes above.
- The probe directory was removed.

## Environment note

`$TMPDIR` was set in one Bash call and unset in the next. `${TMPDIR:?}` aborted
the backup command before any mutation. All scratch work used an absolute
`/tmp/claude-1000/phase3-probe.*` dir instead.

## Files changed (uncommitted)

- `scripts/lib/index-compose.sh`
- `tests/index_compose.bats`

## UNFIXABLE

None.

## Design decisions

None.
