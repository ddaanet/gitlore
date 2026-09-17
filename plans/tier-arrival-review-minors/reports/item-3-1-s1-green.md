# Item 3.1 / Slice 1 — GREEN

## Test transition

`tests/index_compose.bats` "a duplicate dropped from the end terminates the
new last line": red at `cmp -s file.md expected.md` (line 1361, as recorded in
`item-3-1-s1-red.md`) → green.

## Implementation

`gitlore_repair_index` (`scripts/lib/index-compose.sh`) decides termination by
provenance, not by the input's terminated state alone. A parallel `1`/`0` tag
array rides each content array (`p1`/`p1last`, `p2`/`p2last`, `p3`/`p3last`):
the single element tagged `1` is the input's last line, or that line's tail
after a weld split (the last element ever pushed onto `p1`, since weld
splitting always pushes the tail last and the outer loop iterates the file in
order). The tag moves wherever its element moves — into `stray` and back on a
move, dropped along with its element on a duplicate drop. The output stays
unterminated only when the input was unterminated *and* the tagged element is
still `p3`'s last element; any other outcome (the tagged element dropped, or
displaced from last by a stray landing after it) writes every element with
`'%s\n'`, including the new last line.

Also applied per the dispatch: the comment above `gitlore_compose_check_index`
now reads "a defect no take can adopt past" (M8).

## Test runs

- `scripts/run-bats.sh tests/index_compose.bats` → 82 passed, 0 failed
  (includes "welds are split before duplicates are resolved" and the new
  test).
- `scripts/run-bats.sh tests/commit_memory.bats` → 35 passed, 0 failed.
- `scripts/run-bats.sh tests/merge_memory.bats` → 41 passed, 0 failed.
- `scripts/run-bats.sh tests/plugin_distribution.bats` → 15 passed, 0 failed.
- `scripts/run-bats.sh tests/resolve_compose.bats` → 23 passed, 0 failed.
- `shellcheck -x scripts/lib/index-compose.sh tests/index_compose.bats` →
  clean.

Slice 3.1/2 (moved stray at the end) is covered by the same rule and is left
untested per the dispatch; its fixture would exercise the `stray`/`straylast`
path but is out of scope for this slice.
