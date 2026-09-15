# Item 1.1 / slice 1 — RED

**Test:** `an arrival the repair cannot fix beside a root duplicate reports both and the two-fix remedy` (`tests/merge_memory.bats`, after the test at :744).

**Command:** `scripts/run-bats.sh tests/merge_memory.bats --filter "beside a root duplicate reports both and the two-fix remedy"`

**Result:** FAILS on the new assertion (not a setup/harness error). The first two checks pass (`status -eq 1`, the `live:MEMORY.md:` carrier line), proving the fixture is sound; the third check — the new `gitlore: the root index could not take tier 'ddaanet''s lines:` header followed by the root's `memory/MEMORY.md: duplicate pointer path dup.md` line — fails because the unrepairable arm does not yet print it.

```
not ok 1 an arrival the repair cannot fix beside a root duplicate reports both and the two-fix remedy
# (in test file tests/merge_memory.bats, line 795)
#   `[[ "$stderr" == *"gitlore: the root index could not take tier 'ddaanet''s lines:"$'\n'"gitlore:   memory/MEMORY.md: duplicate pointer path dup.md"* ]]' failed
```

shellcheck on `tests/merge_memory.bats`: clean.
