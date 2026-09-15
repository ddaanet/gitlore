# Phase 4 checkpoint corrector: per-arm exits and the rest guard (S4), with the final lifecycle audit

**Scope**: `git diff af79f3f..HEAD` (Phase 4). The exit paths were read together
with Phase 3's continuation gate. The lifecycle audit covers
`git diff e60ff38..HEAD -- scripts tests` (Phases 1-4). **Mode**: review + fix,
nothing committed.

**Overall**: Ready. Phase 4 matches S4 and the item's Interfaces line, with the
remedy's second line changed as the Item 4.1 code review recorded. Probes found
two defects on the re-run paths and both are fixed, each with a test that was
red before the fix. One residual is left for design follow-up: after a refused
local `live` update, nothing re-derives the rest.

## Issues found

### Major

1. **`/gitlore:resolve` published memory's pointer before the tier it points
   at.**
   - **The defect**: `resolve.sh` default mode ran `check_store_gates` for
     memory first and for the tiers after. A tier merge's continuation writes a
     memory bookkeeping commit that records the merge, and memory's local `live`
     advances with it. If the tier's own push then fails, re-running
     `resolve.sh` (the skill's Loop step) pushed memory's `live` to origin, and
     only then was the tier's push refused again. Memory's remote was left
     recording a tier commit that the tier's remote does not have. D17's
     lockstep and `gitlore_push_stores` both publish tiers first.
   - **Probed**:
     - Path C (tier origin declined, merge adopted): after `resolve.sh`, the
       memory remote's `live:ddaanet` was the merge, and
       `git cat-file -t <merge>` on the tier remote failed.
     - Path A (tier `live.lock` held, merge adopted): same result.
     - It also happens without Phase 4: any tier push failing after a memory
       commit that records it.
   - **Why it matters here**: Phase 4's status-2 exits make "re-run
     `resolve.sh`" the next step after a declined or locked tier push.
   - **Fix**: `scripts/resolve.sh` default mode now runs the tier loop first,
     then `check_store_gates "$mempath"`. The comment gives the reason.
   - **Test**: `tests/tier_divergence.bats` "the standalone resolver publishes
     no memory pointer ahead of a tier it could not publish". Red on the
     unchanged script at its last assertion (memory remote `live` unchanged).
     Green after the fix.
   - **Behavior change for prose**: when memory and a tier both need a yield,
     the tier's directive now comes first.
   - **Status**: FIXED

### Minor

1. **A refused merge commit leaked its message temp file.**
   - **The defect**: `merge_msgfile` (`$TMPDIR/gitlore-merge-msg.*`) was removed
     only after a successful `commit`. Under errexit, a failing commit exited
     the script before the `rm`. The leak predates this job, but it is inside
     the lifecycle audit.
   - **Fix**: both the message write and the commit carry
     `|| { rm -f "$merge_msgfile"; exit 1; }`. The merge state, `MERGE_HEAD` and
     the pending ref are kept as before.
   - **Test**: `tests/resolve_compose.bats` "a refused merge commit leaves no
     message file behind and keeps the merge for a rerun". A `commit-msg` hook
     in the tier refuses the commit. The test asserts no `gitlore-merge-msg.*`
     in `TMPDIR`, that the state file and `MERGE_HEAD` are kept, and that the
     rerun lands once the hook is gone. Red on the unchanged script at the
     `find` assertion.
   - **Status**: FIXED

## Q1: exit paths after the merge commit, and whether re-runs converge

At every exit below, the merge commit has landed and the continuation has
already cleared the merge state file and the pending ref. `MERGE_HEAD` went with
the commit. Item 3.1's refusal exits before any of that happens (see the
lifecycle table).

| Path | State at exit | Output | Re-run |
|---|---|---|---|
| **A**: local `. HEAD:live` status 2, tier adopted (or a memory-root merge) | Tier HEAD is the merge and tier `live` is the old commit. Root adopted. For a tier merge, memory's bookkeeping is committed and memory `live` follows it. | git's message only, under `pushing '. HEAD:live' in <abs store> failed, and not because of divergence` | `/gitlore:push` and `pre-push`: `gitlore_repair_stranded_live` advances `live`, then tiers publish before memory. Converges. `/gitlore:merge`: the stranded-live repair, then "already holds everything". Converges locally. `resolve.sh`: while the lock is held, exits 1 on the tier with memory unpublished (after fix 1). Once the lock is gone, it converges. |
| **B**: local status 2, tier unadopted | Tier HEAD is the merge and `live` is old. Root untouched. Memory has an unstaged gitlink change (` M ddaanet`). | The compose refusal lines, git's message, then the four-line remedy | Following the remedy then `/gitlore:merge` adopts (slice 3). The remedy stays valid after any detour. **Residual:** see below. |
| **C**: origin status 2, tier adopted | Tier HEAD and `live` are the merge. Memory bookkeeping is committed. Tier origin is unmoved. | git's message | Every publisher retries the tier push and exits 1 while the decline lasts. Memory is not published ahead of it (fix 1). |
| **D**: origin status 2, tier unadopted | Tier on its pin, `live` is the merge. Root untouched. | git's message, then `gitlore: tier '<t>' is back on the commit the memory store records; its local 'live' keeps the merge. Fix the store, then run /gitlore:merge to adopt the merge into the root index.` | The resting shape. After the root fix, the take adopts. `resolve.sh` exits 1 on the tier gate with its "run /gitlore:merge to adopt them" remedy. |

**No state wedges.** One path does leave a state that later commands do not
diagnose: path B with the agent skipping the remedy.

- **What the probe found** (lock removed after the continuation):
  - `resolve.sh` exits 0 with `gitlore: state is healthy. Nothing to do.` Tier
    HEAD, tier `live` and the tier remote are all the merge, and root is still
    unadopted.
  - `merge-memory.sh` twice prints
    `gitlore: tier 'ddaanet' — already holds everything its remote does.` and
    `gitlore: the memory store has uncommitted changes. …`.
  - `push-memory.sh` prints
    `gitlore: NOT published — uncommitted changes remain in: memory. …`.
  - A memory commit meets the pin guard's "ahead of the pin … no automatic
    remedy" text.
- **What still recovers it**:
  - The printed remedy, at any point: line 1 is a no-op success, line 2's
    ancestry check passes, and the checkout rests the tier.
  - SessionStart's `submodule update`, which reaches the same resting state.
- **What does not**: no command after the continuation re-derives the rest.
  Closing that would need a take that rests a clean tier ahead of its pin when
  its `live` contains HEAD. That changes the pin guard's "no automatic remedy"
  design, so it is recorded here and not fixed.

## Q2: callers of default mode after the status-2 change

- **Who calls default mode**: only `skills/resolve/SKILL.md`. No hook calls
  `scripts/resolve.sh`: `pre-commit`, `pre-push`, `merge-memory.sh`,
  `push-memory.sh`, `commit-memory.sh` and SessionStart source
  `scripts/lib/resolve.sh`. `push_or_report` and `check_store_gates` exist only
  in `scripts/resolve.sh`.
- **Exit status and stderr order**: unchanged. The message is still emitted
  inside `push_or_report`, and the caller exits 1 right after. The removed
  `exit 1` ran at the same point.
- **errexit**: the old `if !` and the new `|| rc=$?` both suspend errexit in the
  body.
- **`rc`**: local in `check_store_gates`. In the continuation it is a global,
  and `compose_merged_indexes` declares its own local `rc`, so the two do not
  collide.
- **Slice 4** pins the `*)` arm's absence.
- The only order change is fix 1's store order.

## Final lifecycle audit (Phases 1-4)

| Object | Created by | Success path | Failure paths | Killed |
|---|---|---|---|---|
| `MERGE_HEAD` / `MERGE_MSG` | merge preparation | cleared by the continuation's `commit` | kept on the merged-index refusal (3.1), on a staging failure (errexit before the commit) and on a refused commit (fix 2); then re-emitted by every gate | kept, and the gates re-emit the directive |
| Merge state file | preparation | `gitlore_clear_merge_state` after the commit and bookkeeping | kept on every pre-commit exit; cleared before the status-2 exits (the merge landed) | between the commit and the clear, the stale state without `MERGE_HEAD` → `gitlore_recover_stale_no_merge_head` (existing) |
| `$GITLORE_PENDING_REF` | preparation | `update-ref -d` right after the clear | kept wherever the state file is | a leftover ref after the clear is inert (existing) |
| Staged content | merger `add -A`; `compose_merged_indexes` `add` | committed; a tier merge's pair committed by bookkeeping, or left staged when root was dirty before | 3.1 refusal: the merger's staging kept, and the continuation's own `add` never runs. Unadopted: tier staged and committed, root untouched. Phase 1 abort: `gitlore_stage_landed_tiers` staging kept, covered by the restamp | as on failure |
| Approval `$msgfile` | user approval | removed by the commit path (existing) | Phase 1 abort and failed status read: `touch` (restamp). Phase 3's not-fresh-arm directive: no touch, deliberately, since a restamp would make an unapproved summary read as fresh | untouched |
| `merge_msgfile` (`$TMPDIR/gitlore-merge-msg.*`) | continuation | `rm` after the commit | a refused write or commit now removes it (fix 2); before the `mktemp` (3.1 refusal) it never exists | leaked (tmp) |
| Bookkeeping msgfile (`gitlore-tier-msg.*`) | `gitlore_commit_tier_bookkeeping` | removed | removed on a commit failure | leaked (tmp) |
| `gitlore-repair.*` scratch dir (tier gitdir) with `index`, `arrival`, `pin` | `gitlore_adopt_repair_arrival` | `rm -rf` before `push . R:live` | `rm -rf` on every read, rewrite, recheck or build failure before any walk-back. Every step is an `if`/`elif` condition, and the caller's `\|\|` suspends errexit, so none bypasses the `rm` | left inert; nothing reads it (accepted, Phase 2) |
| `$scratch/index.lock` | `read-tree` / `update-index` under `GIT_INDEX_FILE` | released by git | released by git, or removed with the scratch dir | inside the scratch dir |
| `.gitlore-repair-index.*` | `gitlore_repair_index`, next to `<file>` (inside the scratch dir in production) | renamed over `<file>` | `rm -f` on a failed `cp`, `printf` or `mv` | inside the scratch dir |
| R's objects | `hash-object -w`, `commit-tree` | reachable from `live` | unreachable when `push . R:live` is refused; left for gc (K1) | same |
| `refs/heads/live.lock` | git, inside `push .` | released | released by git on refusal; gitlore never creates or deletes it (tests hold one) | a stale lock is a user remedy, shown in git's message |
| Tier `live` / HEAD after a status 2 | continuation | A and C: HEAD is the merge. D: HEAD is the pin and `live` is the merge | B: HEAD is the merge and `live` is old, with the printed remedy | n/a |
| `GITLORE_TAKE_IN_PUSH` | a prefix assignment on `gitlore_merge_stores` | scoped to that call | scoped | n/a |

Nothing is half-written on any success path. Every object a failure keeps comes
with a stated recovery: the re-emitted directive, the restamp, a printed remedy,
SessionStart or gc.

## Probes

The probes ran as temporary tests in a copy of `tests/resolve_compose.bats`,
which was then deleted:

- **A**: adopted, `live.lock` held, `resolve.sh` with the lock still held.
- **B1**: unadopted, lock removed, then `resolve.sh`, `merge-memory.sh` twice,
  the root fix and `push-memory.sh`.
- **B2**: unadopted, lock removed, then `push-memory.sh` (stranded-live repair,
  then publish).
- **C**: adopted, tier origin declined, then `resolve.sh`.

A and C were re-run after fix 1: the memory remote no longer records the merge.

## Verification

- `shellcheck -x scripts/resolve.sh tests/resolve_compose.bats tests/tier_divergence.bats`:
  clean.
- `scripts/run-bats.sh`, one file at a time:

  | File | Passed | Failed |
  |---|---|---|
  | `tests/resolve_compose.bats` | 23 | 0 |
  | `tests/tier_divergence.bats` | 20 | 0 |
  | `tests/resolve.bats` | 8 | 0 |
  | `tests/resolve_both_flavors.bats` | 4 | 0 |
  | `tests/resolve_recovery.bats` | 23 | 0 |
  | `tests/push_rejection_discriminator.bats` | 9 | 0 |

- Each new test was run red against the unchanged script first, at its intended
  assertion.

## Changed files

- `scripts/resolve.sh`: default-mode store order; `merge_msgfile` cleanup on a
  refused commit.
- `tests/tier_divergence.bats`: one test.
- `tests/resolve_compose.bats`: one test (now 650 lines; its split is already
  deferred).

## UNFIXABLE

None.

## REFACTOR-NEEDED

None. One residual needs a design call (Q1, path B): a take or gate that rests a
clean tier found ahead of its pin when its `live` contains HEAD. It would
replace the pin guard's "no automatic remedy" for that sub-case.

## Also noted, not fixed

`resolve.sh`'s "remote has no live branch. Pushing." step pushes memory's `live`
before any tier gate. This only happens on a memory remote that has never been
published, where the same ordering concern applies. It was not probed.

## For the prose phases (5-7)

1. **Status-2 refusal** (both continuation push sites and both default-mode
   gates):

   ```
   gitlore: pushing '<push args>' in <store> failed, and not because of divergence — no merge can fix this. git said:
   <git's own output>
   ```

   - `<push args>` is `. HEAD:live` or `origin live`.
   - `<store>` is absolute in the continuation (from the state file) and
     `.gitmodules`-relative (`memory/ddaanet`) in default mode.
   - The merge has landed. Exit 1 here does not mean an unlanded merge, unlike
     the merged-index refusal. `agents/memory-merger.md` turn 2's "Otherwise
     quote every `gitlore:` line" already covers it.
2. **Path B remedy**, verbatim. Line 2 is the Item 4.1 code review's version,
   not the runbook's:

   ```
   gitlore: tier '<t>' stays on the merge commit because its local 'live' does not hold it. Run:
   gitlore:   git -C "<abs>" push . HEAD:live
   gitlore:   git -C "<abs>" merge-base --is-ancestor HEAD live && git -C "<abs>" checkout --detach <pin>
   gitlore: then fix the problems listed above and run /gitlore:merge.
   ```

   - `skills/resolve/SKILL.md`: the Loop re-runs `resolve.sh`, which can exit 0
     "healthy" before the remedy has run (Q1). The Summarize step must relay
     these lines as still to run, not as resolved by the Loop.
3. **Path D**: the rest line quoted in the Q1 table. D52 and `tier-stores.md`
   (the rest guard as the third resting exception) should say the tier rests on
   its pin only when its `live` holds the merge.
4. **Default-mode store order**: `/gitlore:resolve` gates every tier before
   memory, the publish order of D17 and `gitlore_push_stores`. When memory and a
   tier both diverged, the tier's directive comes first. This deserves a
   changelog line. No doc found stating the old order.
5. **A refused merge commit** (a hook, for example) keeps the merge prepared; a
   rerun of the continuation lands it. The existing recovery docs need no
   change.
