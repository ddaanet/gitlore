# Item 1.1 slice 4 — GREEN

Restored `scripts/lib/resolve.sh` to `HEAD` via
`git checkout HEAD -- scripts/lib/resolve.sh` (no hand retyping);
`git diff HEAD -- scripts/lib/resolve.sh` is empty, confirming the file is
byte-identical to `HEAD` — i.e. to the state `62258fa` left it in.

## Suite run

`scripts/run-bats.sh tests/commit_memory.bats tests/git_hook_pre_commit.bats`:

```
bats: 33 passed, 0 failed
```

Matches the test review's own restore-and-rerun probe exactly.

## Precommit gate

`just precommit` run in background (`run_in_background: true`); completion
notification arrived (exit code 0). Verified independently from the gate
sentinels, since the notification alone isn't the source of truth for a subagent
run:

```
scripts/lib/resolve.sh          mtime 1788855803
tests/commit_memory.bats        mtime 1788855407
tests/git_hook_pre_commit.bats  mtime 1788855410

.git/gitlore/gates/lint             mtime 1788855915  (postdates all three inputs)
.git/gitlore/gates/test-unit        mtime 1788856428  (postdates all three inputs)
.git/gitlore/gates/test-integration mtime 1788856482  (postdates all three inputs)
```

All three gated-input files predate their corresponding sentinel, so lint,
test-unit and test-integration are all valid for this tree — no fallback to the
sequential recipes was needed. `check-distribution`'s sentinel predates the
edits, but nothing in this slice touches distribution-gated inputs.

## Commit

`03fa5af98e4085ec1ac102224d3bc2edba7d0f94` —
`✅ Item 1.1/4 — the abort keeps the approval, and the user arm reads right`
(the `commit-msg` hook rewrote the `test:` prefix to the emoji, as expected).

Contains only `tests/commit_memory.bats` and `tests/git_hook_pre_commit.bats`
(141 insertions, 0 deletions, 0 files touching `scripts/`). Staged by name
(`git add tests/commit_memory.bats tests/git_hook_pre_commit.bats`), not `-A` or
`-a`. Body states the fix landed untested in `62258fa` and this commit supplies
the missing regression test, with no implementation diff.

The two report files under `plans/index-edit-propagation/reports/` are left
untracked, per scope — not committed here.

## Scope

Touched: `scripts/lib/resolve.sh` (restored to `HEAD`, net no-op),
`tests/commit_memory.bats`, `tests/git_hook_pre_commit.bats` (committed
unchanged from the reviewed RED state). Nothing else.
