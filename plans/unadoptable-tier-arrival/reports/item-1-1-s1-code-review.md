# Review: Item 1.1 slice 1 — GREEN code review

**Scope**: commit `7f143cf`, `scripts/` only — `gitlore_compose_problems_in`
(`scripts/lib/index-compose.sh`) and the rc 1 arm of
`gitlore_sync_memory_to_live` (`scripts/lib/resolve.sh`). Tests out of scope.
**Date**: 2026-09-14 **Mode**: review + fix

## Summary

The helper matches its interface exactly: a literal, quoted `case` prefix match,
`|| [ -n "$line" ]` on the read, rc 0 only on a match. The arm follows Item
1.1's text: the `-- MEMORY.md` pathspec, tiers from `gitlore_tier_paths` with
the `.git` guard, both message arms, `touch "$msgfile"` and `return 1`. Two
defects are fixed. A failed `git status` read as a clean index, which lets the
commit through, and the comments were inaccurate. The dirtiness read is also
reordered so it happens only for an index that has a problem, as the item
specifies.

**Overall Assessment**: Ready

## Issues Found

### Critical Issues

None.

### Major Issues

1. **A failing `git status` reads as a clean index and the commit publishes the
   problem**
   - Location: `scripts/lib/resolve.sh`, rc 1 arm (both status reads)
   - Problem: each read was
     `[ -n "$(git -C … status --porcelain -- MEMORY.md)" ]`. When a command
     substitution inside a `[` argument fails, the failure is lost, and git's
     non-zero exit becomes "empty" = clean. This also happens under errexit. The
     pre-commit hook calls `gitlore_sync_memory_to_live "$mempath" || exit $?`,
     which turns errexit off for the whole function anyway (the existing comment
     above `gitlore_git -C "$tierpath" add -A` says the same). So a corrupt
     index or an unreadable worktree led to "report and commit". That is the one
     outcome K5 exists to prevent.
   - Fix: capture into `index_status` with an explicit
     `|| { touch "$msgfile"; return 1; }`. This is the same idiom
     `gitlore_sync_tiers_to_live` uses for its checked git calls, and git's own
     stderr carries the reason. A comment states why the check is explicit.
   - **Status**: FIXED

2. **Dirtiness was read for every index instead of per problem-bearing index**
   - Location: `scripts/lib/resolve.sh`, rc 1 arm
   - Problem: Item 1.1 says "reads, per problem-bearing index, whether that file
     is dirty". The code ran `git status` on root and on every materialized tier
     first, and only then checked for problems. That costs one git call per tier
     on every refusal. With fix 1 in place it also gets worse: a status failure
     in a tier with no problems would abort a commit that publishes nothing
     wrong.
   - Fix: check for a problem first
     (`… | gitlore_compose_problems_in … || continue` in the tier loop, and an
     `if` for root), then read status only for the matching index.
   - **Status**: FIXED

### Minor Issues

1. **Arm comment did not name which problems abort and which report, and used
   historical framing**
   - Location: `scripts/lib/resolve.sh`, rc 1 arm header comment
   - Note: Item 1.1 requires this comment to name what aborts and what reports.
     The old comment left out rules 2 and 3 entirely. Its phrase "a dirty index
     whose own carrier is unchanged" contradicts itself, since for a tier the
     index *is* the carrier; the intended case is a tier dirty only outside its
     carrier. It also ended "as before", which breaks the present-tense rule. It
     now says: rules 1, 4 and 6 (the kinds that name their file) abort in a
     dirty root index or tier carrier; the same problems in an unchanged index,
     including a tier dirty only outside its carrier, and rules 2 and 3 report.
   - **Status**: FIXED

2. **SC2310 comment was mislabelled and described a rejected alternative**
   - Location: `scripts/lib/resolve.sh`, the comment above `local abort=0`
   - Note: SC2310 warns that a function called in a condition runs with errexit
     *off*. The comment used the code for the opposite claim (a bare assignment
     aborting under errexit). It explained a road not taken rather than the code
     in place. The comment that replaces it explains the explicit status check
     from fix 1.
   - **Status**: FIXED

3. **Redundant `local tier`**
   - Location: `scripts/lib/resolve.sh`, rc 1 arm tier loop
   - Note: `tier` is already declared `local` by the stale-merge loop earlier in
     the same function. Folded away while restructuring.
   - **Status**: FIXED

## Fixes Applied

- `scripts/lib/resolve.sh` rc 1 arm header comment: now names the aborting
  problems (rules 1/4/6 in a dirty root index or tier carrier) and the reporting
  ones (the same in an unchanged index, a tier dirty only outside its carrier,
  rules 2 and 3). Dropped "as before".
- `scripts/lib/resolve.sh` rc 1 arm body: problem match first, then a checked
  `index_status=$(git -C … status --porcelain -- MEMORY.md) || { touch "$msgfile"; return 1; }`
  for root and for each tier. Removed the duplicate `local tier`. Replaced the
  mislabelled SC2310 comment with one explaining the explicit check.

Verification after the fix:
`shellcheck scripts/lib/resolve.sh scripts/lib/index-compose.sh` is clean, and
`scripts/run-bats.sh tests/commit_memory.bats` gives 29 passed, 0 failed.

## Mutated-SUT run

Mutation, made on the committed SUT before any fix: the tier loop checked
problems against `"$mempath/MEMORY.md"` instead of `"$mempath/$tier/MEMORY.md"`.
This is the plausible wrong implementation where only root's index is
attributed. Running
`scripts/run-bats.sh tests/commit_memory.bats --filter 'a dirty carrier with a duplicate pointer'`
went **red** (`[ "$status" -eq 1 ]` failed, line 161). The file was restored
with `git checkout HEAD -- scripts/lib/resolve.sh`, and
`git diff --quiet HEAD -- scripts/lib/resolve.sh` confirmed it before editing.

## Requirements Validation

| Requirement | Status | Evidence |
|-------------|--------|----------|
| K5 — abort on a problem in an index file the commit changes | Satisfied | rc 1 arm: helper match, then `status --porcelain -- MEMORY.md` per index |
| Tiers from `gitlore_tier_paths`, skip without `.git` | Satisfied | tier loop guards `[ -e "$mempath/$tier/.git" ]` |
| Root attribution = rules 1, 4, 6 | Satisfied | `gitlore_compose_check_index` prefixes `$file: `; rules 2/3 lines carry no prefix |
| Both arms' wording; user arm ends as rc 2's | Satisfied | abort text on both arms of `gitlore_say_for_agent_or_user` |
| `touch "$msgfile"`; return 1 | Satisfied | abort branch and both status-failure exits |
| Advisory text otherwise unchanged | Satisfied | report branch untouched |
| Comment names abort vs report | Satisfied (after fix) | arm header comment |
| Helper interface: literal prefix, rc 0/1 | Satisfied | quoted `case` pattern in `gitlore_compose_problems_in` |

## Notes for later slices (not tested here)

- Slice 3 (root weld), slice 4 (clean tier / tier dirty outside its carrier),
  slice 5 (rule 3 report-only) and slice 6 (helper exact prefix, spaces, decoy):
  reading the code, each should pass as written. The pathspec is present, rule 3
  lines have no prefix, and the helper's quoted `case` treats `.` and spaces
  literally.
- Slice 2 (pre-commit restamp): `touch "$msgfile"` sits on the abort branch and
  runs under the hook's suspended errexit, so the restamp happens.
- No slice covers the status-failure exit added by fix 1. It is a fail-closed
  path with git's own stderr as the message. A test could use a tier whose
  `.git` gitfile points nowhere, but Item 1.1's slices do not ask for one.

## Positive Observations

- The helper uses a quoted `case` pattern instead of `grep "^$file: "`. It is
  immune both to regex characters in the path and to word splitting.
- The tier loop reuses the `.git` guard and the process-substitution feed of the
  stale-merge loop above it, so no pipeline subshell swallows `return` or
  `break`.
- The abort message reuses the arm's existing `$refusal` header, so the two
  outcomes cannot drift apart.

## Recommendations

None beyond the notes above. No refactoring needs a module split or a new
abstraction.
