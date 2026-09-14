# Outline Review: unadoptable-tier-arrival

**Artifact**: plans/unadoptable-tier-arrival/outline.md **Date**: 2026-09-14
**Mode**: review + fix-all (PDR criteria) **Requirements source**:
`.claude/handoff-task.md` "Current task" (items 1–3), Major 1 of
`plans/index-edit-propagation/reports/deliverable-review.md`, code m4 of
`plans/index-edit-propagation/reports/minor-pass-2.md`

## Summary

The outline traces every brief item and picks options with rationale. It
enumerates IN/OUT and leaves three genuine forks open with defaults. K1's merge
shape is correct: `gitlore_yield_merge <tier> <pin-sha> repair live` produces a
clean `--no-ff` merge with `MERGE_HEAD` = arrival (probed with real git). The
claim that every MERGE_HEAD-keyed path works unchanged is false in four places,
though. Two of them lose upstream content silently. All four are fixed in the
outline as postconditions, and two open questions and five risks are added.

**Overall Assessment**: Needs Iteration. The fixes are in, and five open
questions (three original, two added) are my human partner's call.

## Requirements Traceability

| Requirement | Outline Section | Coverage | Notes |
|---|---|---|---|
| 1a Take whose refusal names the arriving carrier prepares a repair merge instead of walking back | Approach 2, K1, K2, S2 | Complete | — |
| 1b Merger gets the problem list | S2 (`problems` field), S5 | Complete after fix | the field was lost on marker completion; S2 postcondition added |
| 1c Continuation composes up and adopts | K4, S3 | Complete | — |
| 1d Repair publishes to every consumer | K6, S3 | Complete | closing-line wording fixed for push-prepared repairs |
| 1e tier-merge-direction governs wording; D50 node records the structural distinction | K3, S6 | Complete | which duplicate survives is added as open question 5 |
| 2a Commit path aborts (rc 2 shape, approval kept) on a refusal naming a committed tier's carrier | K5, S1 | Complete | — |
| 2b Root-only problem stays advisory | K5, S1 | Complete | — |
| 2c Contradicts current rc 1 comment | S1 | Complete after fix | comment-rewrite postcondition added |
| 3 m4: distinct `push_or_report` status; rest after origin failure, keep on merge after local failure | Approach 3, S4 | Complete | m4's "name the third resting exception in tier-stores.md and changelog" added to S6 |
| Defect: `rest_unadopted_tier` leaves the same shape | K4 | Complete | resting now only for non-carrier problems |

**Traceability Assessment**: All requirements are covered. The gaps were partial
coverage of 1b, 2c and m4's doc record, and they are fixed.

## Scope-to-Component Traceability

| Scope IN Item | Component | Notes |
|---|---|---|
| Prevention | S1 | — |
| Repair preparation | S2 | pin-guard, entry-wise-pass, marker and failure-restore postconditions added |
| Continuation gate and landing | S3 | recovery postconditions added |
| m4 per-arm exits | S4 | — |
| Agent-facing prose | S5 | `target_ref` sha and the merge skill's Diverged section added |
| Design records | S6 | `merge-state-recovery.md` and m4 exception added |

**Scope Assessment**: No orphans. The OUT list gains one pre-existing defect,
the entry-wise pass dropping lines in ordinary merges, left for scheduling.

**Cross-component interfaces**: S1's attribution helper is consumed by S2 (K2)
and S3 (K4). The dependency is now stated. Every consumer must match the prefix
against the same `$mempath` spelling passed to the check.
`compose_merged_indexes` passes `gitlore_memory_path`, and the take passes its
own `mempath`.

## Grounding of K1 (verified against code)

- `gitlore_prepare_merge` with authority = pin sha and pending = `live`: the
  ancestry precheck passes and `base` = pin. `checkout --detach pin` and
  `merge --no-commit --no-ff <arrival>` then leave `MERGE_HEAD` = arrival, the
  worktree = arrival and the index ≠ HEAD. The probe in a scratch repo gave
  parents (pin, arrival) on commit.
- Marker/state: `source_ref` = arrival, `target_ref` = pin sha, `mine_diff` =
  `diff pin pin` = empty, `changed_files` = pin...arrival.
- Works unchanged: guard `stale-with-merge-head` (complete then emit),
  `gitlore_restore_staged_merge` (HEAD == `target_ref` resolves),
  `gitlore_landed_merge_commit` (arrival at parent index ≥ 3), SessionStart
  mid-merge skip (`session-start.sh:272`, keyed on state file or MERGE_HEAD),
  the continuation commit, `HEAD:live` ff (live = arrival ⊂ merge), and no
  origin push for flavor ≠ `head-vs-remote`. `grep -- --first-parent scripts/`
  is empty.
- Both reach paths leave HEAD = pin and `live` = arrival once the preparation
  checks out the authority. The remote path runs `push . $remote:live`, then
  `checkout live`. `gitlore_adopt_advanced_live` has `live` ahead already.

## Review Findings

### Critical Issues

None.

### Major Issues

1. **The pin guard does not protect a repair in progress**
   - Location: K1 "reuses … the pin guard's mid-merge remedy"
   - Problem: `gitlore_compose_check_pins` runs
     `[ "$head" = "$pinned" ] && continue` before its mid-merge test. A repair
     keeps HEAD on the pin, so the guard never fires. After the merger
     restructures the carrier, `compose_check` passes. SessionStart's
     unconditional `gitlore_compose` (`session-start.sh:330`), or a
     PostToolBatch compose triggered by any root-index edit, then runs
     `gitlore_compose_down` over the tier worktree. Root's text wins for shared
     paths, so upstream rewordings revert. Root-carried paths the arrival
     deleted come back. The continuation then adopts that. This is silent loss
     of approved upstream content. Ordinary tier merges are safe only because
     their HEAD is the authority, not the pin.
   - Fix: K1 now lists this under "Does not work unchanged". S2 adds a
     postcondition: `gitlore_compose` refuses while the tier holds the repair,
     with HEAD on the pin, and writes no carrier. S2's files gain
     `scripts/lib/index-compose.sh` and `tests/index_compose.bats`.
   - **Status**: FIXED

2. **Recovery returns a dead repair to the arrival, off the pin**
   - Location: K1, S3 Recovery
   - Problem: `gitlore_recover_stale_no_merge_head` checks HEAD out at
     `$pending` (`scripts/lib/resolve.sh:198`, `:216`). That happens both for a
     preparation interrupted before its merge and for a dead merge after
     `git merge --abort`. For a repair, pending is the arrival, so recovery
     leaves the tier ahead of its pin with a defective carrier. That is the
     state the walk-back exists to avoid, and the pin guard answers it with "no
     automatic remedy". `gitlore_prepare_merge`'s failure path restores to the
     same commit.
   - Fix: K1 now lists it. S2 adds "a preparation that fails leaves the tier on
     the pin, `live` on the arrival, no merge state". S3 adds "an aborted or
     never-run repair returns the tier to the pin, not the arrival" and names
     `gitlore_recover_stale_no_merge_head` and `tests/resolve_recovery.bats`. S6
     adds `merge-state-recovery.md`.
   - **Status**: FIXED

3. **The entry-wise index pass drops interleaved lines from the arrival**
   - Location: Risks "S2's entry-wise pass … should reproduce the arrival", S2
   - Problem: `gitlore_index_part … bullets` returns the whole first-to-last
     bullet region, but `_gitlore_index_merge_bullets` emits only path-keyed
     bullets. Non-bullet and blank lines in the region are discarded with rc 0,
     and `gitlore_merge_indexes` then `git add`s the result. The probe fed
     base = ours = a clean index and theirs = the same plus an interleaved line
     and a welded line. It returned rc 0 with the interleaved line gone and the
     welded line intact. A duplicate makes the pass decline (rc 2), so that case
     alone is byte-identical. The outline's risk was stated as expectation and
     was wrong for one of the three defect kinds. The repair would find the
     defect already "fixed" by deletion.
   - Fix: the Risk is restated as verified. S2's fixture covers all three defect
     kinds, and the byte-identity postcondition applies to each. K1 lists the
     gap. The same loss in ordinary merges predates this job and is recorded in
     OUT for scheduling.
   - **Status**: FIXED

4. **A consumer already resting with the arrival in `live` re-repairs instead of
   taking a published repair**
   - Location: Risks, Open questions
   - Problem: `gitlore_merge_one_store` calls `gitlore_adopt_advanced_live`
     before it fetches, and `gitlore_push_stores` enters the take on the same
     `live`-ahead test. So a consumer walked back before this ships prepares its
     own repair even when another consumer's repair is already on origin. So
     does one resting after a mixed refusal (K2), after `rest_unadopted_tier`,
     or after an aborted repair. Its push then diverges from that repair, which
     costs a second synthesis and tangles history. The consumers from the
     incident that motivated this job are exactly this population.
   - Fix: added as a Risk and as open question 4, defaulting to fetch first and
     taking the published repair. It is not resolved, because it changes the
     adopt-before-fetch ordering rationale.
   - **Status**: FIXED (surfaced as an open question)

### Minor Issues

1. **`problems` lost on marker completion**. `gitlore_complete_merge_state`
   rebuilds from `source_ref`/`target_ref` only. An S2 postcondition is added,
   and K1 lists the gap. FIXED
2. **Push-prepared repair gets the wrong closing line**. With
   `GITLORE_MERGE_NO_PUBLISH=1` the continuation prints "merged without
   publishing, as /gitlore:merge asks", even when `pre-push` or `push-memory.sh`
   prepared the repair. Fixed in K6 and S3. FIXED
3. **rc 1 comment rewrite unassigned** (brief item 2 says it contradicts the
   comment). An S1 postcondition is added. FIXED
4. **m4's resting-exception record missing**. minor-pass-2 asks for it in
   `tier-stores.md` and the changelog. Added to S6. FIXED
5. **Merger contract says `target_ref` is `live` or `origin/live`**. For a
   repair it is a sha. Added to S5. FIXED
6. **`skills/merge/SKILL.md` Diverged section says "each hold commits the other
   lacks"**. A repair directive is not a divergence. Added to S5. FIXED
7. **K3 underspecified**. "Keep one of a duplicated pair" does not say which
   when the texts differ, and picking one is a wording choice the tier-merge
   direction rule constrains. It also does not say where an interleaved line
   goes. Added as open question 5 with a default. FIXED
8. **S2 "nothing is staged" was ambiguous**. The repair stages the arrival in
   the tier index by construction. Now "nothing is staged in the memory store".
   FIXED
9. **Unstated dependency and ownership**. S1's attribution helper is used by S2
   and S3, and S3 also edits `scripts/lib/resolve.sh`. Both are stated in
   Dependencies. FIXED
10. **Missing risks**. Recovery's landed-merge scan matches another consumer's
    fetched repair of the same arrival (the arrival is public, unlike an
    ordinary pending commit). Pre-push publishes a pre-S1 clean tier commit
    unchecked. Upstream's own fix racing a downstream repair broadens the
    concurrency risk. All are added to Risks. FIXED

## Fixes Applied

- K1: `target_ref`/`source_ref`/`base`/`mine_diff` stated. The "reuses
  everything unchanged" sentence is replaced by a verified works/does-not-work
  split (pin guard, recovery target, entry-wise pass, marker completion).
- K2: the prefix is matched against the same `$mempath` spelling.
- K3: points to open question 5.
- K6: closing-line wording for push-prepared repairs.
- S1: shared helper note, and the rc 1 comment postcondition.
- S2: files (+`gitlore_prepare_merge`, marker/complete, `index-compose.sh`,
  `index_compose.bats`). Fixture gets one arrival per defect kind.
  Postconditions: byte identity per kind, `problems` after interrupted
  preparation, compose refusal on the pin, failed preparation leaves the tier on
  the pin. "Nothing staged in the memory store" clarified.
- S3: files (+`gitlore_recover_stale_no_merge_head`, `resolve_recovery.bats`),
  closing-line postcondition, aborted/never-run recovery returns to the pin.
- S5: merger `target_ref` sha, and the merge skill's Diverged section.
- S6: m4 resting exception, and `merge-state-recovery.md`.
- Dependencies: S1 helper edge, executor owns both resolve scripts.
- Scope OUT: the ordinary-merge entry-wise line loss (pre-existing).
- Risks: entry-wise risk restated as verified. Added in-session compose, resting
  consumer, landed-merge scan and pre-push residual. Concurrency risk broadened.
- Open questions 4 and 5 added. Questions 1–3 are untouched.

## Positive Observations

- K1's alternative analysis is accurate: a repair commit on top of the arrival
  would classify as `stale-no-merge-head` and be dropped.
- K2's attribution rule is grounded. Rules 2 and 3 carry no file prefix, and
  `gitlore_compose_check_index` prefixes every rule 1/4/6 line with the file
  path.
- K4 correctly notes that `gitlore_compose_up` checks before it writes, so the
  gate needs no second check pass.
- K5 is correct that pin refusals abort earlier, so rc 1 reaches the arm only
  from `gitlore_compose_check`. `commit-memory.sh:66` shares the body.
- S4's `|| rc=$?` contract captures status 2, which `if !` would lose.
- Postconditions are stated as contracts, not code.

## Recommendations

- Settle open questions 1–5 before `/runbook`. Question 4 decides whether S2
  also touches the take's fetch ordering.
- Schedule the ordinary-merge entry-wise line loss as its own defect. Once the
  pin guard and byte identity land, it is the one remaining silent deletion in
  the merge path.
- The S2 fix for the entry-wise pass is not prescribed. Skipping the pass when
  authority equals base is the smallest shape, since the pass then has nothing
  to add. The runbook should pick one.

---

**Ready for user presentation**: Yes. The fixes are applied, and open questions
1–5 need my human partner's call.
