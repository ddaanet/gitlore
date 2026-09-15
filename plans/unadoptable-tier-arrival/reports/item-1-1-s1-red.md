# Item 1.1 slice 1 — RED

## Scope

- Wrote `tests/commit_memory.bats`: "a dirty carrier with a duplicate pointer
  aborts the memory commit" (external contract, slice 1.1/1).
- Added an inert stub `gitlore_compose_problems_in` to
  `scripts/lib/index-compose.sh`, beside `gitlore_compose_check_index`: defined,
  returns 1, prints nothing. `gitlore_sync_memory_to_live` was not touched.

## Test

```
@test "a dirty carrier with a duplicate pointer aborts the memory commit" {
  make_parent_with_memory
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  git -C memory/ddaanet branch -f live
  seed_tier_bullet ddaanet shared.md "hook"
  seed_tier_bullet ddaanet shared.md "hook"
  seed_root_bullet "ddaanet/shared.md" "hook"

  head_before=$(git -C memory rev-parse HEAD)
  tier_head_before=$(git -C memory/ddaanet rev-parse HEAD)
  tier_live_before=$(git -C memory/ddaanet rev-parse live)

  CLAUDECODE=1 run --separate-stderr bash "$CMD" -m "memory: record the shared fact"
  [ "$status" -eq 1 ]
  [[ "${output}${stderr}" == *"memory/ddaanet/MEMORY.md: duplicate pointer path shared.md"* ]]
  [[ "${output}${stderr}" == *"aborted"* ]]
  [ -n "$(git -C memory/ddaanet status --porcelain -- MEMORY.md)" ]
  [ "$(git -C memory rev-parse HEAD)" = "$head_before" ]
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$tier_head_before" ]
  [ "$(git -C memory/ddaanet rev-parse live)" = "$tier_live_before" ]
}
```

A local `live` is created for the tier (`git -C memory/ddaanet branch -f live`,
at the mount's default-branch HEAD) precisely so the "tier's `live` is unmoved"
assertion has something to catch: without it, today's code has nothing to push
and the assertion would be vacuously true.

## Run

`scripts/run-bats.sh tests/commit_memory.bats --filter 'a dirty carrier with a duplicate pointer'`:

```
not ok 1 a dirty carrier with a duplicate pointer aborts the memory commit
# (in test file tests/commit_memory.bats, line 159)
#   `[ "$status" -eq 1 ]' failed

bats: 0 passed, 1 failed
```

**Which assertion failed:** the first one, `[ "$status" -eq 1 ]`. A probe run of
`commit-memory.sh -m` against the same fixture, outside bats, shows why: today's
rc-1 arm of `gitlore_sync_memory_to_live` is advisory rather than an abort, so
the commit proceeds and exits 0 even though the duplicate-pointer problem is
reported on stderr.

```
EXIT: 0
--- stdout ---
--- stderr ---
gitlore: tier composition refused — the memory indexes were left untouched:
memory/ddaanet/MEMORY.md: duplicate pointer path shared.md
gitlore: the commit went ahead with the memory indexes as they stand. Fix the problems above by hand — composition runs again at the next memory commit. This commit also stages each tier at the commit its worktree is on now.
```

The stderr already carries the exact problem line the test asserts on
(`memory/ddaanet/MEMORY.md: duplicate pointer path shared.md`), but not the word
"aborted" (that assertion is unreached — the run stops at the first failing
`[ … ]`), the exit status is 0 not 1, and the tier's carrier is left dirty going
into a commit that landed rather than one that was refused. This is a
behavioural gap (a wrong value / absent abort), not an `ImportError`,
`AttributeError`, or missing-symbol failure — no stub extension was needed
beyond the interface's inert placeholder.

## Full-file run

`scripts/run-bats.sh tests/commit_memory.bats` (no filter): 28 passed, 1 failed
(the new test above). No other test in the file was disturbed by the stub.

## Notes

Nothing committed — the uncommitted test and stub in the tree are this
dispatch's end state, per RED mode.
