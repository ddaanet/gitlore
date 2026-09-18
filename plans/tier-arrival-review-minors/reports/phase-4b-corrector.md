# Phase 4 supplementary checkpoint — slice 3 and the Item 6.1 allow-list

Verdict: **pass after fixes. One Major finding in the plan: fixed in the runbook
and outline before Phase 6.** Item 6.1's allow-list would have sent a
post-landing re-yield to **Summarize** instead of **Loop**, which strands the
fresh merge. The code is correct as landed. Two test denials were missing and
are now added, each proven by a mutation.

Nothing committed or staged. `git diff -- scripts/` is empty: the one production
mutation was restored from a backup under `.git/`, and the backup was removed.

## MAJOR — Item 6.1 routes a post-landing re-yield to Summarize (fixed in the plan)

`continue-after-merge` exits 1 after the merge commit in two places where it
**prepares a fresh merge and prints the full `gitlore: memory merge prepared`
directive**. That happens when the local `HEAD:live` push (`:358-361`) or the
remote `live` push (`:378-382`) is refused as divergence, and
`gitlore_yield_merge` runs. As written, Item 6.1 read this as "any other
non-zero": the merger says the outcome is unrecognised, and the skill goes to
**Summarize**. The skill currently goes to **Loop**, where `resolve.sh`'s
`gitlore_guard_stale_merge_state` re-emits the directive for the new merge
(`scripts/lib/resolve.sh`, `stale-with-merge-head`) and the cycle continues.
Following Item 6.1 as written would drop that and leave a prepared merge in
front of the git operation that triggered the resolve.

The directive cannot appear before the merge is committed. No pre-landing path
calls `gitlore_yield_merge` or `gitlore_emit_merge_directive`. The one
pre-landing hook run, the memory gate on the sentinel commit, exits 0 at once on
`GITLORE_MEMORY_COMMIT` (`scripts/git-hooks/memory-pre-commit:9`). So the line
is a safe post-landing key.

Fix in `plans/tier-arrival-review-minors/runbook.md` Item 6.1:

- It names `gitlore: memory merge prepared` as the one recognised post-landing
  non-zero line.
- It adds a merger arm: the merge landed and a fresh one is prepared; quote the
  lines, say both, and stop.
- It adds a skill rule: such a report goes to **Loop**, as it does now.

`outline.md`'s Phase 4 "Prose" gains the matching bullet.

## The allow-list claims, checked against the code

- **`continue-after-merge` is the only subcommand.** True (`:285-395`). Any
  other name exits 2.
- **Every exit before the merge commit is non-zero.** True. Explicit exits
  (`:35`, `:43`, `:52`, `:58`, `:138`, `:312`, `:323`, `:329`) are all `exit 1`.
  Aborts under errexit and `set -u` exit non-zero. None of the functions reached
  before `:325` calls `exit 0`. The only `exit 0` in the sourced libs is inside
  the hook-wrapper heredoc in `scripts/lib/util.sh:69,74`, which is emitted
  text, not executed code. The function calls that run inside `$(…)` would only
  exit their subshell anyway.
- **Every exit 0 lies after the merge commit.** True. There are exactly two:
  `:375` (`publish: no`) and `:389`. Both paths through the case arm end in an
  `exit`.
- **At least one post-landing non-zero exit has no recognised line.** True. The
  plan names one case, and there are more:
  - `not because of divergence` (`:364`, `:384`, from `push_or_report`), as the
    plan says;
  - a failed re-yield: `|| exit 1` at `:360` and `:381`, with the yield's own
    `could not prepare…` or `state file could not be written` lines;
  - errexit aborts on `gitlore_git … update-ref -d` (`:353`, bare),
    `gitlore_clear_merge_state` (`:352`) and `gitlore_commit_tier_bookkeeping`
    (`:350`, the last command of an `||` list, so errexit stays armed). These
    print git's text only.

  The runbook now names the errexit class next to the push failure. Its "status
  0 means the commit landed and nothing else does" was ambiguous next to its own
  "non-zero alone does not mean unlanded", so it now reads: status 0 means
  landed, and a non-zero status claims nothing by itself. Stale line references
  are also corrected: `:321` becomes `:325` for the merge commit, and Item 4.1's
  target and the outline's Harness range become `:309-330`.

## M15 enumeration, re-run on the current script

| # | Exit | Where | `the merge was not committed`? |
|---|---|---|---|
| 1 | not installed | `:35` | No, by construction |
| 2 | no merge state file | `:42-43` | No, by construction |
| 3 | merges in more than one store | `:49-52` | No (Gap B, covered by the allow-list) |
| 4 | state names no usable store | `:57-58` | No (Gap B) |
| 5 | errexit on `memroot=` … `publish=` | `:39,40,54,55,60,63` | No (Gap B) |
| 6 | merged index fails the check | `:136-138` | Yes |
| 7 | errexit on a staging `add` | `:126,156,172,181` | No, by decision (rider `:105-109`) |
| 8 | failed message-file `mktemp` | `:309-313` | **Yes (now)** |
| 9 | message build failed | `:319-324` | Yes |
| 10 | merge commit refused | `:325-330` | Yes |

Rows 1–7 are unchanged apart from row 8. Rows 9–10 moved down by the four lines
slice 3 added. `:145` (`gitlore_compose_dangling`) and `:297`
(`gitlore_root_dirty_beyond_pair`) still cannot fail. One edge not in the
earlier table: a failing *stderr write* in an unguarded `echo` or `printf | sed`
inside `compose_merged_indexes` aborts under errexit. With stderr broken,
nothing can speak, and the allow-list reads it as unrecognised. No action.

## Minor (fixed) — the slice-1 and slice-2 tests did not deny the message-file line

`tests/resolve_compose.bats`: slice 3's test denied both sibling arms, but
neither sibling test denied its text. Two denials are added:

- refused-commit test, `:413-414`: "the file was created, or the build would not
  run";
- build-failure test, `:472-474`.

Proof: `scripts/resolve.sh` was backed up to `.git/resolve.sh.bak`, and the
message-file `echo` was added unconditionally after a successful `mktemp`. Both
filtered tests then failed on the new assertions: `not ok 1 … (line 414)` and
`not ok 2 … (line 474)`. The script was then restored from the backup and
`git diff -- scripts/` came back empty. The three arms' texts are pairwise
non-substrings ("message could not be built" does not occur in "message file
could not be created"). So each of the three tests now pins its own line and
denies both others.

## Comments and docs in the diff

The slice-3 comment at `:314-318` is in the present tense. It cites no plan,
memory, slice or line number, and it matches the code: `mktemp` failed, so there
is no file to remove, and the removal comes first in the `||` groups. The test
comments are in the same style. Nothing to fix.

## Runs

- `shellcheck -x tests/resolve_compose.bats`: clean.
- `GITLORE_GIT_RETRY_SCHEDULE=0 scripts/run-bats.sh tests/resolve_compose.bats`
  (foreground): **25 passed, 0 failed**.
- `just format-docs` after the plan edits.
- `just precommit` not run.

## Files changed

- `/Users/david/code/gitlore/tests/resolve_compose.bats`: two denial assertions.
- `/Users/david/code/gitlore/plans/tier-arrival-review-minors/runbook.md`:
  - Item 6.1 gains the re-yield arm, the merger and skill routing, the fuller
    list of unrecognised post-landing exits, and `:325`;
  - Item 4.1's target becomes `:309-330`.
- `/Users/david/code/gitlore/plans/tier-arrival-review-minors/outline.md`: the
  Phase 4 Harness range becomes `:309-330`, and a re-yield bullet is added.

## UNFIXABLE

None.
