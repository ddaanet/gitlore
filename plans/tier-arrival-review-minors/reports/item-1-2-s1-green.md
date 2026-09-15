# Item 1.2 slice 1 — GREEN

**Change:** `gitlore_adopt_repair_arrival` in `scripts/lib/resolve.sh`:
- The scratch directory is now created with
  `mktemp -d "${TMPDIR:-/tmp}/gitlore-repair.XXXXXX"`, dropping the
  `git -C "$tierpath" rev-parse --absolute-git-dir` lookup and its now-unused
  `gitdir` local. The lookup existed only to build the old in-gitdir mktemp
  target; nothing else in the function read it, so removing it drops no other
  behaviour. The `mktemp` failure arm keeps its current message-free walk-back
  unchanged (its message and remedy are slice 1.2/2's).
- The function comment's clause "a scratch copy inside the tier's gitdir"
  becomes "a scratch copy outside the repository".

**Tests:**
- `scripts/run-bats.sh tests/merge_memory.bats --filter "a repair's scratch directory lives under TMPDIR"`
  → `bats: 1 passed, 0 failed`.
- `scripts/run-bats.sh tests/merge_memory.bats` (whole file) → `bats: 40 passed, 0 failed`.
- `grep -rln "gitlore-repair" tests/` → only `tests/merge_memory.bats`, already
  run above.
- `gitlore_repair_index`'s rename-within-directory and `hash-object -w`: no
  separate check needed — the same 40-test run exercises every repair case in
  the file (adoption, unrepairable-arrival, and retry-refusal tests all repair
  from the new scratch location) and all pass.
- `shellcheck scripts/lib/resolve.sh tests/merge_memory.bats` → clean.

**Commit:** `refactor: Item 1.2/1 — the repair's scratch copy lives under TMPDIR`,
staged by explicit path (`tests/merge_memory.bats scripts/lib/resolve.sh
plans/tier-arrival-review-minors/reports/item-1-2-s1-red.md
plans/tier-arrival-review-minors/reports/item-1-2-s1-test-review.md
plans/tier-arrival-review-minors/reports/item-1-2-s1-green.md`). Tree clean
afterwards.
