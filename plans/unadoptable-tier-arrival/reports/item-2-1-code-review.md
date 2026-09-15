# Review: Item 2.1 GREEN — `gitlore_repair_index`

**Scope**: commit `b0e19de`, `scripts/lib/index-compose.sh` only:
`gitlore_repair_index`, `gitlore_weld_tail`, the refactored
`gitlore_welded_path`, and the new comment sentence in
`gitlore_compose_check_index`. Tests are out of scope. **Date**: 2026-09-14
**Mode**: review + fix (nothing committed)

## Summary

The rules, the report strings, the survivor rule and the write-failure contract
are all implemented correctly. The tests cover them, and a mutation run confirms
it. Two defects outside the tests' reach were fixed:

- **Quadratic subprocesses.** The duplicate pass took 31 seconds on a 200-bullet
  index.
- **bash 3.2 abort.** Empty-array expansions abort the take under `set -u` on
  bash before 4.4, which is the macOS target.

The refactor of `gitlore_welded_path` also added one subshell to every bullet
the check reads. That is fixed too. Three smaller items are fixed as well.

**Overall Assessment**: Ready

## Issues Found

### Critical Issues

1. **Empty-array expansions abort under `set -u` on bash 3.2**
   - Location: `gitlore_repair_index`, pass 2 assembly
     `p2=("${pre[@]}" "${reg[@]}" "${stray[@]}" "${trail[@]}")`, pass 3
     `p3=("${pre2[@]}" "${keep[@]}" "${trail2[@]}")`, and
     `printf '%s\n' "${p1[@]}"` on an empty file.
   - Problem: bash before 4.4 treats `"${a[@]}"` of an array with no elements as
     an unbound variable under `set -u`. That error is fatal to the
     non-interactive shell, whatever `||` context surrounds the call. `stray` is
     empty in every repair without an interleaved line. `pre` is empty whenever
     line 1 is a bullet. `scripts/merge-memory.sh` and every entry point run
     `set -euo pipefail`, and Item 2.2 calls this from the take. On macOS, the
     first duplicate or weld repair would kill `merge-memory.sh` mid-take. Linux
     bash 5.2 does not reproduce this, so the suite cannot see it.
   - Fix: the passes were restructured so no possibly-empty array is expanded:
     - An empty `p1` returns 0 before the region read.
     - A bulletless result returns 0, since with no bullet there is nothing to
       repair.
     - Stray lines are appended into `p2` right after the last bullet, behind a
       `${#stray[@]} -gt 0` guard.
     - Pass 3 works on `p2` directly: every bullet lies inside the region, so
       the pre/region/trailer split was redundant.
     - `p3` always holds a bullet.

     A comment at the guard names the bash 4.4 boundary.
   - Grounding: not reproduced locally (no bash 3.2 on this box). This is the
     documented bash-4.4 NEWS change for `${a[@]}` under `nounset`.
   - **Status**: FIXED

### Major Issues

1. **The duplicate pass forks quadratically: 31 s on a 200-bullet index**
   - Location: `gitlore_repair_index`, the duplicate grouping loop.
   - Problem: for each distinct path, the inner loop re-ran
     `path=$(gitlore_bullet_path …)` on every later line (one subshell each).
     Each outer step also ran `grep` against a growing `seenpaths`. That is
     about m²/2 subshells: 31.3 s measured on a 200-bullet index with one
     duplicate (probe below). Item 2.2 runs this inside a take.
   - Fix: compute each line's path once into `paths[]` (m subshells). Group by
     in-shell string comparison, and mark grouped indices so each group is
     scanned once. `grep` against the pin runs only for members of a group of
     two or more. The same probe now takes 0.64 s.
   - **Status**: FIXED

2. **The `gitlore_welded_path` refactor added a subshell per bullet to every
   check**
   - Location: `gitlore_welded_path`.
   - Problem: `second=$(gitlore_weld_tail "$line")` nests a second subshell
     inside the check's own `welded=$(gitlore_welded_path …)`, and it runs for
     every bullet, welded or not. `gitlore_compose_check_index` on the
     200-bullet probe went from 1.24 s before `b0e19de` to 1.86 s. The check
     runs on every compose, for root and each carrier. Behaviour was otherwise
     preserved: capture only strips trailing newlines, which a read line cannot
     hold, and the status propagates unchanged.
   - Fix: first screen with `gitlore_weld_tail "$line" >/dev/null`. A redirected
     function call runs in the current shell, so no subshell. Capture only when
     a weld is present. The check is back to 1.19 s. The repair's weld loop
     screens the same way before calling `gitlore_welded_path`, so a non-welded
     line costs no subshell.
   - **Status**: FIXED

### Minor Issues

1. **Survivor rule computed with redundant known/lacked flags**
   - Location: duplicate pass, `anyknown`/`anylacked`.
   - Note: "the first line the pin lacks, else the first" gives the same
     survivor in all three cases. When every line is lacked, the first lacked
     line is the first line, so a mixed-group flag is unnecessary. The fix
     replaces two scans and two flags with one scan that defaults to `group[0]`.
     Mutation-verified that the rule is still pinned (below).
   - **Status**: FIXED

2. **The rewrite left `<file>` at mode 0600**
   - Location: scratch creation.
   - Note: `mktemp` creates 0600, and the `mv` carried that mode onto `<file>`.
     The rewrite is supposed to happen in place. The fix adds
     `cp -p -- "$file" "$scratch"` after `mktemp`, with the same
     `rm -f; return 1` arm, so the truncating write keeps `<file>`'s mode.
     Probed: a 0644 file stays 0644. The write-failure paths are unchanged:
     `mktemp` failing in a read-only directory still returns 1 with nothing
     created.
   - **Status**: FIXED

3. **Blank lines relied on an accident to stay out of duplicate grouping**
   - Location: old pass 3, `path=$(gitlore_bullet_path "${reg2[i]}")` on a blank
     line inside the region.
   - Note: the bare assignment failed, which is an errexit hole if the caller
     ever runs it outside a `||`/`if` context. The empty `path` was then skipped
     only because `seenpaths` starts with an empty line that `grep -qxF ''`
     matches. Now `|| path=""` sets it explicitly and `[ -n "$path" ]` gates
     grouping.
   - **Status**: FIXED

4. **Redeclared locals inside branches and loops**
   - Location: `local i=0 idx` twice, `local -a group=()` and `local j=$i`
     inside the loop.
   - Note: the restructure removed these. Each local is declared once.
   - **Status**: FIXED

## Fixes Applied

- `scripts/lib/index-compose.sh` `gitlore_welded_path`: in-shell screen before
  the capture, with a comment giving the reason.
- `gitlore_repair_index`, weld loop: the same in-shell screen ahead of
  `gitlore_welded_path`.
- `gitlore_repair_index`: early return on an empty file or a bulletless result,
  with a comment on the bash 3.2 `set -u` hazard.
- `gitlore_repair_index`, interleaved pass: a single pass using rule 4's test
  verbatim (`n > first`, `n < last`, non-blank, not a bullet). Strays are
  appended after the last bullet behind a count guard.
- `gitlore_repair_index`, duplicate pass: operates on `p2`, with paths computed
  once, grouping in-shell, a single-scan survivor and an explicit empty path for
  non-bullets.
- `gitlore_repair_index`, scratch: `cp -p` to keep the file mode.

Net: 76 insertions, 98 deletions.

## Verification

- `scripts/run-bats.sh tests/index_compose.bats`: 80 passed before the fixes and
  80 passed after, the latter re-run after the final edit.
- `scripts/run-bats.sh tests/commit_memory.bats`: 35 passed, 0 failed.
- `scripts/run-bats.sh tests/merge_memory.bats`: 23 passed, 0 failed.
- `shellcheck scripts/lib/index-compose.sh`: clean.
- **Timing probe:** 200 bullets plus one duplicate, a preamble and a trailer.

  | | Before | After |
  |---|---|---|
  | Repair | 31.3 s | 0.64 s |
  | Check (1.24 s before `b0e19de`) | 1.86 s | 1.19 s |

- **Combined probe:** run under `bash -euc`, in a tier dir with a space and a
  file named `b [*].md`. The index held:
  - a three-bullet weld whose third path duplicates a later line;
  - a stray `stray *[x]` and a stray `-e not a bullet`;
  - a later duplicate of the first bullet;
  - an unterminated trailer.

  Result:
  - Six report lines, in rule order.
  - Every glob and space byte kept.
  - The file is still unterminated.
  - `gitlore_compose_check_index` prints nothing.
  - An empty file returns 0.
  - No scratch file left in the directory.
- **Mutated-SUT run:** saved the SUT, then replaced the pin test with `if false`
  so the first line always survives, then ran the five `differing duplicate`
  tests, then restored.
  - "keeps the line the pin lacks" and "of several lines the pin lacks, the
    first survives" went red on their output assertions.
  - The three rows where the first line is correct stayed green, as they should.
  - Restore confirmed with `cmp` against the saved copy.

## Conformance to Item 2.1 (post-fix)

| Rule | Status | Evidence |
|---|---|---|
| Order: welds, then interleaved, then duplicates | Satisfied | three sequential passes; the report accumulates in that order |
| Weld split at `gitlore_welded_path`'s `- [`, only when the path is a file under `<tier-dir>`, repeated | Satisfied | the loop re-tests `cur=$second`; `[ -f "$tierdir/$wpath" ]` is quoted; `${cur%"$second"}` is literal |
| Interleaved non-blank non-bullet lines moved in order to the start of the trailer; blanks stay | Satisfied | same test as rule 4 in the check; appended at `n == last` |
| Duplicate survivor rule | Satisfied | the first lacked line, else `group[0]`; survives at its own index |
| Other lines keep bytes and order | Satisfied | array elements copied verbatim; the termination state is restored on write |
| `\|\| [ -n "$line" ]` on every read, pin included | Satisfied | both `while read` loops |
| Scratch beside `<file>`, rename only on edit | Satisfied | `mktemp "$dir/…"` after `[ -n "$report" ] \|\| return 0` |
| Exact report strings | Satisfied | the three literals match the runbook |
| rc 1 with the file unchanged and no scratch left when the write fails | Satisfied | `mktemp`, `cp`, `printf` and `mv` each return 1, with `rm -f` after creation; rename is atomic |
| Comment sentence in `gitlore_compose_check_index` | Satisfied | present; cites no plan |

**Agreement with the check:**
- **Split:** both halves of a split are bullets. The first keeps its link; the
  second passed `gitlore_bullet_path`. A split therefore cannot create an
  interleaved line.
- **Interleaved pass:** only moves lines. It cannot weld two lines, and it
  cannot add a bullet, so it cannot create a duplicate.
- **Duplicate pass:** runs after strays have left the region, so dropping a
  bullet cannot expose a non-blank non-bullet line. When a region-edge bullet is
  dropped, the lines outside it are blank or bullets.
- **Residual:** the check still reports a weld whose second path names no tier
  file. That is the designed unrepairable arm Item 2.2 handles.

**Pattern safety:**
- Every `grep` is `-qxF --` on a here-string, so a line starting with `-`, or
  containing `[` or `*`, matches literally.
- An empty pin gives a here-string of `"\n"`, which a bullet never equals.

## Refactoring Signals

- `REFACTOR-NEEDED: scripts/lib/index-compose.sh — 1058 lines against the 400-line cap (896 before b0e19de). The check, the repair and their parsing primitives (bullet_path, weld_tail, welded_path, index_region) form a cohesive unit that could leave the compose/write machinery.`

## Positive Observations

- Sharing `gitlore_weld_tail` means the repair splits exactly the shape the
  check flags, from one scan.
- Report lines print only after `mv` succeeds, so a failed write never describes
  an edit that did not land.
- Termination handling reuses `gitlore_compose_write`'s `tail -c 1 | wc -l`
  idiom.
- The scratch file is created only when `report` is non-empty, so a clean index
  keeps its inode (the test's `-ef`).

## Recommendations

- Item 2.2's tests on macOS are the only place the bash 3.2 hazard would show.
  `tests/bsd_portability.bats` cannot shadow a bash version. The phase gate on a
  macOS runner, if one exists, is where to confirm a repair take end to end.
