# Item 1.1, slice 2 — test review

`tests/cc_hook_memory_commit_batch.bats`, the one new test `a fix after an
aborting index does not commit under the old approval`. Reviewed, three fixes
applied, still red on the assertion the dispatch named. Nothing committed; the
only tracked change in the tree is `tests/cc_hook_memory_commit_batch.bats`.

## Mechanical check

`bash scripts/run-bats.sh tests/cc_hook_memory_commit_batch.bats`, foreground,
before any edit: **11 passed, 1 failed**.

```
not ok 8 a fix after an aborting index does not commit under the old approval
# (in test file tests/cc_hook_memory_commit_batch.bats, line 191)
#   `[ "$(git -C memory rev-parse HEAD)" = "$head_before" ]' failed
```

The failure is an assertion, not a missing command and not a bats error, and it
is the second-batch HEAD check the dispatch named as the expected first failure.
This reproduces the RED report exactly. The two tests that must stay green
unchanged — `a locked repo keeps both IPC files so the next batch retries
transparently` and `a refusal that needs a fix keeps both IPC files and hands
the agent the fix` — are among the 11 passing.

## Findings

### 1. MAJOR — the second batch checked the approval file's existence, not that
### it was left alone

`[ -f "$msgfile" ]` was the whole assertion on the preserved approval. Two
distinct failures pass it.

A restamp is the load-bearing one. Every abort arm in
`scripts/lib/resolve-sync-memory.sh` restamps with a bare `touch "$msgfile"`
(lines 96, 122, 157, 165, 180, 186 — the welded-index abort this test's first
batch drives is the one at 186). If GREEN's new freshness branch restamps the
same way, the approval reads fresh again and *the batch after this one commits
under the old summary* — the defect the slice closes, moved one batch later.
The test could not see it, because its own third batch rewrites the file before
running. The refusal the design routes to is
`resolve-sync-memory.sh:49-54`, which `return 1`s ahead of the first restamp arm
(the arms begin after the comment at line 67), so a no-restamp guard is
satisfiable by the implementation the design specifies.

An emptied or rewritten file is the second: design point 3 makes the stale file
the text the agent re-presents, so its bytes are part of the contract.

Fixed with the idiom slice 1 settled on (`tests/commit_memory.bats:87-104`) — a
byte-exact copy plus a marker one whole second before the run, since mtime is
second-granular:

```
  cp "$msgfile" "$BATS_TEST_TMPDIR/approval.before"
  : > "$TMP_REPO/before-second-batch"
  sleep 1
  …
  cmp -s "$msgfile" "$BATS_TEST_TMPDIR/approval.before"
  [ ! "$msgfile" -nt "$TMP_REPO/before-second-batch" ]
```

The marker is created after the `touch -t 200001010000` backdate, so the guard
holds today (2000 is not newer than now) and fires only on a restamp.

### 2. MAJOR — the third batch did not prove the commit was on the rewritten
### approval

`[ "$(git -C memory rev-parse HEAD)" != "$head_before" ]` is equally true of a
commit made under the *original* approval, which is the thing the test exists to
forbid. Added the subject assertion, matching the technique the file's own
success test uses (line 72):

```
  [ "$(git -C memory log -1 --pretty=%s)" = "memory: record a and b (fixed)" ]
```

### 3. MINOR — the second batch did not state that the fix survived

A GREEN that reached a clean tree by discarding the edit left HEAD unchanged and
passed. The third batch catches it transitively (clean memory means no commit,
so HEAD would not move), but the direct statement is one line and is the shape
the locked-repo test already uses:

```
  [ -n "$(git -C memory status --porcelain)" ]   # and the fix was not discarded
```

Also set `CLAUDECODE=1` on the third batch, as on the other two: with three
batches in one body, an unexplained arm difference is noise, and on a GREEN
failure it surfaces the agent-arm text rather than the user-arm one.

### 4. Checked, no defect

- **Backdate ordering (dispatch specific 1).** The welded-index abort does
  restamp — `resolve-sync-memory.sh:186` `touch "$msgfile"` on the
  `abort_files` arm — so the backdate is necessary, not decorative, and it is
  applied after that batch and before the `MEMORY.md` rewrite. `2000-01-01`
  puts the approval strictly older than everything `find "$mempath" -type f`
  walks (`gitlore_commit_msg_freshness`, `scripts/lib/util.sh:290`), which the
  approval file itself sits outside of, so the `>=` compare answers `no`
  regardless of the rewrite's own second. `touch -t` is BSD-portable.
- **Same-output pairing and a satisfiable negative (specific 2).** Both
  `*"no longer covers"*` and `!= *"retries by itself"*` read the same `$agent`
  capture from the second batch. `retries by itself` occurs in exactly one
  shipped string — `scripts/cc-hooks/memory-commit-batch.sh:119`, the existing
  deferred branch's `additionalContext` — and in neither the design's new
  `systemMessage` nor `reference/memory-approval-clause.txt`, so the new branch
  can satisfy it. Verified by grepping the tree, not by reading the design.
  The positive is discriminating in the other direction: the existing deferred
  text does not contain `no longer covers`.
- **Third-batch freshness (specific 4).** The approval rewrite is separated from
  the `MEMORY.md` fix by an entire batch run, and the compare is `>=`, so
  same-second is moot here anyway. The second batch writes nothing into
  `memory/` on the freshness-refusal path (it returns at
  `resolve-sync-memory.sh:54`, ahead of `gitlore_compose`), and freshness is
  read at line 34 *before* composition writes, so the third batch's own compose
  cannot outdate the approval it is about to commit on.
- **Third batch is reachable and will commit.** Under unchanged code the second
  batch commits this exact repaired `MEMORY.md`, which is what the red
  assertion at line 201 reports — so the index checks accept the fixed file, and
  under GREEN the same store state is what the third batch meets. The
  third-batch assertions are unreached at RED but not unsatisfiable.
- **Exact `systemMessage` (dispatch, verbatim).** Byte-compared against
  `design.md:65`: identical, em dash `e2 80 94`, no trailing period. Exact
  equality is also what pins the design's "the script's reason is dropped on
  this branch".
- **Whole-clause substring (specific 5).** Kept. It is not over-pinning: the
  expectation is read from `reference/memory-approval-clause.txt` at test time,
  so it asserts interpolation rather than wording, and a clause edit moves both
  sides together. Same technique as the file's `pending-summary message
  interpolates the canonical memory-approval clause` test, and the clause body
  carries the `**New <tier>/<slug>:**` markers, so it subsumes the `**<Kind>`
  check the dispatch asked for. The clause is asserted on `additionalContext`
  only, which is right here — unlike the no-summary branch, this branch's
  `systemMessage` is the curt one-liner and carries no clause.
- **`.claude/rules/shell.md` (specific 6).** No `2>/dev/null` added; no bare
  top-level `! cmd` (the `[ ! "$msgfile" -nt … ]` is inside `[ ]`); every path
  quoted, including `$TMP_REPO` and `$BATS_TEST_TMPDIR`; no `read` loop; no
  whitespace splitting. `just lint` → `lint-shell: 210 files clean`.

## Final red run

`bash scripts/run-bats.sh tests/cc_hook_memory_commit_batch.bats` after the
fixes:

```
not ok 8 a fix after an aborting index does not commit under the old approval
# (in test file tests/cc_hook_memory_commit_batch.bats, line 201)
#   `[ "$(git -C memory rev-parse HEAD)" = "$head_before" ]' failed

bats: 11 passed, 1 failed
```

Same assertion, moved to line 201 by the added fixture lines. The 11
pre-existing tests still pass.
