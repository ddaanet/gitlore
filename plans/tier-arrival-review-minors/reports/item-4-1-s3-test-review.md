# Item 4.1, slice 3 — test review

Test: `a failed mktemp for the merge message file leaves the merge prepared`,
`tests/resolve_compose.bats:478-533`.

## Verdict

Red for the right reason after fixes.
`scripts/run-bats.sh tests/resolve_compose.bats`: `24 passed, 1 failed`; the
sole failure is the new test at line 518, the message-file line's assertion.
`shellcheck -x` is clean. `git diff -- scripts/` is empty.

## Findings and fixes

1. **Post-conditions never ran in RED.** The state assertions (MERGE_HEAD, merge
   state, staged synthesis in both stores, no message file) sat below the
   failing stderr assertion, so the RED run proved nothing about them. Moved
   them above it, as the slice-2 test does, with the same "Already true of the
   unfixed script" comment. The RED run now passes them against unchanged code.
2. **No rerun, unlike both siblings.** Slices 1 and 2 end by removing the stub
   and rerunning to status 0 with the merged line landed; that is what makes
   "stays prepared" operational rather than inferred from state files. Added the
   same tail (`rm -f "$fakebin/mktemp"`, rerun, `status -eq 0`, landed line).
3. **mktemp's own reason was unasserted.** Slice 1 pins the gitlore line after
   git's reason. Without an equivalent, a fix that swallows mktemp's stderr
   (`2>/dev/null`, which `.claude/rules/shell.md` forbids) or prints the gitlore
   line first went green. Added an ordering glob
   `*"mktemp: failed to create file via template"*"gitlore: the merge message file could not be created"*`,
   placed after the positive assertion so a missing line still fails on its own
   line. The stub's stderr text now matters, so it is a fixed string that no
   longer interpolates the path.
4. **Line-number citation in a comment.** "well before :309" cites a production
   line, which the dispatch constraints forbid in source. Reworded to "before
   the message file does".

Noted, not changed: the `find` for a leftover message file is vacuous against a
correct implementation (mktemp failed, so no file exists). The runbook lists it,
and a fallback-path mutation (below) shows it catches a real wrong fix.

## Stub checks

- The argv at `scripts/resolve.sh:309` is one argument, the template; the stub
  pattern `" $* "` against `*" ${TMPDIR}/gitlore-merge-msg.XXXXXX "*` matches
  it, including under a spaced `TMPDIR`, since the path is quoted in the
  pattern.
- Portability: `#!/bin/sh`, `case`, `exec "$real" "$@"` only; no bash-isms, no
  GNU mktemp flags. `real_mktemp=$(command -v mktemp)` also picks up
  `bsd-stubs.bash`'s shim when that is on PATH, which `exec` forwards correctly.

## Mutations (each restored; `git diff -- scripts/` empty afterwards)

Test mutations:

| Mutation | Result |
|---|---|
| Stub keyed on `gitlore-git.XXXXXX` (fails a different mktemp) | fails line 509, the hit-file grep — the grep is live |
| Stub pattern never matches (real mktemp runs, merge lands) | fails line 506, status |

Production mutations of `scripts/resolve.sh:309`:

| Implementation | Result |
|---|---|
| Correct: `\|\| { echo <line> >&2; exit 1; }` | passes, including the rerun |
| Prints the line, `exit 0` | fails line 506, status |
| Prints the line and continues | fails line 524, build arm text present |
| Emits the build arm's text | fails line 518, message-file line |
| `2>/dev/null` on mktemp, then the line | fails line 522, ordering glob |
| Line printed before mktemp's reason | fails line 522, ordering glob |
| `merge --abort` before the line | fails line 513, MERGE_HEAD |
| Falls back to a fixed message-file path | fails line 517, leftover message file |

## Environment note

The Bash tool's shell had `TMPDIR` unset during the production mutations, so a
first attempt's backup copy went to `/`; `scripts/resolve.sh` was restored with
`git checkout -- scripts/resolve.sh` (it was clean at session start) and the
mutations were rerun against the clean file. The results above come from that
rerun.
