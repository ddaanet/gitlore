# Item 1.2 slice 2 — RED

## Test

`tests/merge_memory.bats`: `a repair whose scratch directory cannot be made walks back and points upstream`, added after "a repair's scratch directory lives under TMPDIR, not the tier's gitdir" and before "a repair whose checkout follow fails walks back and keeps the repair".

Fixture: the :558 duplicate-pointer arrival, wired with a `mktemp` stub on `$fakebin`
(`case " $* " in *gitlore-repair.*) exit 1 ;; esac`, otherwise `exec`s the real `mktemp`),
scoped to the run via `PATH="$fakebin:$PATH"`.

## Command

```
scripts/run-bats.sh tests/merge_memory.bats --filter 'scratch directory cannot be made'
```

## Result: FAIL on assertion (confirmed RED)

```
not ok 1 a repair whose scratch directory cannot be made walks back and points upstream
# (in test file tests/merge_memory.bats, line 693)
#   `[[ "$stderr" == *"no scratch directory could be made"* ]]' failed
```

Premise verified before finalizing (temporary debug dump, removed): the stub fires and
`status` is already 1, so the failure is the first content assertion, not setup. Captured
stderr under today's code:

```
gitlore: nothing was recorded, and tier 'ddaanet' is back on the commit the memory store records; its local 'live' keeps what arrived. Fix the store, then run /gitlore:merge again.
```

This is the bare walk-back the `mktemp` arm still performs (no `could not be repaired`
line, no refusal header, no `Run /gitlore:merge again.` remedy, no carrier-problem body) —
exactly the gap Item 1.2 closes.

`shellcheck -x tests/merge_memory.bats` — clean.

No production code touched. No commit made.
