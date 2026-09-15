# Item 1.2 slice 1 — test review

**Test:** `a repair's scratch directory lives under TMPDIR, not the tier's gitdir`
(`tests/merge_memory.bats`, now at :625).

**Verdict:** sound after fixes. Still red on an assertion; passes under the
intended move.

## 1. Mechanical

`scripts/run-bats.sh tests/merge_memory.bats --filter "a repair's scratch directory lives under TMPDIR"`
fails on an assertion, not an error, both before and after the fixes:

```
not ok 1 a repair's scratch directory lives under TMPDIR, not the tier's gitdir
# (in test file tests/merge_memory.bats, line 659)
#   `[ "$(grep -c -F -- "$gitdir/gitlore-repair." "$seen")" -eq 0 ]' failed
```

## 2. Wrong-reason hunting

- **Other `mktemp` users under `$TMPDIR`.** The prefixes are
  `gitlore-git.`, `gitlore-index-merge.`, `gitlore-merge-indexes.`,
  `gitlore-compose-down.`, `gitlore-tier-msg.`, `gitlore-merge-msg.`,
  `gitlore-tier-seed.`. None matches the glob `gitlore-repair.*`.
  `gitlore_repair_index`'s `.gitlore-repair-index.XXXXXX` is a dotfile inside
  the scratch directory, so neither glob reaches it. `tmp_env` starts empty
  for each test, so no stale directory can be counted.
- **`commit-tree` call count.** `scripts/lib/resolve.sh:2006` is the only
  `commit-tree` call in `scripts/` or `hooks/`, and it runs once per repair.
  Only one tier is repaired, so `seen` gets exactly one `ls` run. The probe
  confirmed "exactly one" holds after the move.
- **`TMPDIR` reaching the SUT.** No script assigns `TMPDIR`. Inside `run` it is
  a temporary exported assignment, so it reaches `merge-memory.sh` and its
  children. The stub bakes in `$tmp_env` at write time rather than reading
  `$TMPDIR` at run time, which makes the check stricter: a script that reset
  `TMPDIR`, or a `/tmp` hardcode, would fail the "one line under `$tmp_env`"
  assertion. The sandbox does not interfere. One Bash call in this box had
  `TMPDIR` unset, but the test sets its own `TMPDIR` for the command either
  way.
- **"The repair is adopted" was weak** *(fixed)*. The test only checked
  memory's gitlink equals tier HEAD, plus the root line appearing once. It now
  also asserts what the neighbouring adoption test (:558) pins:
  - HEAD's only parent is the arrival (`remote_sha`, now captured from
    `push_tier_fact` instead of discarded);
  - the subject is the repair subject;
  - `live` equals HEAD.
- **Stub interpolation.** `$gitdir`, `$tmp_env`, `$seen` and `$real_git` are
  expanded into double-quoted positions in the stub. Spaces are safe. A `"`,
  `$` or backtick in a path would break it, the same residual bound the
  neighbouring stubs at :415 and :596 accept. The fixture paths come from
  `mktemp` templates with no such characters. The stub is on `PATH` only for
  the command under test.
- **`2>/dev/null` in the stub** *(fixed)*. Failure is expected here: one of the
  two globs always matches nothing. The stub now says so inline, per
  `.claude/rules/shell.md`.
- **Comment density** *(fixed)*. Added a two-line header saying why the
  directory is observed at `commit-tree`: it is removed once the commit is
  built.

## 3. Probe

1. Saved a byte copy of `scripts/lib/resolve.sh`.
2. Changed `:1910` to `mktemp -d "${TMPDIR:-/tmp}/gitlore-repair.XXXXXX"`.
3. Ran the test: `bats: 1 passed, 0 failed`.
4. Restored the copy; `git diff --quiet scripts/` is clean.

## 4. Final state

- Red on the unchanged SUT (output above).
- `shellcheck tests/merge_memory.bats`: clean.
- Only `tests/merge_memory.bats` is modified. Nothing committed.
