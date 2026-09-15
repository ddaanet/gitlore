# Phase 3 checkpoint corrector: continuation gate (S3)

**Scope**: `git diff 2edbd1b..HEAD` (`scripts/resolve.sh`
`compose_merged_indexes`, `tests/resolve_compose.bats`), checked against K4 and
against the Phase 1 commit path and the Phase 2 take. **Mode**: review + fix,
nothing committed.

**Overall**: Ready. The gate matches K4 and the Interfaces line, and its
lifecycle is clean. One Major seam, in the Phase 1 commit path, is fixed. One
K1/K4 interaction had no test and now has one. Two stale comments about how a
store ends up with no root index are corrected. The loop that follows a refusal
ends only by agent judgement; nothing in the code bounds it (see Residuals).

## Issues found

### Major

1. **An unapproved parent commit over a kept tier merge asked the user for a
   summary instead of re-emitting the directive.**
   - **Cause**: a prepared tier merge moves the tier's gitlink, so memory reads
     dirty (`git status --porcelain` → ` M ddaanet`). In
     `gitlore_sync_memory_to_live`, the freshness refusal came before the
     per-tier stale-merge loop, so an unapproved commit printed
     `gitlore: memory is dirty and has no approved commit summary. Prepare a summary and present it to the user …`
     along with the memory-writing clause. That puts a merge in front of the
     user, against D49. Even after approval, the retry stops on the directive.
     Probed: with fresh approval, `pre-commit` re-emitted the directive, and
     `pre-push` and `merge-memory.sh` did too.
   - **Why Phase 3 widens it**: the ordering is older than this job. But a
     refused continuation makes a kept, synthesized tier merge a state that
     persists, rather than the brief window between a preparation and its
     continuation.
   - **Fix**: `scripts/lib/resolve.sh`, in the not-fresh arm only. The arm runs
     `gitlore_guard_stale_merge_state` over every materialized tier before it
     prints the approval refusal. The fresh path is unchanged: a recovery that
     composes up still runs after the freshness read, so it cannot make an
     approval already given read as stale.
   - **Test**: `tests/resolve_compose.bats` "a refused tier merge answers an
     unapproved parent commit with its continuation directive". A mutation run
     against HEAD's `scripts/lib/resolve.sh` fails on
     `[[ "$all" == *"memory merge prepared"* ]]`; the file was restored and
     checked with `cmp`.
   - `commit-memory.sh` keeps its own up-front `-m` check ("memory is dirty;
     commit-memory needs an approved summary"). Its callers always pass a
     summary, and with one it reaches the same directive. Left as is.
   - **Status**: FIXED

### Minor

1. **Stale comments on how a store ends up rootless.** `scripts/resolve.sh` (the
   staging tail of `compose_merged_indexes`) and the rootless test in
   `tests/resolve_compose.bats` both said an empty auto-memory dir seeds a store
   with no root index. `scripts/install/init-submodule.sh` scaffolds `MEMORY.md`
   for an empty dir, a missing dir or a migration stub. Both comments now name
   the reachable causes. The function header's EXITS line now notes that a store
   with no root index runs no check.
   - **Status**: FIXED

## Coverage added

- "a tier merge whose incoming side welds a line is refused, and the split
  synthesis publishes" (see Q2). This is a guard: it holds on HEAD.

## Q1: a refused merge, and what the merger loop does next

- **Refusal output**: see the quotes under "For the prose phases" below. It
  lists only the problems attributed to the merged index. Everything else
  `gitlore_compose_check` found is withheld, and the landed merge reports it on
  the next continuation.
- **Is it actionable?** Yes, in every case. Rules 1, 4 and 6 are properties of
  the named file's own text, and that file is in the merger's store, so an edit
  to the named lines always clears it. A synthesis is never unrepairable in the
  way an arrival can be.
  - A memory-root merge can be refused for a defect both sides already carried.
    The named `MEMORY.md` then need not appear in `changed_files`, and the
    merger must edit it anyway.
  - Conflict markers left in a pointer block fail rule 4, so they are refused
    too.
- **Re-emission**: after the refusal, a second call to `resolve.sh` in default
  mode runs `gitlore_guard_stale_merge_state` → `stale-with-merge-head` → the
  same directive, exit 1. Slice 2 covers the memory store; probe P3 confirmed
  the tier case. `pre-push`, `merge-memory.sh` and `pre-commit` (after the fix
  above) re-emit it the same way. SessionStart skips a tier holding merge state
  and tells the agent to run `/gitlore:resolve`.
- **Does the loop end?** Only by agent judgement, and the current prose makes
  that less likely:
  - The re-emitted directive does not carry the problem lines. A fresh merger
    dispatched from it reads a carrier with no markers and can honestly answer
    `No conflict.`; approval then brings the same refusal back. Nothing in the
    code counts cycles.
  - `agents/memory-merger.md` turn 2 says a composition refusal "does not mean
    the merge failed".
  - `skills/resolve/SKILL.md` Loop re-runs `resolve.sh` after the sub-agent
    exits, which re-dispatches without the problem lines, and its Summarize says
    "The merge landed either way".
  - **Who learns**: the parent agent sees each refusal on the merger's turn-2
    report. The user learns only through the parent's relay.
  - The stop has to come from S5 (see prose items 2–4).

## Q2: Phase 2 repair against a tier merge

- A tier merge is refused where a take would repair. That is K4 as designed:
  "what this repo authors (a commit, a synthesis) is refused and re-authored;
  what arrives is repaired". K7 names "a mechanical repair of a merge synthesis"
  as a rejected alternative. The merge does not need the repair.
- **Probed** with a diverged tier whose remote pushed a welded line:
  - The entry-wise pass (`gitlore_merge_indexes`) carries the welded line
    through as one bullet for its first path. The prepared carrier holds
    `- [their fact](t.md) — theirs- [their other](u.md) — also theirs`.
  - The gate refuses it, naming `u.md`.
  - After the split synthesis, the continuation exits 0 and the tier remote's
    `live:MEMORY.md` carries the split line. Under a publishing flavor, the fix
    reaches upstream in the same push.
  - Now locked in by the test above.
- Duplicates and interleaved lines on the incoming side mostly never reach the
  synthesis: the entry-wise pass keys on path and keeps bullets only. That is
  the separately tracked "entry-wise pass drops interleaved lines" defect, not
  this job's.

## Q3: Phase 1 commit path over a kept merge

- The problem check never sees the staged synthesis.
  `gitlore_guard_stale_merge_state` runs first:
  - for memory, at the top of `gitlore_sync_memory_to_live`;
  - for tiers, in the dirty branch, and (after the fix) ahead of the approval
    refusal.
  - It returns 1 with the directive, before `gitlore_compose` or its rc-1 abort.
- Memory-root refusal: memory status `M  MEMORY.md`. `pre-commit` re-emits the
  head-vs-live directive, and nothing is composed or committed.
- Tier refusal: see Major 1.
- `MERGE_HEAD` survives: no commit-path step before the guard checks anything
  out.

## Lifecycle on the refusal path

| Object | After a refusal |
|---|---|
| Merge state file (store's gitdir) | kept (slices 1, 4) |
| `MERGE_HEAD` / `MERGE_MSG` | kept; the exit precedes the commit, and no checkout runs |
| `$GITLORE_PENDING_REF` | kept (its `update-ref -d` comes after the commit) |
| Staged synthesis | kept, exactly as the merger's `add -A` left it; the continuation's own `add -A` never runs |
| Root `MEMORY.md` (worktree and index) | untouched: `gitlore_compose_up` rc 1 returns before `gitlore_compose_write`; the file is byte-identical in slice 1 |
| Memory HEAD, tier HEAD, `live`, origin | unmoved |
| `merge_msgfile` temp | never created (the `mktemp` comes after compose) |
| `tier_unadopted` rest | not reached |

Nothing is half-written. The rerun after a fix lands (slice 3).

## The rootless-store gap (recorded in the Item 3.1 code review, not fixed)

- **Reachability**: rare, but reachable.
  - `init-submodule.sh` scaffolds `# Memory Index` when the auto-memory dir is
    missing, empty or a migration stub (`docs/references/installation.md` step
    7: "the scaffold is never skipped").
  - It copies a non-empty dir verbatim. A dir holding files but no `MEMORY.md`
    therefore seeds a rootless store. CC's auto-memory keeps `MEMORY.md` as its
    index, so that input is atypical.
  - The other route is a root index deleted by hand and committed.
  - No gitlore script deletes the root index, and none recreates it: not
    `add-tier.sh`, not SessionStart.
- **Breadth**: the gap covers the whole store, not just S3.
  - `gitlore_compose` has the same `[ -f "$root" ] || return 0`, so S1
    prevention never runs.
  - The take's adoption goes through `gitlore_compose_up`, so S2 neither refuses
    nor repairs a defective arrival. It is adopted as-is.
  - A rootless store runs no index check on any path. The continuation prints
    `gitlore: the memory root <abs> has no MEMORY.md, so no tier lines can compose into it. The merge is committed regardless; create the root index (`#
    Memory Index`) and edit it to trigger composition.`

## Residuals (not fixed)

- **No mechanical bound on refuse/re-synthesize cycles** (Q1). A retry cap or
  problem lines in the re-emitted directive would be a design addition; the
  prose route below is K4's intended stop.
- **`tests/resolve_compose.bats` is now 498 lines**, over the 400-line soft cap.
  This sits with the deferred file-size splits.

## Verification

- `shellcheck scripts/resolve.sh scripts/lib/resolve.sh tests/resolve_compose.bats`:
  clean.
- `scripts/run-bats.sh`, one file at a time:

  | File | Passed | Failed |
  |---|---|---|
  | `tests/resolve_compose.bats` | 17 | 0 |
  | `tests/tier_divergence.bats` | 19 | 0 |
  | `tests/commit_memory.bats` | 35 | 0 |
  | `tests/git_hook_pre_commit.bats` | 20 | 0 |
  | `tests/tier_lockstep.bats` | 14 | 0 |

- **Mutation run**: HEAD's `scripts/lib/resolve.sh` fails the new commit-path
  test on its directive assertion. The file was restored and checked with `cmp`.
- **Probes** ran as temporary tests inside `tests/resolve_compose.bats`, then
  were removed. Two became the tests above.

## Changed files

- `scripts/lib/resolve.sh`
- `scripts/resolve.sh` (comments only)
- `tests/resolve_compose.bats`

## UNFIXABLE

None.

## REFACTOR-NEEDED

None new.

## For the prose phases (5-7)

1. **Exact refusal output.** Paths are the parent-relative spelling from
   `.gitmodules`, because the continuation runs from the parent root:

   ```
   gitlore: the merged index fails the check, so the merge was not committed; the merge stays prepared for a new synthesis:
   gitlore:   memory/ddaanet/MEMORY.md: duplicate pointer path t.md
   gitlore:   memory/ddaanet/MEMORY.md: line 6 welds two pointer bullets onto one line — u.md is invisible to every parse and the next compose will drop it; split them
   gitlore:   memory/MEMORY.md: interleaved non-bullet line <n> inside the pointer block
   ```

   Only merged-index problems are listed. Do not promise that the refusal names
   every problem in the store.
2. **`agents/memory-merger.md` turn 2**: "a composition refusal … does not mean
   the merge failed" is false for this header. Exit 1 with it means the merge
   did not land. The merger should quote the lines and stop.
3. **`skills/resolve/SKILL.md`**:
   - Answer that exit by resuming the *same* merger with `rejected:` plus the
     problem lines, before the Loop step. A re-run of `resolve.sh` re-emits a
     directive without them, and a fresh dispatch can answer `No conflict.` into
     the same refusal.
   - Summarize's "The merge landed either way" must separate problems that
     blocked landing from problems reported after it.
   - Consider a stop, such as surfacing to the user when the same problem line
     returns after a re-synthesis. Nothing in the code stops it.
4. **The merger may have to edit a file outside `changed_files`**: a memory-root
   refusal can name a root `MEMORY.md` defect both sides already carried.
5. **`skills/merge/SKILL.md` Diverged step 2** is already consistent: the same
   store returning the same block is continued, never discarded.
6. **`docs/references/index-composition.md`** (continuation paragraph) and
   **D52**:
   - A tier merge is refused for carrier problems. A memory-root merge is
     refused for root rules 1, 4 and 6.
   - Everything else lands, as before: tier rested, or committed uncomposed with
     `gitlore: tier composition refused — the merge is being committed uncomposed. …`.
   - A defect arriving on the far side of a divergence reaches the synthesis,
     not the repair.
7. **Commit gate (D50 / `commit-gate.md`)**: a dirty memory store with no fresh
   approval now meets a tier's prepared-merge directive before the summary
   request.
8. **Rootless stores**: say that a store with no root `MEMORY.md` runs no index
   check at all (S1, S2 or S3), if the docs claim any of the three
   unconditionally.
