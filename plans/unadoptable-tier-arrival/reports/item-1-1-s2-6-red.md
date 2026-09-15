# RED: Item 1.1 slices 2–6

**Mode**: RED, batched. **Scope**: `tests/git_hook_pre_commit.bats`,
`tests/commit_memory.bats`, `tests/index_compose.bats`. `scripts/` untouched at
the end (`git diff --quiet HEAD -- scripts` holds).

All five slices' tests are **guards**: each passes on the first run against the
SUT as slice 1's code review left it (7f143cf, 9a7e277), matching that review's
"Notes for later slices" prediction. Every guard's mutation-red is recorded
below via the scratch-and-restore procedure (in-place mutation of
`scripts/lib/resolve.sh` or `scripts/lib/index-compose.sh`, run the filtered
test, restore with `git checkout HEAD -- <file>`, confirm
`git diff --quiet HEAD -- <file>`).

## Slice 2 — `tests/git_hook_pre_commit.bats`

**Test**: "a dirty carrier with a duplicate pointer aborts the commit and
restamps the approval"

**Verdict**: guard. First run: `1 passed, 0 failed`.

**Mutation-red**: removed `touch "$msgfile"` from the abort branch (the
statement immediately before `return 1` at `resolve.sh`'s rc-1 abort arm,
mirroring slice 1's own already-committed abort branch one case up). Output:

```
not ok 1 a dirty carrier with a duplicate pointer aborts the commit and restamps the approval
# (in test file tests/git_hook_pre_commit.bats, line 418)
#   `[ "$(_gitlore_mtime "$msgfile")" -gt "$stamp_epoch" ]' failed
```

Restored; `git diff --quiet HEAD -- scripts/lib/resolve.sh` confirmed clean
before the next mutation.

## Slice 3 — `tests/commit_memory.bats`

**Test**: "a dirty root index with a welded line aborts the memory commit"

**Verdict**: guard. First run: `1 passed, 0 failed`.

**Mutation-red**: removed the root-attribution block entirely (the
`gitlore_compose_problems_in "$mempath/MEMORY.md"` check and its
`git status --porcelain -- MEMORY.md` read), leaving only the tier loop —
"attribute only tier carriers" per the dispatch. Output:

```
not ok 1 a dirty root index with a welded line aborts the memory commit
# (in test file tests/commit_memory.bats, line 196)
#   `[ "$status" -eq 1 ]' failed
```

Restored; `git diff --quiet HEAD -- scripts/lib/resolve.sh` confirmed clean.

## Slice 4 — `tests/commit_memory.bats`

**Tests**: "a carrier defect in a clean tier commits and reports" and "a tier
dirty only outside its carrier commits and reports"

**Verdict**: both guards. First runs: `1 passed, 0 failed` each.

**Mutation-red, variant "without the `-- MEMORY.md` pathspec"**: both
`git status --porcelain -- MEMORY.md` calls (root and tier) changed to
`git status --porcelain` (whole-tree). Result:
- "a tier dirty only outside its carrier commits and reports" → red:
  `[ "$status" -eq 0 ]' failed` (the tier's untracked `extra.md` now reads the
  whole tier as dirty, so the carrier defect wrongly aborts the commit).
- "a carrier defect in a clean tier commits and reports" → stayed green: the
  fixture has no dirt outside `MEMORY.md`, so this variant cannot discriminate
  it — expected, since the pathspec only matters when non-carrier dirt exists.

Restored; `git diff --quiet HEAD -- scripts/lib/resolve.sh` confirmed clean.

**Mutation-red, variant "or not at all"**: both dirtiness reads removed, `abort`
set unconditionally whenever `gitlore_compose_problems_in` matches (as if every
problem-bearing index were dirty). Result: "a carrier defect in a clean tier
commits and reports" → red:

```
not ok 1 a carrier defect in a clean tier commits and reports
# (in test file tests/commit_memory.bats, line 219)
#   `[ "$status" -eq 0 ]' failed
```

The second test reds the same way under this variant (a superset of the first).
Restored; `git diff --quiet HEAD -- scripts/lib/resolve.sh` confirmed clean.

## Slice 5 — `tests/commit_memory.bats`

**Test**: "a leftover root prefix commits and reports even when root is dirty"

**Verdict**: guard. First run: `1 passed, 0 failed`.

**Mutation-red**: the root-attribution `if` condition changed from
`printf '%s\n' "$compose_result" | gitlore_compose_problems_in "$mempath/MEMORY.md" >/dev/null`
to `[ -n "$compose_result" ]` — a green that aborts on any root refusal,
including a rule-3 problem the helper never attributes. Output:

```
not ok 1 a leftover root prefix commits and reports even when root is dirty
# (in test file tests/commit_memory.bats, line 258)
#   `[ "$status" -eq 0 ]' failed
```

Restored; `git diff --quiet HEAD -- scripts/lib/resolve.sh` confirmed clean.

## Slice 6 — `tests/index_compose.bats`

**Test**: "problem attribution matches the exact file prefix"

**Verdict**: guard. First run: `1 passed, 0 failed`.

**Mutation-red, `grep "^$file: "` implementation**:
`gitlore_compose_problems_in` rewritten to `grep "^$file: "`. The decoy
`my memXd/MEMORY.md` line is matched by the regex `.` in `my mem.d`, so the
`my mem.d/MEMORY.md` query returns two lines instead of one. Output:

```
not ok 1 problem attribution matches the exact file prefix
# (in test file tests/index_compose.bats, line 1122)
#   `[ "$output" = "my mem.d/MEMORY.md: duplicate pointer path dup.md" ]' failed
```

Restored; `git diff --quiet HEAD -- scripts/lib/index-compose.sh` confirmed
clean.

**Mutation-red, word-splitting implementation**: rewritten to
`set -- $line; [ "$1" = "$file:" ] || continue` (unquoted `set --`). The space
in `my mem.d/...` splits `$line` and `$file` alike, so `$1` never equals the
multi-word `"$file:"`, and every case fails. Output:

```
not ok 1 problem attribution matches the exact file prefix
# (in test file tests/index_compose.bats, line 1117)
#   `[ "$status" -eq 0 ]' failed
```

Restored; `git diff --quiet HEAD -- scripts/lib/index-compose.sh` confirmed
clean.

## Whole-file runs (after every mutation was restored)

- `tests/git_hook_pre_commit.bats` — 20 passed, 0 failed.
- `tests/commit_memory.bats` — 33 passed, 0 failed.
- `tests/index_compose.bats` — 66 passed, 0 failed.

## shellcheck

`shellcheck tests/git_hook_pre_commit.bats tests/commit_memory.bats tests/index_compose.bats`
— clean, no output.

## Final state

`git diff --quiet HEAD -- scripts` holds.
`git status --porcelain -- tests scripts` shows only the three test files
modified:

```
 M tests/commit_memory.bats
 M tests/git_hook_pre_commit.bats
 M tests/index_compose.bats
```

No commit made.
