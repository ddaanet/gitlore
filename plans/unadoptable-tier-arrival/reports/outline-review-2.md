# Outline Review 2: unadoptable-tier-arrival (post-proof, commit-shaped)

**Artifact**: plans/unadoptable-tier-arrival/outline.md **Date**: 2026-09-14
**Mode**: review + fix-all, settled decisions K1–K7 not reopened
**Requirements source**: deliverable-review Major 1
(`plans/index-edit-propagation/reports/deliverable-review.md`), minor-pass-2
code m4 (`plans/index-edit-propagation/reports/minor-pass-2.md`)

## Summary

The commit-shaped outline is sound, and most of its claims check out against the
code. Four gaps would have shipped defects:

- K1's write-then-commit shape strands a take that is killed between the two
  steps (probed).
- The push's `behind` arm skips the tier push after a take, so R's gitlink goes
  out before R does.
- K5 checked dirtiness per tier where the decision is per index file.
- The residual weld-guard case kept the original misattributed message.

All four are fixed inside the settled decisions. One finding needs my human
partner's call (escalation E1). The outline is 340 lines.

**Overall Assessment**: Ready, pending E1 and confirmation of K1's mechanism
line (Major 1 below).

## Requirements Traceability

| Requirement | Outline Section | Coverage | Notes |
|---|---|---|---|
| Major 1: a defective arrival wedges every push | Approach 2, K1–K3, K6, S2 | Complete after fix | the push lockstep gap in the `behind` arm is fixed (Major 2) |
| Major 1: the message names a clean worktree file | K2, S2 | Complete after fix | it persisted for the guarded-weld residual; the report now attributes problems to the arrival in `live` |
| Major 1: upstream publishes because rc 1 is advisory | Approach 1, K5, S1 | Complete after fix | the per-tier vs per-file inconsistency is fixed (Major 3) |
| m4: distinct `push_or_report` status, per-arm rest | Approach 3, S4 | Complete | remedy wording fixed (Minor 6) |
| m4: name the third resting exception in tier-stores.md and the changelog | S6 | Complete after fix | now explicit |
| Continuation refusal for the merged index (partner's addition) | K4, S3 | Complete after fix | inversion of the existing test named |
| Fetch-first (partner's addition) | S2 | Complete | its doc paragraph added to S6 |
| S7 memory fact | S7 | Complete | publication wording aligned with K6 |

**Traceability Assessment**: every requirement is covered. The gaps were fixed.

## Scope-to-Component Traceability

| Scope IN Item | Component | Notes |
|---|---|---|
| Prevention | S1 | the helper moved to `index-compose.sh`, with a unit-test home |
| Mechanical repair in the take | S2 | `gitlore_push_stores` `behind` arm added; test homes corrected |
| Continuation gate | S3 | — |
| m4 exits and rest guard | S4 | — |
| Agent prose | S5 | — |
| Design records | S6 | fetch-first paragraph, continuation gate in D52, line reference corrected |
| Memory fact | S7 | — |

**Scope Assessment**: no orphans.

**Cross-component interfaces**:

- S1's helper consumes `gitlore_compose_check` output plus the `$mempath`
  spelling. S2 feeds it `gitlore_compose_up` rc 1 output, and S3 feeds it
  `compose_merged_indexes`' `composed`. Both are check output verbatim.
- The rc 2 text (`could not write <file>`) carries no `<file>:` prefix, so it
  cannot be misattributed.
- `gitlore_repair_index` needs the tier's file list for the weld guard, so its
  signature gained `<tier-dir>`.

## Verified claims (against code)

- **K2 attribution:** rules 1, 4 and 6 print `"$file: …"`, with `file` being
  `$mempath/MEMORY.md` or `$mempath/$tier/MEMORY.md`. Rule 2
  (`the tier manifest lists …`) and rule 3 (`root index line …`) print no prefix
  (`index-compose.sh:166-237,255-285`).
- **K1 precondition:** both take paths leave the tier's HEAD and `live` on the
  arrival before `gitlore_adopt_tier_into_root`. The remote path pushes
  `$remote:refs/heads/live` and checks out `live`. `gitlore_adopt_advanced_live`
  checks out `live`.
- **K5:** `gitlore_compose` rc 1 writes nothing. The rc 2 arm restamps with
  `touch "$msgfile"`. `pre-commit` and `commit-memory.sh` both reach
  `gitlore_sync_memory_to_live`. The pin guard aborts earlier, so rc 1 comes
  only from `gitlore_compose_check`.
- **Problem statement:** the take refuses a dirty tier. The pin guard's "ahead"
  arm refuses a tier at `live`. `memory-pre-commit` blocks a naked tier commit.
  `gitlore_push_stores` retakes when `live` is ahead.
- **K4/S3:** the continuation calls `compose_merged_indexes` bare
  (`scripts/resolve.sh:253`). Exiting inside it before the commit keeps the
  state file and `MERGE_HEAD`. `gitlore_guard_stale_merge_state`'s
  `stale-with-merge-head` arm re-emits the continue-after-merge directive.
- **S4:** `push_or_report` exits 1 today on a non-divergence refusal
  (`scripts/resolve.sh:226-242`), before `rest_unadopted_tier` runs.
  `check_store_gates` calls it as `if !`.
- **Numbering and size:** D52 is unused, since `decisions.md` ends at D51.
  `design.md:232` is the D50 sentence. The fact file is 2492 bytes.
- **Weld detection** (probed with `gitlore_welded_path`): the check flags only a
  second link introduced by `- [`. `hook[B](b.md)` and `(a.md)[B](b.md)` are not
  flagged (see E1).

## Review Findings

### Critical Issues

None.

### Major Issues

1. **A take killed between the repair write and R's commit wedges the tier**
   - Location: K1 (canned `git commit`), "Interruption" bullet
   - Problem: I probed two ways of committing R in a scratch repo:
     - Writing the repaired carrier into the worktree, then committing.
     - Committing through a temporary index, so HEAD is R while the real index
       and worktree still hold the arrival.

     In both states, `git checkout --detach <pin>` fails with "Your local
     changes … would be overwritten". `submodule update` without `--force` runs
     that same checkout. So SessionStart cannot pin the tier, the pin guard then
     refuses every commit, and the take refuses the dirty tier. The
     "Interruption" bullet's claim was false for that window, and the same
     hazard hits the "check still refuses after the repair" walk-back if the
     worktree was written.

     A third probe used `commit-tree` from a temporary index, then
     `push . <R>:refs/heads/live`, then `checkout --detach live`. It succeeds,
     and a kill between the push and the checkout leaves a clean tier that
     checks out at the pin.
   - Fix: K1 now builds R with `commit-tree` from a temporary index in the
     tier's gitdir and advances `live` to R before the tier checks it out. The
     worktree never holds the repair uncommitted. Other changes:
     - The Interruption bullet is scoped to a kill before the up projection
       writes root. That later window predates this job.
     - The refused-update bullet and S2's matching postcondition now describe
       `live` being refused with the tier still on the arrival, and assert a
       clean worktree.
     - `commit-tree` runs no hook, so the sentinel sentence was removed.

     The decision itself (a plain commit on top of the arrival, inside the take)
     is unchanged. The mechanism line changed, so my human partner should
     confirm it.
   - **Status**: FIXED (mechanism line — confirm)

2. **A take inside a push's `behind` arm does not publish R before memory
   records it**
   - Location: K6, S2 take postconditions
   - Problem: in `gitlore_push_stores`, a tier push refused as `behind` runs
     `gitlore_merge_stores` and then an unconditional `continue`
     (`scripts/lib/resolve.sh:1342-1343`), skipping that tier's push. That was
     safe while a take only fast-forwarded to commits already on origin. With
     the repair, the take leaves R in `live` ahead of `origin/live`, and the
     bookkeeping commit records R's gitlink. Memory's push after the loop then
     publishes a pointer to a tier commit the tier remote lacks, which breaks
     the D17 lockstep. K6's "publishes R in that push" was false for this arm,
     and a defective remote arrival reaches exactly this arm on a push. This
     finding is from the source, not a probe.
   - Fix: K6 names both push arms and says the `behind` arm retries the tier
     push when the take left `live` ahead of `origin/live`. S2's files gain the
     `behind` arm. S2's postcondition asserts, for both arms, that the tier's
     origin holds R before memory's origin holds the gitlink.
   - **Status**: FIXED

3. **K5 checked dirtiness per tier, while the decision is per index file**
   - Location: K5 "Aborts", Approach 1
   - Problem: "a tier `gitlore_memory_dirty` reports dirty whose carrier has
     problems" aborts a commit that only touches a fact file, when the tier's
     unchanged carrier has a problem. The settled decision is "problems in any
     index file the commit changes", and root was already per-file.
   - Fix: K5 now aborts on a carrier with uncommitted changes
     (`status --porcelain -- MEMORY.md`), and a dirty tier with an unchanged
     carrier stays advisory. Approach 1's rationale sentence and an S1
     postcondition ("a tier dirty only outside its carrier commits and reports")
     were updated to match.
   - **Status**: FIXED

4. **The guarded-weld residual keeps the Problem's misattribution and wedge**
   - Location: K2, S2 "check still refuses", Risks
   - Problem: a weld the guard does not repair makes the take walk back. The
     report then names the worktree carrier, which is clean: the exact
     misattribution in the Problem statement. The Risk said "nothing is
     published", which understates it. Every take and push keeps failing until
     upstream edits the line.
   - Fix: K2 gains a bullet: problems the repair cannot fix are attributed to
     the arrival in `live`. The S2 postcondition asserts that wording and a
     clean worktree. The Risk now states the wedge plainly. The weld guard
     itself is untouched.
   - **Status**: FIXED

### Minor Issues

1. **S2 test homes wrong.** Take tests live in `tests/merge_memory.bats`, and
   push-take tests in `tests/push_behind_vs_diverged.bats`.
   `tier_divergence.bats` covers merge preparation. FIXED
2. **The S1 helper had no unit-test home** for its space-in-`$mempath` and
   prefix-tier cases. It moved to `index-compose.sh`, beside the format it
   parses, with `tests/index_compose.bats`. FIXED
3. **The `gitlore_repair_index` signature lacked the tier** needed by the weld
   guard, and did not say where the output goes. It is now
   `<file> <pin-carrier> <tier-dir>`, rewriting a scratch copy outside the
   worktree. FIXED
4. **K3's duplicate rule was ambiguous.** It did not cover more than two lines,
   say where the survivor sits, or say whether blank interleaved lines move.
   Now: the first line the pin lacks survives at its own position; the move
   covers non-blank lines only, as rule 4 flags them. The S2 "keeps the
   arrival's line" wording (both lines are the arrival's) is now "keeps the line
   the pin lacks". FIXED
5. **K4 "land and rest the tier" did not fit memory-root merges.** It now says a
   memory-root merge commits uncomposed, as now. FIXED
6. **S4's remedy skipped "fix the problems"**, and `/gitlore:merge` would refuse
   again without that step. Added to the remedy and to the postcondition. FIXED
7. **S3 did not name the existing test its gate inverts**: "a compose refusal is
   reported but never strands the merge" (`tests/resolve_compose.bats:241`). Now
   named. FIXED
8. **A dangling "(Q4)" reference** to an open question that no longer exists was
   removed. The fetch-failure fallback now says it still exits 1 as today. FIXED
9. **S1's first postcondition** did not assert that the output names the
   problem, or that memory stays uncommitted. Both added. FIXED
10. **S6 gaps.**
    - D52 omitted the continuation gate that K7 lists.
    - `tier-stores.md:117-119` ("at the head of every take") becomes false under
      fetch-first.
    - The rest guard was not called the third resting exception, as m4 asks.
    - The `index-composition.md` paragraph is at lines 116-120, not 117-120.

    All fixed. FIXED
11. **S7's "published by the next push"** contradicted K6, where a take inside a
    push publishes in that push. Aligned. FIXED

## Escalations (settled decisions — not edited)

**E1 — K3's no-marker weld split acts on lines the check never refuses.**

- **What the rule says:** K3 splits a weld "before the second link's `- [`, or
  before its `[` with `- ` added". S2 has a matching unit postcondition, "a weld
  with no `- ` marker".
- **What the check flags:** `gitlore_welded_path` flags only a second link
  introduced by `- [`. A line with a hook such as `see [x](y.md)` passes the
  check.
- **Why it matters:** once any carrier problem triggers the repair, this rule
  splits that legitimate hook link into a new bullet whenever `y.md` exists in
  the tier. That restructures a line nobody reported, beyond "the repair covers
  the carrier's lines" problem by problem.
- **Recommendation:** the weld rule acts exactly on what `gitlore_welded_path`
  reports. Drop the no-marker clause and its postcondition, or replace it with
  "a bare `[x](y.md)` in a hook is left unchanged".
- **The alternative:** keep the clause and extend rule 6 to flag the no-marker
  shape too. That is a check change with its own spurious-report surface, which
  the `gitlore_welded_path` comment already weighs.

The outline is unedited on this point.

## Fixes Applied

- **Approach 1:** the rationale sentence is now per index file.
- **K1:**
  - The opening sequence is now scratch repair, recheck, `commit-tree`,
    `push . <R>:refs/heads/live`, checkout `live`, retry.
  - New "worktree never holds the repair uncommitted" bullet.
  - Interruption scoped to a kill before root is written.
  - The refused-update bullet is rewritten.
  - The canned-commit and sentinel sentence was removed.
- **K2:** new bullet attributing unfixable carrier problems to the arrival in
  `live`.
- **K3:** signature `<file> <pin-carrier> <tier-dir>` and a scratch copy; rule 2
  covers non-blank lines; rule 3 generalized, with the survivor at its own
  position.
- **K4:** outside-problems wording covers the memory-root merge.
- **K5:** carrier-file dirtiness; the advisory arm includes a dirty tier with an
  unchanged carrier.
- **K6:** both push arms, and the `behind` arm's retry of the tier push.
- **S1:** files gain `index-compose.sh` and `index_compose.bats`; postconditions
  for the output, memory uncommitted, and a tier dirty outside its carrier.
- **S2:**
  - Files gain the `behind` arm; test homes corrected.
  - Duplicate postcondition reworded.
  - Publication postcondition covers both arms and ordering against memory.
  - Guarded-weld and refused-update postconditions assert a clean worktree and
    attribution to the arrival.
  - "(Q4)" removed; fetch-failure behaviour stated.
- **S3:** names the inverted existing test.
- **S4:** the remedy and its postcondition include fixing the problems.
- **S6:** D52 includes the continuation gate; fetch-first paragraph; third
  resting exception; line reference 116-120.
- **S7:** publication wording matches K6.
- **Risks:** the weld-guard residual is stated as a wedge with correct
  attribution.

## Positive Observations

- K2's prefix attribution rests on a real invariant of the check's output, and
  needs no parsing beyond an exact prefix.
- K4's "refuse what this repo authors, repair what arrives" line is consistent
  across K1, K3, K4 and S5.
- S4's `|| rc=$?` contract is correct. `if !` would lose status 2.
- Fetch-first removes the second-repair divergence for the resting consumers the
  incident actually produced.
- The postconditions are contracts, and each tdd item has a concrete
  git-observable assertion.

## Recommendations

- **Settle E1 before `/runbook`.**
- **Confirm K1's mechanism line** (`commit-tree` rather than a canned
  `git commit`).
- **S2 fixture:** assert the lockstep order by making the tier remote reject R
  (for example with a `pre-receive` hook). The push must then fail before
  memory's origin moves.
- **Pre-existing, out of scope:** a take killed after `gitlore_compose_up`
  writes root but before the pair is staged leaves root describing a tier that
  SessionStart pins back. The next compose projects it down and dirties the
  tier. Tracking it alongside the entry-wise defect would be reasonable.

## Incident during this review

A probe ran with `TMPDIR` unset in that shell, so its scratch path expanded to
empty, and `git -C ""` acted on the gitlore repository itself:

- It re-ran `git init`, which is harmless; the config contents are unchanged.
- The commit attempts were refused by the commit-msg hook.
- It created a local branch `live` at a dangling commit `6aef350`, whose parent
  is `914fec1` and whose tree is the current index.

Nothing else changed:

- `main`, the index and the worktree are unchanged.
- The memory store and the `ddaanet` tier are unchanged: HEAD, `live` and
  `origin/live` are equal, with no reflog entries today.
- Nothing was published.

Deleting the branch was denied by the permission classifier. To remove it:

```
git -C /Users/david/code/gitlore branch -D live
```

Check: `git -C /Users/david/code/gitlore branch --list live` prints nothing.

---

**Ready for user presentation**: Yes. E1, and confirmation of K1's mechanism
line, are for my human partner.
