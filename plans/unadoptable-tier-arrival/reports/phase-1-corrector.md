# Review: Phase 1 checkpoint — prevention (S1 / K5)

**Scope**: `git diff e60ff38..HEAD -- scripts tests` (commits 7f143cf, 9a7e277,
f3381c5): `scripts/lib/index-compose.sh`, `scripts/lib/resolve.sh`,
`tests/commit_memory.bats`, `tests/git_hook_pre_commit.bats`,
`tests/index_compose.bats`. Checked for seams against the callers of
`gitlore_sync_memory_to_live` (`scripts/git-hooks/pre-commit`,
`scripts/commit-memory.sh`, `scripts/cc-hooks/memory-commit-batch.sh`) and
against the prose in `docs/`, `skills/` and `agents/`. **Date**: 2026-09-14
**Mode**: review + fix

## Summary

The phase delivers K5 and S1. In the rc 1 arm, a rule 1, 4 or 6 problem in
root's `MEMORY.md` or in a tier carrier aborts the commit when that file has
uncommitted changes. The abort restamps the approval and returns 1. Clean files
and rules 2 and 3 stay advisory. The attribution helper matches the exact
`"<file>: "` prefix. Every postcondition in the outline has a test.

The per-slice reviews missed three seams, all now fixed:

- **Standalone commit path:** the PostToolBatch hook told the agent "No action
  is needed" right next to an abort that needs an edit.
- **Abort message:** it did not say which of the listed problems caused the
  abort.
- **rc 1 arm comment:** it had lost two true statements about the arm, and one
  clause was ambiguous.

**Overall Assessment**: Ready

## Issues Found

### Critical Issues

None.

### Major Issues

1. **The standalone commit path told the agent to do nothing about an abort that
   needs an edit**
   - Location: `scripts/cc-hooks/memory-commit-batch.sh:116-117` (the `else` arm
     after `commit-memory.sh`)
   - Problem: the handoff path runs `commit-memory.sh -F "$msgfile"` from
     PostToolBatch. On any failure it tells the agent: "it retries by itself …
     No action is needed from you and re-triggering will not help. Reason:
     $out". Before this phase, a compose refusal on this path went ahead. Now a duplicate pointer in an edited carrier makes `$out`
     say "Fix them by editing the lines above". The wrapper around it
     contradicts that. The agent gets two opposite directives, and the trigger
     re-aborts on every tool batch until somebody edits the file.
   - Fix: the agent message now says the commit retries by itself and
     re-triggering will not help, then: "When the reason below names a fix, make
     it and the retry picks it up; otherwise no action is needed from you." The
     comment above the call now says the same. The locked-repo test's `deferred`
     / `re-trigger` assertions still hold. A new test in
     `tests/cc_hook_memory_commit_batch.bats` covers the abort: "a refusal that
     needs a fix keeps both IPC files and hands the agent the fix". It uses a
     root weld through the batch hook and asserts the directive, the abort
     reason, memory `HEAD` unchanged, and both IPC files kept. It is red against
     HEAD's hook on the directive assertion.
   - **Status**: FIXED

### Minor Issues

1. **The abort did not say which listed problem blocks the commit**
   - Location: `scripts/lib/resolve.sh`, rc 1 arm abort message
   - Note: `$refusal` lists every problem in the store, advisory ones included:
     a clean carrier's duplicate and rule 2 and 3 lines. The directive "Fix it
     by editing the named lines" did not say which lines block the commit. The
     tier loop also stopped at the first dirty carrier with a problem, so after
     one fix the retry could abort again on the next file. The arm now collects
     every changed index file that has a problem (root, then each tier, no
     `break`). The agent arm lists them after "The changed index files with
     problems:" and ends "Fix them by editing the lines above that name those
     files, then retry; the summary needs approval again." The user arm is
     unchanged and still ends the way the rc 2 arm does. New test in
     `tests/commit_memory.bats`: "an abort names every changed index file with a
     problem and no clean one". It uses a dirty root weld, a dirty `other`
     carrier duplicate and a committed-clean `ddaanet` duplicate. It asserts all
     three problem lines, then the exact list block `memory/MEMORY.md` /
     `memory/other/MEMORY.md`. It is red against HEAD.
   - **Status**: FIXED

2. **The rc 1 arm comment dropped two true statements and had an ambiguous
   clause**
   - Location: `scripts/lib/resolve.sh`, rc 1 arm header comment
   - Note: "in root's MEMORY.md or a tier carrier with uncommitted changes" can
     be read as root aborting whether or not it is dirty. It now says "when that
     file has uncommitted changes". Slice 1 deleted two sentences that still
     describe the code, and both are restored:
     - Rc 1 reaches this arm only from `gitlore_compose_check`, because the pin
       guard runs first. The attribution depends on this: rule 7 lines carry no
       file prefix, and none can arrive here.
     - `$refusal` is held in one variable so the arms cannot drift apart. Four
       messages now share it.
   - **Status**: FIXED

## Checked, no finding

- **Attribution spelling:** `gitlore_compose_check` builds each prefix from the
  `$mempath` it was given, as `"$mempath/MEMORY.md"` and
  `"$mempath/$tier/MEMORY.md"`. Its tier set comes from `gitlore_tier_paths`,
  the same set the arm loops over. Rule 2, rule 3 and pin lines start with
  `the tier manifest`, `root index line` or `tier '`, so none can match.
- **Stale-merge guard:** memory's guard and each tier's guard run before the
  compose, so an abort never meets a half-finished merge. The abort returns
  before `gitlore_sync_tiers_to_live`, so no tier commit and no `live` advance
  happen (slice 1 asserts the tier `HEAD` and `live`).
- **State left behind on the abort path:** compose rc 1 writes nothing. The only
  earlier writes are `gitlore_stage_landed_tiers` staging and a recovered
  merge's up projection. The pin guard and rc 2 arms leave the same state, and
  the restamp covers it. No lock is taken, and `$msgfile` stays in place.
- **Dirtiness reads:** untracked `?? MEMORY.md` (a new carrier or root) counts
  as a change and aborts, which is correct. A failed status read restamps and
  returns 1, following the `gitlore_sync_tiers_to_live` idiom.
- **Wording against rc 2 and the pin guard:** the agent arm follows the pin
  guard's "the summary has to be approved again" pattern. The user arm matches
  rc 2's ending.
- **`skills/`:** no statement about the commit path's compose refusal. Nothing
  there became false.

## Doc statements made false by this phase

| Statement | Covered by |
|---|---|
| `docs/references/git-hooks.md:15-16` "a compose refusal reported" | Item 6.2 |
| `docs/references/git-hooks.md:55` "rc 1 reports and continues" | Item 6.2 |
| `docs/references/git-hooks.md:147-150` D50 body: "the commit proceeds with the carrier as it stands and the refusal is only reported" | Item 6.2 names D50's *conclusion*; this argument paragraph must be rewritten with it |
| `docs/decisions.md:53-54` "a compose refusal only reports" | Item 6.4 |
| `docs/design.md:230-232` D50 sentence | Item 6.5 |
| `docs/references/commit-gate.md:54-57` "on any failure the trigger and the message file stay put and the next batch retries — no agent action" | **No Phase 5–6 item.** An index-problem abort (and an off-pin tier, as before) needs an edit before the retry lands. |
| `agents/memory-merger.md:37` "a composition refusal … does not mean the merge failed" | Item 5.1 (K4, Phase 3's change, not this phase's) |

## Fixes Applied

- `scripts/lib/resolve.sh` rc 1 arm:
  - The comment scopes "uncommitted changes" to both files.
  - The comment restores the notes that rc 1 comes only from
    `gitlore_compose_check` and that `$refusal` is shared.
  - `abort=0` / `break` is replaced by an `abort_files` list, collected over
    root and every tier.
  - The agent-arm abort text names those files.
- `scripts/cc-hooks/memory-commit-batch.sh`: the deferral's agent message defers
  to a fix the reason names. The comment above the call says so.
- `tests/commit_memory.bats`: new test "an abort names every changed index file
  with a problem and no clean one".
- `tests/cc_hook_memory_commit_batch.bats`: new test "a refusal that needs a fix
  keeps both IPC files and hands the agent the fix".

Verification:

- `shellcheck` on the four edited files: clean.
- `scripts/run-bats.sh`, one file at a time:
  - `tests/cc_hook_memory_commit_batch.bats`: 11 passed, 0 failed.
  - `tests/commit_memory.bats`: 35 passed, 0 failed.
  - `tests/git_hook_pre_commit.bats`: 20 passed, 0 failed.
- `tests/index_compose.bats`: not re-run; neither it nor its SUT was edited.
- Mutation: both scripts replaced with `git show HEAD:<file>`, then each new
  test run with `--filter`. Each was red at its intended assertion
  (`commit_memory.bats:232` on the list block, and
  `cc_hook_memory_commit_batch.bats:154` on the directive). Both files were
  restored afterwards and `git diff --stat -- scripts` confirmed it.
- Nothing staged or committed.

## Requirements Validation

| Requirement | Status | Evidence |
|---|---|---|
| K5 abort: dirty carrier with problems, via `commit-memory.sh` and `pre-commit`, restamp | Satisfied | `commit_memory.bats` "a dirty carrier with a duplicate pointer aborts…", `git_hook_pre_commit.bats` restamp test |
| K5 abort: dirty root with rule 1/4/6 | Satisfied | "a dirty root index with a welded line aborts…" |
| K5 advisory: clean carrier; tier dirty outside carrier; root dirty outside `MEMORY.md` | Satisfied | the three "commits and reports" tests |
| K5 advisory: root rules 2/3 even when dirty | Satisfied | "a leftover root prefix commits and reports…" |
| S1 helper: exact prefix, spaced mempath, prefix-named tiers | Satisfied | `index_compose.bats` "problem attribution matches the exact file prefix" |
| S1 arm comment names abort vs report | Satisfied | rc 1 arm header comment |

## Positive Observations

- The helper is a quoted `case` prefix match, safe against regex metacharacters
  and word splitting. The unit test's decoy (`my memXd`) and prefix tier (`a` vs
  `ab`) pin both.
- Each abort test also asserts that the index is still dirty and that memory
  `HEAD`, tier `HEAD` and `live` are unmoved, so a non-zero exit from some other
  refusal cannot pass them.
- The restamp test backdates with a fixed `touch -t`, which needs neither a
  sleep nor a GNU/BSD `date` split.

## Recommendations

- **Batch retry and the approval claim:** on the PostToolBatch path, the retry
  reuses the preserved summary. The edit that fixes an aborting index therefore
  commits under the old approval, although the abort text says "the summary
  needs approval again". The pin guard's remedy text has the same gap. Closing
  it needs a status protocol between `commit-memory.sh` and the batch hook, for
  example a distinct exit for a refusal that needs an edit, which would clear
  the msgfile or stop the retry loop. That is a design choice beyond this phase.
- Phase 6 should cover the `commit-gate.md:54-57` claim listed above. Item 6.2
  should rewrite the D50 argument paragraph, not only its conclusion line.
