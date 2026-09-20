# Split report — `tests/git_hook_pre_commit.bats`

## Partition

- `tests/git_hook_pre_commit.bats` — 275 lines, 12 tests. Invocation-path,
  leaked-env, worktree, off-pin-abort and carrier-compose-on-commit tests
  (original lines 1–282, minus the header/setup/teardown/HOOK lines moved to
  the helper).
- `tests/git_hook_pre_commit_index.bats` — 241 lines, 9 tests. The
  index/carrier-staleness group: `committed_stale_carrier_store` and its two
  dirty/clean cases, the half-landed-tier retry, and the two abort-and-restamp
  arms (duplicate pointer, welded line), plus the partial-compose-keeps-summary
  case (original lines 283–509).
- `tests/helpers/git-hook-pre-commit.bash` — new, 12 lines: `HOOK=` (with a
  `shellcheck disable=SC2034` since it's now used only by callers),
  `setup()` (`setup_tmp_repo` + `export CLAUDE_PLUGIN_ROOT`), `teardown()`.
  Shared because both resulting files use the hook path and the tmp-repo
  lifecycle.

Followed the hint boundary exactly (split at `committed_stale_carrier_store`,
line 303 of the original) rather than folding the two preceding carrier tests
("aborts on an off-pin tier", "composes the carrier before committing") into
the new file — the hint named the boundary and both files land comfortably
under 380 lines without moving them, so no deviation was needed.

`committed_stale_carrier_store` is used only within the new file (its two
callers are both there), so it stayed in that file, in its original position
above its first user, with the comment block that precedes it (originally the
"shared base for both dirty-scope cases below" comment, lines 283–302) moving
with it as the section's leading comment.

## References

`grep -rn 'git_hook_pre_commit\.bats' docs/design.md docs/decisions.md docs/references scripts tests skills agents justfile CLAUDE.md`
found one hit: `tests/helpers/triggers.bash:47`, naming the test "ignores
parent GIT_DIR/GIT_INDEX_FILE leaked by 'git commit'". That test stayed in
`tests/git_hook_pre_commit.bats` (now at line 143), so the reference is still
correct — left unchanged.

No other reference to the suite name or to a moved test's title was found
under `docs/`, `scripts/`, `tests/` (excluding the split files themselves),
`skills/`, `agents/`, `justfile`, or `CLAUDE.md`.

## Verification

1. Test names preserved:
   `diff <(grep '^@test' "$TMPDIR/git_hook_pre_commit.orig.bats" | sort) <(cat tests/git_hook_pre_commit.bats tests/git_hook_pre_commit_index.bats | grep -h '^@test' | sort)`
   → prints nothing.
2. No line lost:
   `diff <(sort "$TMPDIR/git_hook_pre_commit.orig.bats") <(cat tests/git_hook_pre_commit.bats tests/git_hook_pre_commit_index.bats tests/helpers/git-hook-pre-commit.bash | sort) | grep '^<'`
   → prints nothing (every header/setup/teardown/HOOK line the split
   deliberately consolidated into the helper reappears there, so the
   line-multiset comparison balances with no `<`-only leftovers).
3. `wc -l`:
   - `tests/git_hook_pre_commit.bats`: 275
   - `tests/git_hook_pre_commit_index.bats`: 241
   - `tests/helpers/git-hook-pre-commit.bash`: 12
4. `scripts/run-bats.sh tests/git_hook_pre_commit.bats tests/git_hook_pre_commit_index.bats`
   → `bats: 21 passed, 0 failed`. Original `@test` count:
   `grep -c '^@test' "$TMPDIR/git_hook_pre_commit.orig.bats"` = 21. Match.
5. `just lint` — deferred to the end of the batch (all three suites), per the
   dispatch.

Step 6 (whole-suite `just test-unit`) intentionally not run — left to the
main session per the brief.
