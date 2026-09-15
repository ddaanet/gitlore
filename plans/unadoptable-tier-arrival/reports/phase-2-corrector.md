# Phase 2 checkpoint corrector — mechanical repair in the take (S2)

**Scope**: `git diff a4789af..HEAD -- scripts tests`, reviewed as a whole:
`gitlore_repair_index` and helpers, the repair arm of
`gitlore_adopt_tier_into_root`, the `gitlore_merge_one_store` reorder, and the
`behind` arm of `gitlore_push_stores`. It was checked against the outline's
K1/K2/K3/K6 and against Phase 1's commit path. **Mode**: review + fix, nothing
committed.

**Overall**: Ready. The per-item fixes fit together. The repair primitive's
contract matches how 2.2 calls it. Four seams were fixed (one Major, three
Minor), and one K6 path that had no test now has one.

## Contract: `gitlore_repair_index` as 2.2 calls it

| Contract point | 2.2's use | Holds |
|---|---|---|
| `<file>` rewritten in place; rename only on edit | `$scratch/arrival`, taken from `git show HEAD:MEMORY.md` | yes |
| `<pin-carrier>` may be missing, read as empty | `$scratch/pin` is written only when `rev-parse -q --verify <pin>:MEMORY.md` hits | yes |
| `<tier-dir>` is where a weld path must exist | `$tierpath`: the worktree, at HEAD (the arrival or the stranded `live`), clean because a take refuses a dirty tier | yes |
| rc 1 means unwritten and unchanged | leads to the "could not be rewritten" step message and a walk-back | yes |
| empty stdout means no edit | the recheck then reprints the same problems, and the unrepairable arm runs; an empty-body R is unreachable, since carrier-prefixed problems come only from rules 1/4/6 in `gitlore_compose_check_index` | yes |
| leaves on disk | its `.gitlore-repair-index.*` temp sits inside `$scratch`, which `rm -rf` clears on every path before any ref moves | yes |

## Issues found

### Major

1. **A take inside a push told the reader to run `/gitlore:push`.** The success
   line said "/gitlore:push publishes it" even when the take ran in either arm
   of `gitlore_push_stores`, which is already publishing it (K6). An agent
   relaying that line sends the user to run again what just ran.
   - **Fix**: `gitlore_push_stores` now runs both of its takes as
     `GITLORE_TAKE_IN_PUSH=1 gitlore_merge_stores …`. This uses the same
     prefix-assignment idiom as
     `GITLORE_MERGE_NO_PUBLISH=1 gitlore_yield_merge`.
   - Under that marker, `gitlore_adopt_repair_arrival` prints
     `gitlore: tier '<t>' — the repair is committed in its local 'live', and this push publishes it.`
     `/gitlore:merge` keeps the runbook's exact line.
   - **Tests**: both push repair tests now assert the push wording and the
     absence of `/gitlore:push publishes it`. Against HEAD's `resolve.sh`, both
     fail on that assertion (mutation run, restored and checked with `cmp`).
   - **Status**: FIXED

### Minor

1. **The unrepairable arrival's closing remedy pointed at the local store.** The
   unrepairable report says the index "must be fixed where it was published".
   The walk-back line after it ended "Fix the store, then run /gitlore:merge
   again.", which is the local-remedy reading K2 rules out ("never to the
   worktree carrier, which is clean").
   - **Fix**: `gitlore_adopt_walk_back_tier` takes an optional closing remedy
     (`$5`, defaulting to today's sentence). The unrepairable arm passes "Once
     the index is fixed where it was published, run /gitlore:merge again." With
     fetch-first, that take fast-forwards onto the upstream fix.
   - **Test**: "an arrival the repair cannot fix walks back and names upstream"
     asserts the new sentence and the absence of `Fix the store`. It fails
     against HEAD.
   - **Status**: FIXED

2. **The weld guard accepted a path that climbs out of the tier.** K3 splits
   only "when the welded path names a file in the tier".
   `[ -f "$tierdir/$wpath" ]` also accepted `../outside.md`, or any `..` route
   to an existing file.
   - **Fix**: new `gitlore_repair_tier_file`, which rejects a leading `/` and
     any `..` component before the `-f` test.
   - **Test**: `tests/index_compose.bats` "a weld whose path climbs out of the
     tier is left unchanged". It fails when the guard is reverted to the bare
     `-f`.
   - **Status**: FIXED

3. **The region read passed a process substitution to a function as a file.**
   The line was
   `read -r first last < <(gitlore_index_region <(printf '%s\n' "${p1[@]}"))`.
   It was the only `func <(…)` use under `scripts/`. It cost a subshell, a
   printf process and a re-read of lines already in memory, and bash 3.2's
   handling of it cannot be checked on this box.
   - **Fix**: the bounds are read off `p1` in the same shell, using the same
     bullet test `gitlore_index_region` uses. All 81 tests in
     `index_compose.bats` pass.
   - **Status**: FIXED

4. **The header comment on `gitlore_adopt_repair_arrival` omitted a kill
   state.** It said a killed take leaves the tier "on the arrival or its pin". A
   kill between `checkout --detach live` and the retry leaves it on the repair.
   Changed to "on the arrival, the repair or its pin".
   - **Status**: FIXED

### Coverage added

- `tests/push_behind_vs_diverged.bats`: "a repair resting on a root problem
  inside a push publishes nothing until it is fixed". This is K6's last
  sentence, which no test covered. The fixture is the live-ahead arm with a
  stranded duplicate plus a committed root `gone/x.md` line.
  - **First push**: exits 1, prints the repair line and no "publishes it", and
    puts R in `live` with the stranded commit as its only parent. The tier stays
    on its pin, and neither remote moves.
  - **After the root fix is committed**: the next push exits 0 with no second
    repair, and the snapshot hook shows the tier remote at R when memory's push
    fires. Memory's remote records R.
  - **Nature**: a guard. It holds on HEAD, and it goes red when the live-ahead
    take's `|| return 1` is dropped.

## Lifecycle

| Object | Success | Each failure path | Killed mid-repair |
|---|---|---|---|
| `$scratch` (`gitlore-repair.*` in tier gitdir), its temp index and the rewrite temp | removed before `push .` | removed before any walk-back | left behind, inert: nothing reads it, and it is not swept (accepted in 2.2) |
| tier `live` | R | arrival (read/rewrite/recheck/build fail, or `push .` refused); R (checkout or retry fail) | arrival or R |
| tier HEAD | R | pin via walk-back; on walk-back failure, a runnable absolute checkout command | arrival, R or pin; SessionStart's `submodule update` returns it to the pin |
| root `MEMORY.md`, staged pair | written, staged and committed (or staged when root was dirty before) | untouched: compose rc 1 writes nothing, and the retry's rc 1 or 2 never reaches staging | the window every take already has |
| memory `live` | follows the bookkeeping commit | unmoved | unmoved |

Interaction with Phase 1's commit path:
- **Resting tier** (on its pin, R in `live`, clean): the pin guard passes. The
  rc 1 abort ignores it, since the carrier is unchanged and
  `gitlore_sync_tiers_to_live` skips clean tiers. Fixing root and committing
  through the approved path is therefore not blocked, and the next take or push
  adopts R.
- **Adopted repair with a dirty root before the take**: the pair is staged at R.
  The pin guard reads `:tier` = R, and a later commit carries it.

Probed, no finding:
- **Fetch-first against a rested tier merge** (`rest_unadopted_tier`): a
  published merge M is an ancestor of `origin/live`, so adoption is skipped and
  the fast-forward reaches the same adoption with the same `head`. A no-publish
  M is not an ancestor, so it adopts as before.
- **Several tiers inside a push**: a repair of a tier later in the loop is
  published when the loop reaches it, because the refs agree and its `live` is
  ahead of `origin`. The residual is a race only: a tier already published
  earlier in the loop whose remote gains a defective arrival mid-push. The
  in-loop take would repair it without republishing it.

## Verification

- `shellcheck scripts/lib/resolve.sh scripts/lib/index-compose.sh tests/merge_memory.bats tests/push_behind_vs_diverged.bats tests/index_compose.bats`:
  clean.
- `scripts/run-bats.sh`, one file at a time, `GITLORE_GIT_RETRY_SCHEDULE=0`:

  | File | Passed | Failed |
  |---|---|---|
  | `tests/index_compose.bats` | 81 | 0 |
  | `tests/merge_memory.bats` | 35 | 0 |
  | `tests/push_behind_vs_diverged.bats` | 15 | 0 |
  | `tests/commit_memory.bats` | 35 | 0 |
  | `tests/push_memory.bats` | 12 | 0 |
  | `tests/tier_divergence.bats` | 19 | 0 |

- **Mutation runs**: each saved under `/tmp/claude-1000/probe.*`, then restored
  and checked with `cmp`.
  - HEAD's `resolve.sh`: the three new message assertions fail.
  - The bare `-f` weld guard: the containment test fails.
  - The live-ahead take with `|| :`: the resting-push test fails.

## Changed files

- `scripts/lib/resolve.sh`
- `scripts/lib/index-compose.sh`
- `tests/merge_memory.bats`
- `tests/push_behind_vs_diverged.bats`
- `tests/index_compose.bats`

## UNFIXABLE

None.

## REFACTOR-NEEDED

None new. `scripts/lib/index-compose.sh` is now 1075 lines; its split is already
deferred. `scripts/lib/resolve.sh` (~2170 lines) was far over the cap before
this job, and this phase's ~200 lines add to it. Record it beside the
index-compose split if it is not already tracked.

## For the prose phases (5-7)

Quote script output exactly as follows.

- **Repair success, by context**:
  - under `/gitlore:merge`:
    `gitlore: tier '<t>' — the repair is committed in its local 'live'; /gitlore:push publishes it.`
  - inside a push (`/gitlore:push` or the parent's `pre-push`):
    `… in its local 'live', and this push publishes it.`
  - `skills/merge/SKILL.md` Report (S5) relays the first form. A push skill or
    doc that relays take output must not turn the second into an errand.
- **Edit lines**: `gitlore: repaired <t>'s arrival: <report line>`. There is one
  per edit, printed once R is in `live`, including when the take then rests.
- **Unrepairable report**: the sentence, then the problem lines, indented as
  `gitlore:   live:MEMORY.md: line <n> …` (2.2's indentation fix), then the
  walk-back line ending
  `Once the index is fixed where it was published, run /gitlore:merge again.`
- **A push can itself write an unprompted repair commit** in a tier and publish
  it (D49 / D52). `skills/push/SKILL.md` has no S5 item; check that its Report
  wording does not claim a push only publishes what was already committed.
- **Wording carried over, not changed here**:
  - The resting walk-back still says "nothing was recorded … its local 'live'
    keeps what arrived" when `live` holds R. That reads true only as "memory
    recorded nothing" and "R contains the arrival".
  - `gitlore_adopt_advanced_live` prints "adopted them at <sha>" before the
    compose, including when the take then repairs or rests. This pre-dates the
    job.
  - D52's text should word the wedge risk to match.
- **K3 in D52**: the weld guard requires the second path to name an existing
  file inside the tier. A leading `/` or a `..` component never qualifies.
- **Phase 1 items still open** (from `phase-1-corrector.md`):
  `docs/references/commit-gate.md:54-57`, and the D50 argument paragraph.
