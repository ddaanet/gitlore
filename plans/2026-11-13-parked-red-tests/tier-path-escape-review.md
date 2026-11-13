# Review: tests/tier_path_escape.bats (red)

Verdict: **accepted with edits.** The file now has 12 tests: 10 red, 2 controls.
Unpatched checkout: `bats: 2 passed, 10 failed`. Patched copy:
`12 passed, 0 failed`. shellcheck is clean. The edits are listed below. Nothing
under scripts/ in the checkout was touched, and nothing ran against the
checkout's memory/.

## Step 1: each red test fails on the victim assertion (run)

The victim is always a temp path. For tests 1, 3-7 and 10 it is
`/tmp/claude-1000/victim-gitlore-test.*`, beside TMP_REPO. For test 2 it is
TMP_REPO itself (the temp parent) with origin `$TMP_REPO/.parent-remote.git`.
For tests 8-9 it is `$TMP_REPO/victim`. Setup succeeded in every test, and each
failure comes from the victim assertion:

| # | test | failing assertion | hostile state checked |
|---|---|---|---|
| 1 | `..` push | victim gained live at its HEAD | `.gitmodules` at HEAD and on `live` holds `path = ../../victim-…`; no gitlink |
| 2 | bare `..` push | parent's origin gained `refs/heads/live` | TMP_REPO had no origin before the test added one |
| 3 | `..` SessionStart | victim's pre-commit removed | same as 1 |
| 4 | symlink push | victim gained live | `s` is tracked as `120000` in the index and in HEAD; `memory/s/victim-…/.git` resolves; tier_paths prints `s/victim-…` |
| 5 | symlink SessionStart | pre-commit removed | same as 4 |
| 6 | newline push | victim gained live | `od -c` of the blob shows `path = inside\n../../victim-…` (escaped), and `config -z` returns a real LF in the value |
| 7 | newline SessionStart | pre-commit removed | same as 6 |
| 8 | NEW: newline gitlink push | victim gained live | index and HEAD hold `160000 … "in\n../victim"`; the fixture asserts it |
| 9 | NEW: newline gitlink SessionStart | pre-commit removed | same as 8 |
| 10 | compose | root MEMORY.md carries the victim line | `.gitlore-tiers` lists the climb; victim MEMORY.md has the bullet |

## Step 2: assertions

Every assertion checks only the victim's state: its refs, its origin's refs, its
hook file, its `gitlore.hooksDir`, and the root MEMORY.md content. None checks
wording, exit status or mechanism, so the tests hold under any fix that keeps
the victim untouched.

## Step 3: controls (run, mutation-checked)

- Control 11 (mounted tier listed and published) passes now. It fails under a
  mutant `gitlore_tier_paths` that returns nothing.
- Control 12 (conflicted gitlink). The fixture does
  `update-index --force-remove` and then `--index-info` with stages 1, 2 and 3.
  It passes now. Under a mutant that accepts only `160000 … 0<TAB>` (stage 0) it
  fails, and nothing else does. So the stages are really built, and a
  stage-0-only fix is caught.

## Edits to the test file (each verified)

1. **Coverage defect: the newline drop was unpinned.** Tests 6 and 7 use a
   newline path with no gitlink. The gitlink rule alone already makes them pass:
   run against the fix with both newline drops removed, they were green. So
   nothing pinned the "drop a path holding a newline" half of the fix. I added
   `hostile_store_newline_gitlink` and tests 8 and 9. They use the one newline
   shape git admits as a gitlink: index path `in<LF>../victim`, staged through
   `update-index -z --index-info` and committed. It splits into `in` and
   `../victim`, which reaches a repository in the parent's work tree. Results:
   red now, red under the fix with no newline drop, green under the full fix,
   and green with either one of the two drops (see below).
2. Control 12: the mid-body `[[ "$output" == *"ddaanet"* ]]` does not abort
   under macOS bash 3.2 (bats-gotchas row), and it did not show the stages. It
   is now
   `[[ … *" 1<TAB>ddaanet"*" 2<TAB>ddaanet"*" 3<TAB>ddaanet"* ]] || false`.
3. Test 10: `grep` `[ "$status" -ne 0 ]` became `-eq 1`. A missing MEMORY.md
   (exit 2) no longer passes vacuously.
4. Test 2: dropped the `git remote add … 2>/dev/null || git remote set-url`
   fallback. No fixture gives TMP_REPO an origin, as grep of the helpers and a
   run (`git remote -v` was empty) both show.
5. Lint (from the PostToolBatch hook): removed the unused `VICTIM_HEAD`.
   `assert_victim_gate_kept` used an `A && B || C` form (SC2015), now split into
   two checks. The new fixture uses `$(…)` instead of `run`, which avoids
   SC2030/2031.

## Step 4: patched copy

The tree is `/tmp/claude/gitlore-fanout/paths-review/` (copies of scripts, tests
and plugin-dev; `PLUGIN_ROOT="${BATS_TEST_DIRNAME}/.."` in
tests/helpers/setup.bash). With the fix: **all 12 pass** (all 10 of the original
file passed before tests 8 and 9 were added).

This settles the probe's reasoning-only claim:
- The gitlink rule alone closes `..`, bare `..`, symlink and the gitlink-less
  newline route (tests 1-7 and 10 green under the fix with no newline drop).
- The gitlink rule alone does **not** close the newline gitlink shape (tests 8
  and 9 red under that variant). A newline drop closes it. Either drop on its
  own suffices, whether on the index path while building the gitlink set or on
  the `.gitmodules` value. But the set-side drop is required for safety if the
  set is newline-delimited: an index path `in\n../x` put into the set would
  otherwise make a `.gitmodules` entry `../x` match. So keep both.

## Step 5: exposed suites against the patched copy

`plugin-dev/run-bats.sh -j 2 tests/add_tier*.bats tests/merge_memory_tiers.bats tests/session_fetch_timeout.bats`:
- Unpatched copy (`paths-review-base/`): 91 passed, 0 failed.
- Patched copy, clean tree (`paths-review-fix2/`): **91 passed, 0 failed.**

A first patched run in `paths-review/` was contaminated by mutant swaps made
mid-run. It also came out 91/0, but it is superseded by fix2.

The `tests/` copied in includes other agents' in-progress edits to
`commit_pin_guard_yield.bats` and `release_fix_unresolvable.bats`. Those files
were not run.

## Step 6: bats-gotchas and portability

- No bare `! cmd`. `bats_require_minimum_version 1.5.0` is declared for
  `run --separate-stderr`.
- `assert_victim_not_published` uses negative `rev-parse` status checks, backed
  by a positive `for-each-ref` empty-output check on a remote that exists.
- Mid-body `[[ ]]` now carries `|| false`.
- `start_session` gives the hook no stdin payload (the hook does
  `payload=$(cat)`). That matches tests/cc_hook_session_start_relay.bats, and
  the cleanup runs (red reproduces). Low.
- Paths are always quoted. No word splitting, no GNU-only tools in the file.
- No bash 3.2 binary exists on this box, so 3.2 was not run. Every construct is
  one the existing function already uses (`$'\n'` in `${…#…}`, `read -d ''`,
  process substitution) or is a plain `case`.

## Implementer section: fix text used (scripts/lib/util-config.sh)

Run on git 2.47.3 / bash 5 / Linux. The header comment's sentence "Paths
containing a newline are out of scope by construction" becomes false under this
fix and should be restated: tiers are `.gitmodules` paths that are gitlinks in
the memory index at any stage, and a newline-holding path is dropped.

```bash
gitlore_tier_paths() {
  local mempath="$1" rec path gitlinks=$'\n'
  [ -f "$mempath/.gitmodules" ] || return 0
  # The gitlinks of the memory index, at any merge stage, newline-delimited.
  # An index path holding a newline is skipped: it would split into lines.
  # LC_ALL=C: a NUL-delimited `read`,
  # against the bash 5.0-5.3 multibyte `read -d ''` overshoot (BP#65).
  while IFS= LC_ALL=C read -r -d '' rec; do
    case "$rec" in 160000\ *) ;; *) continue ;; esac
    path="${rec#*$'\t'}"
    case "$path" in *$'\n'*) continue ;; esac
    gitlinks="$gitlinks$path"$'\n'
  done < <(git -C "$mempath" ls-files -s -z)
  while IFS= LC_ALL=C read -r -d '' rec; do
    path="${rec#*$'\n'}"
    case "$path" in *$'\n'*) continue ;; esac
    case "$gitlinks" in *$'\n'"$path"$'\n'*) printf '%s\n' "$path" ;; esac
  done < <(git config --file "$mempath/.gitmodules" -z --get-regexp '^submodule\..*\.path$')
  return 0
}
```

Notes:
- `"$path"` is quoted inside the `case` pattern, so glob characters in a path
  match literally.
- A conflicted path appears up to 3 times in the set. That is harmless.
- The fix drops paths silently. Whether a dropped entry should get a stderr
  notice (the probe suggested one) is a design choice the tests leave open.

**Hoisting.** `root_change_is_tier` (scripts/commit-memory.sh:56-77) calls
`gitlore_tier_paths` once per root status entry (line 182). It calls it again
once per link pointer per changed MEMORY.md line (line 73). The fix adds one
`git ls-files` fork to each call, next to the existing `git config` fork. That
doubles the forks per call but does not change how they scale, and a commit
touches tens of pointers at most. So hoisting is optional, not required by this
fix. If done, compute the list once: line 199 already does
`tiers=$(gitlore_tier_paths "$mempath")`, but it runs after the loop at line
182. That would also halve the existing cost.

Not covered: `gitlore_active_tiers` consumers that bypass the tier set
(SessionStart's `gitlore_active_tier_scopes`, session-diagnostics.sh:66). The
probe's out-of-scope items stand.
