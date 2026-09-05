# Runbook review — index-edit propagation

**Artifact**: `plans/index-edit-propagation/runbook.md` **Design**:
`plans/index-edit-propagation/outline.md` **Tree**: verified against `aed4254`
(`git status` clean at review time) **Mode**: review + fix-all

## Summary

Every `path:line` citation in the runbook was re-read from the tree; all but
three name what the runbook says they name, and the three misses are off-by-one
or one-line-short rather than wrong files. Every fixture helper the slices call
exists in `tests/helpers/` with the signature assumed. The structural problems
are elsewhere: one slice never reaches the code it tests, one slice is fully
subsumed by its predecessor, one phase would red on a missing symbol, two slices
name the wrong suite, one interface cannot feed the two channels it has to feed,
and two factual claims about the codebase are wrong in ways that would cost an
executor a debugging cycle each.

All are fixed in place. Item 4.2's open decision — raise the hub cap to 440 vs.
split `docs/design.md` — was left as a default with its fork named, per the
outline; it is executable as written and the constant, file and test it names
are real.

**Overall assessment**: Ready.

## Requirements coverage

| Requirement | Traces (verified) | Phase | Items | Coverage |
|---|---|---|---|---|
| FR-B | FR15, FR8, FR11, NFR5 | 1 | 1.1 (4 slices) | Complete |
| FR-C | FR15, FR2 | 2 | 2.1 (4 slices) | Complete |
| FR-D | NFR2, NFR4 | 3 | 3.1 (5 slices) | Complete |
| FR-E | project convention | 4 | 4.1, 4.2, 4.3 | Complete |

The upstream ids are real: FR2/FR8/FR11/FR15 are items 2, 8, 11 and 15 of
`docs/design.md` §Functional Requirements; NFR2/NFR4/NFR5 are items 2, 4 and 5
of §Non-Functional Requirements. `FR11` was added to FR-B's Traces column — the
dirty-only scope is argued from FR11 throughout Item 1.1 and Item 4.1, and it
was the one load-bearing trace the table omitted.

Outline coverage is complete: changes B, C, D and the design record each map to
a phase, and the three out-of-scope items are carried forward verbatim.

## Critical

1. **Phase 1 slice 3 (dirty-only scope) never reached the guard.** Location:
   former slice 3. Problem: the fixture was "the slice-1 divergence committed on
   both sides, working tree clean". `gitlore_sync_memory_to_live` returns at
   `scripts/lib/resolve.sh:885` when the store is clean **and** `HEAD` equals
   `live` — and `make_tier_in_memory` (`tests/helpers/tier-fixtures.bash:56`)
   fast-forwards *every* local branch onto the tier commit, so that fixture
   satisfies both. The function's body, including the `dirty = 1` branch under
   test, never runs. The case would have passed with the guard deleted, with the
   compose call absent, and with the whole feature reverted — the "path
   staleness" shape from `green-is-not-evidence`. Fix: the fixture now commits
   the divergence and then `git -C memory branch -f live HEAD~1`, so the early
   return does not fire and the skipped dirty branch is the operative condition;
   a paired positive over the same fixture, differing only in dirtiness, was
   added in its own test body. **FIXED** (now slice 2).

2. **Phase 3 slice 1 would red on `command not found`.** Problem:
   `gitlore_relay_marker_file` / `_write` / `_drain` are new, and
   `tests/index_sync.bats` sources `scripts/lib/index-sync.sh` directly in
   `setup()` (`:12`), so the slice-1 assertions would fail on absence, not
   wrongness — the exact thing `genuine-red-not-missing-sut` forbids and the
   recall artifact flagged. Fix: a **Red shape** paragraph added to Item 3.1
   prescribing the inert-stub landing (marker-file printing the unsuffixed path
   whatever its second argument, write returning 0 writing nothing, drain
   returning 0 with both variables empty), and noting that Phases 1 and 2 need
   no such step because their SUTs exist and their helpers ignore an extra
   argument. **FIXED**

3. **Phase 1 slice 4's refusal assertion pinned a string nothing produces.**
   Problem: the case asserted `$stderr` contains `refused`, but the reporting
   text is what Item 1.1 *adds* — the string would have been invented at green
   time, and `gitlore_compose_check_pins`' own problem text
   (`scripts/lib/index-compose.sh:310-349`) never contains it. Fix: Item 1.1 now
   fixes both message texts up front by reusing `gitlore_compose_and_report`'s
   wording (`:787` for rc 1, `:779` for rc 2), and the case asserts two strings
   that fail for different faults — `tier composition refused` (the branch
   fired) and `is checked out at` (the problem lines were forwarded). Also
   recorded: `gitlore_say_for_agent_or_user` (`scripts/lib/log.sh:7`) branches
   on `CLAUDECODE`, which `tests/commit_memory.bats` sets on some cases and not
   others, so both arms must carry the phrase. **FIXED**

4. **"a payload it already has in hand" is false for half the consumers.**
   Problem: Item 2.1 claimed all four consumers hold the payload, then
   contradicted itself one bullet later for `index-compose.sh` (which drains at
   `:23`). `add-tier-batch.sh` drains too — `cat >/dev/null || true` at `:38` —
   and the runbook said nothing about it, so an executor following the bullet
   would find no `$payload` to read. Fix: claim corrected, the capture spelled
   out (`payload=$(cat || true)`, since the script runs under
   `set -euo pipefail`), and its header comment at `:20` — "the batch payload is
   unused" — added to the list of comments this change falsifies, alongside the
   one already listed at `index-sync-pre.sh:43-47`. **FIXED**

## Major

5. **Phase 1 slice 2 was subsumed by slice 1.** Its assertions were the SHA
   equality (already true today — the tier-first ordering at
   `resolve.sh:900-905` exists to make it true) plus slice 1's own content
   assertion. No placement of the compose call fails slice 2 while slice 1
   passes: slice 1 observes the tier's *committed* carrier, which is downstream
   of everything slice 2 pinned. Fix: the gitlink equality folded into slice 1
   with an honest note about what it does and does not pin, the standalone slice
   removed, slices renumbered 3→2, 4→3, 5→4. (The recall artifact's reference to
   "Phase 1 slice 2" now points at the dirty-only case; the pairing argument it
   made still holds, inside slice 1.) **FIXED**

6. **Slice 1's assertion pair could not fail on either half alone.**
   `contains "— fresh hook"` plus `does not contain "stale hook"` is an absent
   string that is a variant of the present one — `green-is-not-evidence`
   prescribes exact-block equality instead, and this repo ships the helper for
   it (`assert_bullets`, `tests/helpers/tier-fixtures.bash`). Fix: both cases
   now extract `HEAD:MEMORY.md` to `$BATS_TEST_TMPDIR` and assert
   `assert_bullets` equals exactly `- [shared](shared.md) — fresh hook` — the
   unprefixed carrier form `tests/index_compose.bats:373` already pins.
   Consequence recorded in the test-suite note: `assert_bullets` calls
   `gitlore_index_part`, which lives in `index-compose.sh`, and neither suite
   sources any lib today, so both gain one `source` line in `setup()`. **FIXED**

7. **Slice 1.4's write-failure induction described the wrong mechanism.** The
   runbook said `chmod a-w memory/ddaanet` stops the temp file being created "in
   the carrier's directory". `gitlore_compose_write` puts its temp in the
   store's own gitdir via `rev-parse --absolute-git-dir`
   (`scripts/lib/index-compose.sh:656`) and explains why in a comment; what the
   chmod actually fails is the `mv` at `:676`. The outline had this right ("the
   temp file *or its `mv`*") and the runbook dropped it. Fix: mechanism
   corrected, with a note that the existing case's own comment
   (`tests/index_compose.bats:930-931`) says the same wrong thing and is stale —
   flagged, not edited, since it is outside this plan directory.
   **FIXED (runbook)**; the stale source comment is left for a separate pass.

8. **Two slices named the wrong suite.** Phase 3 slice 4 put a
   `session-start.sh` case in `tests/cc_hook_index_compose.bats`;
   `tests/cc_hook_session_start.bats` exists and owns that script. Phase 2 slice
   4 put an `add-tier-batch.sh` case in the same compose suite;
   `tests/cc_hook_add_tier.bats:11` owns that script. Fix: both repointed.
   **FIXED**

9. **`gitlore_relay_drain` could not feed the two channels it has to feed.** The
   interface returned one blob on stdout, but `systemMessage` and
   `additionalContext` are separate channels
   (`memory/ddaanet/hook-output-channels.md` §2) and drain removes the markers,
   so it cannot be called twice. Fix: drain now sets `GITLORE_RELAY_SYSMSG` /
   `GITLORE_RELAY_CTX`, mirroring `gitlore_compose_and_report`'s existing
   `GITLORE_COMPOSE_SYSMSG` / `GITLORE_COMPOSE_CTX` (`index-compose.sh:794,796`,
   consumed at `index-compose.sh:55-56` and `add-tier-batch.sh:80-85`). The
   marker's file format — previously unspecified, so two executors would have
   produced two formats — is now stated as two delimited sections. Slice 1's
   case was rewritten to assert the split (each variable carries its own body
   and **not** the other's), which a one-sided assertion would not have caught.
   **FIXED**

10. **Item 4.2 omitted the one prose surface that contradicts it.**
    `check_size`'s own docstring (`scripts/check-docs-links.py:251-253`) reads
    "Split it along a need-time seam rather than raising the cap" — it would
    have sat directly above code doing the opposite. Fix: the three prose
    surfaces that move with the constant are now enumerated (module docstring
    `:29-31`, `check_size`'s docstring, and the block message, which
    interpolates `MAX_LINES` and must name whichever cap it applied). The
    implementation note now also names the mechanism precisely: `check_size`
    already receives `root` and can compare `os.path.relpath(path, root)`
    against the existing `HUB` constant at `:53`. **FIXED**

11. **Items 4.1 and 4.2 leave the gate red between them, unstated.** A decision
    argued in a node with no conclusion in the hub is what
    `scripts/check-docs-links.py:406` blocks on, so running the checker after
    4.1 reports a failure that is correct and expected. Fix: stated in Item 4.1
    and in the Gate section — run the checker after 4.2, land the two together.
    **FIXED**

12. **The compose call's placement "after the freshness check" had no recorded
    reason.** `gitlore_commit_msg_freshness` (`scripts/lib/util.sh:275`)
    compares the approved summary's mtime against the newest file under
    `$mempath`; compose writes carrier files, so a compose placed ahead of it
    makes the tree newer than the summary and *every* commit is refused as
    stale. Slice 1 catches the violation, but the constraint read as arbitrary
    tidying and was the kind an executor "cleans up". Fix: rationale added to
    Item 1.1. **FIXED**

13. **`tests/integration_gitlink_staging.bats` was named as a Phase 1 test home
    but no slice used it.** Fix: the Corrections section now states it as the
    regression boundary for the `GIT_INDEX_FILE` handoff the compose call sits
    upstream of (per `memory/ddaanet/git-hook-env-leak.md`), not as a home for
    new cases. **FIXED**

14. **`pre()` and `feed()` were described as already taking an agent id.** They
    do not: `pre()` (`tests/cc_hook_index_compose.bats:27`) takes only a file
    name or the literal `Bash`, and `feed()` (`:36`) takes no argument at all
    and pipes a literal `{}`. Fix: restated as work in the slice. **FIXED**

15. **Slice 3.2's title contradicted its own body and the outline.** "relays
    *instead of* reporting" against a body asserting the subagent still gets its
    own JSON, and an outline section headed "In addition to, not instead of".
    Fix: title corrected. Slice 3.2's first case title had the same inversion
    ("emits no parent-facing json" over an assertion that stdout *is* valid
    JSON) and was corrected too. **FIXED**

## Minor (all fixed)

- `tests/index_compose.bats:920` → `:921` (920 is blank; the `@test` is 921).
- `index-sync-post.sh:36-38` → `:35-38` (the bounding comment starts at 35).
- `tests/check_docs_links.bats:374` → the `@test` lines `:371` and `:383`, and
  the new blocking case now asserts `oversized-file`, the path and the count
  rather than only a non-zero status.
- "a sixth untracked file" listed only four names. There are five existing
  `gitlore-…` gitdir names once `gitlore_merge_artifact_file`
  (`scripts/lib/util.sh:226`) is counted; the enumeration now matches the
  ordinal.
- Phase 2 slice 2 asserted "no file matching the keyed glob" with no form given.
  Now a `find -maxdepth 1 -name` form, with the reason: bash 3.2 leaves an
  unmatched glob as a literal and the gitdir path may contain whitespace. Also
  names the suite's actual drivers — `pre_stdin` (`:109`), `post_stdin`
  (`:136`), `batch_payload` (`:140`) — and that `batch_payload` needs the same
  optional agent id.
- Phase 3 slice 4's negative now holds its framing literal in one test-file
  variable asserted by both cases, defined test-side, per the string-staleness
  rule.
- Phase 3 slice 5 now names the gitdir explicitly
  (`git -C memory rev-parse --absolute-git-dir`) and bounds the chmod: compose
  runs first and touches only the worktree, and if a `git` call does fail under
  the mode change, narrow the induction rather than widen it.
- Item 4.1 now names `D50` as the next free number (`D49` is the highest across
  `docs/design.md` and `docs/references/`) with the command to re-derive it.
- Slice 1.1's fixture now names `seed_tier_bullet` explicitly and notes that
  `commit-memory.sh -m` writes its own message file (`:61-63`), so the fixture's
  copy is for the hook case.
- Item 4.3: the filename date is the landing date; both changelog surfaces are
  under the same `docs/` cap, and `docs/changelog.md` is at 312 lines.
- `Depends on: … Model: …` run together on one line in four items; separated.
- One table row was mid-repair when a newline was introduced into it; repaired
  to a single physical line.

## Verified and left alone

- **Citations that check out**: `scripts/lib/index-sync.sh:94,102`;
  `scripts/lib/resolve.sh:11`; `scripts/git-hooks/pre-commit:68`;
  `scripts/commit-memory.sh:66`; `index-sync-pre.sh:40-41,43-47,48,53`;
  `index-sync-post.sh:30`; `index-compose.sh:23,32`; `add-tier-batch.sh:75`;
  `scripts/lib/util.sh:163,217`; `scripts/check-docs-links.py:55,29-31`;
  `docs/design.md` 218-228 and 308-318 (and the file is at exactly 400 lines);
  `tests/index_sync.bats:356`; `tests/cc_hook_index_compose.bats:45`;
  `tests/git_hook_pre_commit.bats:149,185`; `session-start.sh:325-338`; the node
  at 340 lines; the suite case counts (13 / 3) and the `load` lines.
- **Fixture helpers**: `make_parent_with_memory` (`fixtures.bash:14`),
  `make_tier_in_memory` (`tier-fixtures.bash:56`), `set_tier_manifest` (`:108`),
  `seed_tier_bullet` (`:116`), `seed_root_bullet` (`:133`) all exist with the
  arity the slices use. `gitlore_commit_msg_file` (`util.sh:133`) and
  `gitlore_memory_dirty` (`util.sh:243`) likewise — and the runbook's
  `gitlore_memory_dirty memory` "is still `0`" is correct: that function echoes
  a string and does not signal through exit status.
- **Portability**: nothing in the runbook implies a GNU-only flag. The two
  `chmod` inductions, the `id -u` guard and the `find` form added in review are
  BSD-safe; the one whitespace hazard (the keyed-glob absence check) is fixed.
- **Item 4.2's open decision**: left as stated. The fork is named, the default
  is executable, and the three things it names are real — `MAX_LINES` at
  `scripts/check-docs-links.py:55`, the `HUB` constant at `:53` that makes the
  hub test cheap, and `tests/check_docs_links.bats` with an existing 400-line
  filler pair to sit beside.

## Unfixable / for the executor

- The stale comment at `tests/index_compose.bats:930-931` ("the temp file cannot
  be created there") misdescribes `gitlore_compose_write`. Outside this plan
  directory, so not edited. The runbook now warns against copying it; correcting
  the source comment is a one-line change worth folding into Phase 1.
