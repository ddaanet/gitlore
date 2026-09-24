# Item 1.1, slice 2 — RED

`tests/cc_hook_memory_commit_batch.bats`, one new test: `a fix after an
aborting index does not commit under the old approval`. Nothing else in the
file changed; nothing committed.

## Mechanical check

`bash scripts/run-bats.sh tests/cc_hook_memory_commit_batch.bats`, foreground:
**11 passed, 1 failed**. The failure is an assertion, not a missing command or
a bats error.

```
not ok 8 a fix after an aborting index does not commit under the old approval
# (in test file tests/cc_hook_memory_commit_batch.bats, line 191)
#   `[ "$(git -C memory rev-parse HEAD)" = "$head_before" ]' failed
```

Line 191 is the second-batch HEAD check, the assertion the dispatch named as
the expected first failure. On unchanged code the sequence is: welded-index
abort (restamps the approval to now), the test backdates the approval and
fixes the weld in `MEMORY.md`, then the second batch — unmodified
`memory-commit-batch.sh` still calls `commit-memory.sh -F "$msgfile"`, which
rewrites the message file from its own contents and mints a fresh approval by
construction, so `gitlore_sync_memory_to_live` proceeds, composes the now-clean
index, and commits. `HEAD` moves, reproducing the defect the slice closes.

Every pre-existing test in the file (10 others, now 11 total minus the new
one) still passes, including the two the dispatch named to stay green
unchanged: `a locked repo keeps both IPC files so the next batch retries
transparently` and `a refusal that needs a fix keeps both IPC files and hands
the agent the fix`.

`just lint` → `lint-shell: 210 files clean (209 cached)`.

## Notes for GREEN

- The test's `**<Kind>` template-marker check is done by asserting the full
  clause text (`reference/memory-approval-clause.txt`) is a substring of
  `additionalContext`, the same technique the existing "pending-summary
  message interpolates the canonical memory-approval clause" test uses — the
  clause body itself carries the `**New <tier>/<slug>:**` etc. markers, so
  matching the whole block subsumes the marker check named in the dispatch.
- The exact `systemMessage` string asserted is
  `gitlore: memory commit deferred — the approved summary no longer covers the
  store, approval needed again` (em dash, no trailing period) — copied
  verbatim from `design.md`'s Design point 3.
- Third-batch commit assertions (HEAD advanced, both IPC files gone) are
  written but unreached at RED, since the test aborts at line 191 first; they
  will exercise once GREEN lands.
