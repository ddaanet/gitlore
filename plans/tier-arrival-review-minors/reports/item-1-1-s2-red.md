# Item 1.1 / slice 2 — RED

**Test:** `a repair whose commit build fails walks back and points upstream`
(`tests/merge_memory.bats`, after "a take repairs a duplicate pointer that
arrived and adopts the repair" at :558).

**Command:**
`scripts/run-bats.sh tests/merge_memory.bats --filter "commit build fails walks back and points upstream"`

**Result:** FAILS on the new assertion (not a setup/harness error). The premise
assertions pass first — the `commit-tree` stub is hit
(`shim refuses commit-tree` in stderr) and the existing
`building the repair commit failed.` line from `gitlore_adopt_repair_arrival`
prints — proving the fixture reaches the commit-build arm. The failing assertion
is the refusal header the arm does not yet print:

```
not ok 1 a repair whose commit build fails walks back and points upstream
# (in test file tests/merge_memory.bats, line 619)
#   `[[ "$stderr" == *"gitlore: the root index could not take tier 'ddaanet''s lines:"$'\n'"gitlore:   memory/ddaanet/MEMORY.md: duplicate pointer path a.md"* ]]' failed
```

Today's code falls into the shared `if [ -z "$repair" ]` block
(`scripts/lib/resolve.sh:1948-1950`) and calls `gitlore_adopt_walk_back_tier`
directly with an empty `$remedy`, so it never prints the refusal header or
`$composed`, and the walk-back's default remedy ("Fix the store, then run
/gitlore:merge again.") is used instead of "Run /gitlore:merge again." — the two
assertions after the header check (`Run /gitlore:merge again.` present,
`Fix the store` absent) would also fail today; bats stops at the first.

shellcheck on `tests/merge_memory.bats`: clean.

Nothing committed; scope was test-only (`scripts/` untouched).
