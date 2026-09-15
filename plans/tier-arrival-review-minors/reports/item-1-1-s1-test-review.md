# Item 1.1 / slice 1 — test review

**Test:** `an arrival the repair cannot fix beside a root duplicate reports both
and the two-fix remedy` (`tests/merge_memory.bats`).

**Verdict:** red for the right reason. Two small fixes applied; still red on an
assertion; shellcheck clean.

## Mechanical

Re-ran `scripts/run-bats.sh tests/merge_memory.bats --filter "beside a root
duplicate reports both and the two-fix remedy"` before and after the fixes. Both
runs: `not ok`, failing on the `[[ … ]]` header-plus-root-line assertion. It is
not a setup error: the preceding premise checks, `status -eq 1` and the
`live:MEMORY.md:` line all pass.

## Wrong-reason hunting

- **The fixture really is a root duplicate beside an unrepairable arrival.** I
  probed it with a temporary block, since removed, that checked the tier out on
  the arrival and ran `gitlore_compose_up memory ddaanet`. It returned rc=1, and
  `$composed` was:
  ```
  memory/MEMORY.md: duplicate pointer path dup.md
  memory/ddaanet/MEMORY.md: duplicate pointer path b.md
  memory/ddaanet/MEMORY.md: line 8 welds two pointer bullets …
  ```
  `gitlore_compose_problems_in memory/ddaanet/MEMORY.md` selects only the last two.
  So the refusal's "other lines" are exactly the root line. The mempath is the
  relative `memory` (from `.gitmodules`), so the literal `memory/MEMORY.md:`
  prefix in the assertion matches what the implementation will print.
- **Current stderr**, captured with the same probe: the carrier header, two
  `live:MEMORY.md:` lines, and the walk-back line ending `… Once the index is
  fixed where it was published, run /gitlore:merge again.` The header assertion
  fails because nothing prints the refusal header.
- **Assertion 1** (`$'\ngitlore:   live:MEMORY.md:'`) is anchored to a line start.
  It holds today and must keep holding, which is the slice's intent.
- **Assertion 3 ("ends with")** has no trailing `*`, so it genuinely anchors the
  end of stderr (bats strips the trailing newline). It is hidden behind the
  failing header assertion, but it would fail on its own too. Today's tail has
  `Once` capitalised and lacks the `Fix the problems listed above in this repo;`
  prefix, so it cannot pass vacuously.
- **Assertion 2** asserts that the header is immediately followed by the root
  line. This matches `$composed` order, root before tier.

## Fixes applied

1. **Filtered and full refusal were indistinguishable.** An implementation that
   printed all of `$composed` under the header would pass all three slice
   assertions, because the root line comes first. It would also list the carrier
   problems twice. The Changes spec for the unrepairable arm prints only the
   lines `gitlore_compose_problems_in` does not select. Added
   `[[ "$stderr" != *"memory/ddaanet/MEMORY.md:"* ]]` with a two-line comment.
   It holds today, so red still comes from the header assertion, and it holds
   after a correct implementation. The substring cannot match the root line.
2. **The "dirty root duplicate" premise was unasserted.** Added
   `[ "$(grep -cF '(dup.md)' memory/MEMORY.md)" -eq 2 ]` and
   `run ! git -C memory diff --quiet -- MEMORY.md`. These make it explicit that
   the root index holds two `dup.md` pointers uncommitted, in the style of the
   neighbouring tests' premise checks.

## Not changed

- The test at :744 and its :771 assertion were not touched.
- No SUT edits. Nothing committed.
