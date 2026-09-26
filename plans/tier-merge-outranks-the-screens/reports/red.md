# RED — tier mid-merge outranks the summary screens

Touched only `tests/cc_hook_memory_commit_batch.bats` and
`tests/commit_memory_approval.bats`; both now `load helpers/tier-fixtures`.
No production code changed.

## Pass/fail counts

- `tests/cc_hook_memory_commit_batch.bats`: 15 passed, 2 failed (17 total; 15
  pre-existing tests still pass).
- `tests/commit_memory_approval.bats`: 7 passed, 2 failed (9 total; 7
  pre-existing tests still pass).

Run: `./scripts/run-bats.sh tests/cc_hook_memory_commit_batch.bats tests/commit_memory_approval.bats`

## Test 1 — "a tier's prepared merge hands over the merge directive, not a re-approval request"

File: `tests/cc_hook_memory_commit_batch.bats`

Failing assertion:
```
[[ "$agent" == *"memory merge prepared"* ]]
```

Wrong message actually emitted by the second batch (verbatim
`additionalContext`, captured from the identical fixture during verification):

```
gitlore: the approved summary at /tmp/claude-1000/gitlore-test.PL6MzA/.claude/gitlore-memory-message no longer covers the memory store. Present it to the user again as a markdown blockquote (`> …`) rather than a code fence, amended for what changed, and once they approve write it to /tmp/claude-1000/gitlore-test.PL6MzA/.claude/gitlore-memory-message — the commit then completes on its own.

Before drafting the summary, invoke the `gitlore:memory-writing` skill and hold
every pending memory change against it: ...
```

`systemMessage` was `gitlore: memory commit deferred — the approved summary no
longer covers the store, approval needed again` — the exact re-approval line
the test asserts it must not be. The batch's post-run screen calls
`gitlore_store_mid_merge "$mempath"` (root only), misses the tier's own
`MERGE_HEAD`, falls to the freshness arm, and the tier merge's checkout (newer
mtimes inside `memory/ddaanet`) makes that arm fire — dropping `$out`, which
already carried the real merge directive.

## Test 2 — "a tier mid-merge with no approval is not met with a request for a summary"

File: `tests/cc_hook_memory_commit_batch.bats`

Failing assertion:
```
[[ "$agent" == *"memory merge prepared"* ]]
```

Wrong message actually emitted by the second batch (verbatim
`additionalContext`, same fixture, approval file removed before the run):

```
gitlore: a memory commit is pending, but no approved summary exists yet. Summarize the pending memory changes as a commit message, present it to the user as a markdown blockquote (`> …`) rather than a code fence, and once they approve write it to /tmp/claude-1000/gitlore-test.bglldS/.claude/gitlore-memory-message. The commit then completes on its own — do not re-trigger it.

Before drafting the summary, invoke the `gitlore:memory-writing` skill and hold
every pending memory change against it: ...
```

`systemMessage` was `gitlore: commit-memory is pending but no approved summary
exists yet at .../gitlore-memory-message. ...` — the pre-run "no approved
summary" screen, reached because it too checks `gitlore_store_mid_merge` on
the root only and reads `mid_merge=0` despite the tier holding a prepared
merge.

## Test 3 — "a tier mid-merge is answered with the merge directive, not a summary request"

File: `tests/commit_memory_approval.bats`

Failing assertion:
```
[[ "${output}${stderr}" == *"memory merge prepared"* ]]
```

Wrong message actually emitted by the bare second call (verbatim stderr,
captured from the identical fixture during verification):

```
gitlore: memory is dirty; commit-memory needs an approved summary. Pass it with -m <summary> or -F - (heredoc).
```

`commit-memory.sh`'s own `gitlore_guard_stale_merge_state "$mempath"` at line
72 checks only the root store; with the tier mid-merge and no approval file on
disk, it passes silently and the run falls straight to the "Pass it with -m"
screen at line 75 instead of the merge directive.

## Test 4 — "the usage line names the bare invocation"

File: `tests/commit_memory_approval.bats`

Failing assertion:
```
[[ "${output}${stderr}" == *bare* ]]
```

Wrong message actually emitted (verbatim, `bash scripts/commit-memory.sh -x`,
status 2):

```
usage: commit-memory.sh [-m <summary> | -F <file> | -F -]
```

The usage string lists only the arg-driven forms and never says "bare".

## Verification notes

Each test was proved red by running the exact scenario against unchanged
production code (via disposable scratch `.bats` files, created and removed
outside the two permitted files, never left in the tree) before being written
into the two target suites, then confirmed again as part of the two-suite run
above. Every failure lands on the test's own content assertion — none failed
on a missing helper, a `load` error, or a fixture error. Every pre-existing
test in both files still passes.
