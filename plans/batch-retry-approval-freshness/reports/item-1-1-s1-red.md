# Item 1.1, slice 1 — RED report

`tests/commit_memory.bats`, two new tests added after "refuses dirty memory
with no summary, leaving it uncommitted" and before "-m commits dirty memory
…". Ran with `bash scripts/run-bats.sh tests/commit_memory.bats`: 16 pass
(every pre-existing test), 2 fail — both on the assertion named in the
dispatch, not on a missing command or a bats error.

## `bare invocation commits on a fresh approval file and consumes it`

Failed assertion line: `[ "$status" -eq 0 ]` (tests/commit_memory.bats:63).

```
not ok 6 bare invocation commits on a fresh approval file and consumes it
# (in test file tests/commit_memory.bats, line 63)
#   `[ "$status" -eq 0 ]' failed
```

Current `commit-memory.sh` treats bare (`have_summary=0`) as a refusal
unconditionally on dirty memory, so `status` is 1 regardless of the approval
file's freshness — matches the design doc's "bare refuses everything today".

## `bare invocation refuses a stale approval file and leaves it`

Failed assertion line: `[[ "${output}${stderr}" == *"no approved commit summary"* ]]`
(tests/commit_memory.bats:86).

```
not ok 7 bare invocation refuses a stale approval file and leaves it
# (in test file tests/commit_memory.bats, line 86)
#   `[[ "${output}${stderr}" == *"no approved commit summary"* ]]' failed
```

Current code emits the usage-era refusal ("commit-memory needs an approved
summary… Pass it with -m …"), which contains `-m` but not the sync's own
"no approved commit summary" wording — the discriminating negative the
dispatch called out.

`just lint` is clean (`lint-shell: 210 files clean`). Nothing committed.
