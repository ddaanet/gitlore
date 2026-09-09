# Item 1.2 slice 1 — RED report

Mode: RED. SUT untouched — `git diff --exit-code scripts/` reports no diff.

## Files changed

- `tests/commit_memory.bats` — replaced
  `an off-pin compose refusal is reported and does not abort the commit` with
  `a tier moved off its pin aborts the commit`, asserting the new abort
  behaviour instead of the old pass-through-and-report behaviour.
- `tests/git_hook_pre_commit.bats` — added
  `the parent pre-commit hook aborts on an off-pin tier`, the same fixture
  through the hook entry point, asserting the unchanged gitlink and the
  unchanged carrier.

`git diff --stat`:
```
tests/commit_memory.bats       | 50 ++++++++++++++++++++++++++----------------
tests/git_hook_pre_commit.bats | 28 +++++++++++++++++++++++
2 files changed, 59 insertions(+), 19 deletions(-)
```

## Fixture

Item 1.1 slice 3's off-pin induction verbatim: `make_parent_with_memory`,
`make_tier_in_memory ddaanet`, `set_tier_manifest ddaanet`,
`seed_tier_bullet ddaanet shared.md "stale hook"`,
`seed_root_bullet "ddaanet/shared.md" "fresh hook"`, then
`git -C memory/ddaanet commit -q --allow-empty -m "moved outside /gitlore:merge"`,
never staged into memory's index — so `gitlore_compose_check_pins` reads
`:ddaanet` against the tier's moved HEAD and refuses, while memory itself is
dirty with a fresh approved summary, reaching the commit.

## Suite run

`scripts/run-bats.sh tests/commit_memory.bats tests/git_hook_pre_commit.bats`:
```
not ok 12 a tier moved off its pin aborts the commit
# (in test file tests/commit_memory.bats, line 184)
#   `[ "$status" -ne 0 ]' failed
not ok 30 the parent pre-commit hook aborts on an off-pin tier
# (in test file tests/git_hook_pre_commit.bats, line 241)
#   `[ "$status" -ne 0 ]' failed

bats: 32 passed, 2 failed
```

Both isolated with `bats -f` to confirm the failure is the test's own, not
interference from another case in the file:

**`a tier moved off its pin aborts the commit`**
(`tests/commit_memory.bats:162`):
```
1..1
not ok 1 a tier moved off its pin aborts the commit
# (in test file tests/commit_memory.bats, line 184)
#   `[ "$status" -ne 0 ]' failed
```
Assertion failed: `[ "$status" -ne 0 ]` at line 184. Against unchanged code,
`gitlore_sync_memory_to_live` still calls `gitlore_compose_check_pins` nowhere —
the commit proceeds to `gitlore_sync_tiers_to_live`, which stages the tier's
moved gitlink, and `bash "$CMD"` exits 0. The red is the commit having landed
with `:ddaanet` moved, exactly as the dispatch predicted, not a missing symbol
or a fixture that failed to reach the guard (`gitlore_compose_check_pins`
already exists at `scripts/lib/index-compose.sh:310` and is exercised elsewhere
in the suite).

**`the parent pre-commit hook aborts on an off-pin tier`**
(`tests/git_hook_pre_commit.bats:225`):
```
1..1
not ok 1 the parent pre-commit hook aborts on an off-pin tier
# (in test file tests/git_hook_pre_commit.bats, line 241)
#   `[ "$status" -ne 0 ]' failed
```
Same assertion, same cause, through `bash "$HOOK"` — the second entry point
sharing `gitlore_sync_memory_to_live` reaches the identical unguarded path and
exits 0.

## Lint

`shellcheck -s bash tests/commit_memory.bats tests/git_hook_pre_commit.bats` —
exit 0, no findings.

## Scope check

Only the two test files changed. `scripts/lib/resolve.sh` and every other file
under `scripts/` untouched. The replaced test
`an off-pin compose refusal is reported and does not abort the commit` is
deleted, not left alongside its replacement. Slice 2's manifest-refusal case,
slice 3's two user-arm cases, and the existing
`the rc-1 user arm does not tell a user to retry a commit that succeeded` are
all untouched — left for slice 3, per scope. Nothing committed; nothing staged
beyond the working-tree edits. `just precommit` and the whole suite were not
run, per instruction — only the two named suites, through `scripts/run-bats.sh`.
