# Runbook: tier-arrival review minors

**Design:** `plans/tier-arrival-review-minors/outline.md`. **Recall:**
`plans/tier-arrival-review-minors/recall-artifact.md`. **Requirement IDs:**
M1–M21 are the item numbers in
`plans/tier-arrival-review-minors/classification.md`.

## Run constraints

- **Dispatch rules.** Every dispatch is bound by
  `plans/unadoptable-tier-arrival/dispatch-constraints.md`, with one exception:
  `.claude/handoff-task.md` and `.claude/handoff-todo.md` are folded into this
  job's commits.
- **Test runs.** Run bats files one at a time with `scripts/run-bats.sh <file>`.
  Run `just precommit` in the background at each phase boundary.
- **Fixtures.** Store fixtures come from `tests/helpers/tier-fixtures.bash` and
  the suite's own helpers.
- **`git` stubs.** Use a `git` stub only to inject errors. Follow
  `tests/merge_memory.bats:410-425`: a `$BATS_TEST_TMPDIR/fakebin/git` shell
  script that matches its arguments with `case " $* "` and `exec`s the real git
  otherwise. Put it on `PATH` only for the command under test.
- **Guard slices.** A slice marked **guard** already holds when it is written.
  The executor records it as a guard instead of forcing a red.

## Requirements mapping

| Requirement | Phase | Items | Notes |
|---|---|---|---|
| M1, M2, M3 repair and walk-back messages | 1 | 1.1 | |
| M7 scratch directory | 1 | 1.2 | |
| M5 mid-push repair race | 2 | 2.1 | Defect: the red is the reproduction |
| M4 tier push failure wording | 2 | 2.2 | |
| M6 terminator preservation, M8 comment verb | 3 | 3.1 | M8 rides the item that edits the same file |
| M15 pre-landing exit lines (harness) | 4 | 4.1 | |
| M9–M13 test specificity | 5 | 5.1–5.4 | mutant-proven |
| M14, M15 merger and resolve prose | 6 | 6.1, 6.2 | |
| M16–M21 docs, plus mechanism and quote sweep | 7 | 7.1–7.7 | |

## Phase 1: Repair and walk-back messages (type: tdd)

### Item 1.1: repair messages and walk-back

**Target:** `scripts/lib/resolve.sh`, specifically:
- `gitlore_adopt_tier_into_root` (the repair call);
- `gitlore_adopt_repair_arrival`;
- `gitlore_adopt_report_refusal_and_walk_back`;
- `gitlore_adopt_walk_back_tier`.

**What changes.** A repair that walks back reports every problem of the refusal
and a remedy that fits its arm. The walk-back names what `live` holds.

**Requirements:** M1, M2, M3.

**Changes:**
- **Full refusal passed through.** The call in `gitlore_adopt_tier_into_root`
  passes `$composed` as a new seventh argument.
- **Unrepairable arm.**
  - After its `live:MEMORY.md:` lines, it prints the refusal's other lines under
    `gitlore: the root index could not take tier '<t>''s lines:`, each prefixed
    `gitlore:   `. The other lines are those
    `gitlore_compose_problems_in "$tierpath/MEMORY.md"` does not select.
  - When other lines exist, the remedy is:
    `Fix the problems listed above in this repo; once the index is fixed where it was published, run /gitlore:merge again.`
  - Otherwise the remedy is unchanged.
- **Transient arms.** These are: arrival read, pin read, rewrite, commit build,
  `live` advance and checkout follow. Each keeps its own `could not …` line. It
  then prints the full refusal under the same header, and walks back with the
  remedy `Run /gitlore:merge again.`
- **Walk-back wording.**
  - `gitlore_adopt_walk_back_tier` gains a sixth argument naming what `live`
    holds, defaulting to `what arrived`. Its message reads
    `its local 'live' keeps <that>.`
  - `gitlore_adopt_report_refusal_and_walk_back` gains the same argument as its
    sixth and passes it through.
  - The retry-refusal call and the checkout-follow arm pass `the repair`.

**Slices:**
1. **Unrepairable arrival beside a root duplicate.** New test in
   `tests/merge_memory.bats` after the test at :744, built from that test's
   fixture plus a duplicate pointer in the dirty root `memory/MEMORY.md`. The
   test asserts:
   - stderr carries a `gitlore:   live:MEMORY.md:` line;
   - stderr carries the `could not take tier 'ddaanet''s lines:` header, and
     under it a line naming `memory/MEMORY.md`;
   - stderr ends with the two-fix remedy string above.

   The test at :744 is rewritten to assert its unchanged remedy.
2. **Commit build fails.** A new test uses the :558 duplicate-arrival fixture
   with a `git` stub that exits 1 on `commit-tree`. It asserts:
   - stderr contains `building the repair commit failed`;
   - stderr contains the refusal header, then the carrier's problem line;
   - stderr contains `Run /gitlore:merge again.`;
   - stderr does not contain `Fix the store`;
   - the tier `HEAD` is back on the pin.
3. **Retry refused on root.** The test at :703
   (`a repair beside a root problem lands in live and waits`) gains two
   assertions: stderr contains `its local 'live' keeps the repair.`, and does
   not contain `keeps what arrived`.
4. **Checkout follow fails.** A new test uses the :558 fixture with a `git` stub
   that exits 1 on `checkout -q --detach live` and forwards every other
   checkout. It asserts:
   - stderr contains `could not follow`;
   - stderr contains `keeps the repair.`;
   - stderr contains `Run /gitlore:merge again.`;
   - the tier's `live` equals the repair commit, whose parent is the arrival.

**Interfaces:**
- `gitlore_adopt_repair_arrival <mempath> <tier> <old_gitlink> <root_dirty_before> <label> <carrier_problems> <composed>`
  → 0 when adopted, 1 after emitting and walking back
- `gitlore_adopt_report_refusal_and_walk_back <mempath> <tier> <old_gitlink> <label> <composed> [<live_holds>]`
  → 1
- `gitlore_adopt_walk_back_tier <mempath> <tier> <old_gitlink> <label> [<remedy>] [<live_holds>]`
  → 1; `<live_holds>` defaults to `what arrived`

### Item 1.2: scratch directory under `$TMPDIR`

**Target:** `scripts/lib/resolve.sh`, in `gitlore_adopt_repair_arrival`.

**What changes.** The scratch directory is created with
`mktemp -d "${TMPDIR:-/tmp}/gitlore-repair.XXXXXX"`. The function comment's
clause "a scratch copy inside the tier's gitdir" becomes "a scratch copy outside
the repository". The `mktemp` arm prints
`gitlore: tier '<t>' — its arrival could not be repaired: no scratch directory could be made.`,
then the full refusal, then walks back with `Run /gitlore:merge again.`

**Requirements:** M7.

**Depends on:** Item 1.1 (the full-refusal argument and remedy).

**Slices:**
1. **Scratch directory location.** A new test uses the :558 fixture with a `git`
   stub. On `commit-tree`, the stub appends the output of
   `ls -d "<tier gitdir>"/gitlore-repair.* "$TMPDIR"/gitlore-repair.*` to
   `$BATS_TEST_TMPDIR/seen`, ignoring failures, before `exec`ing the real git.
   The test asserts:
   - `seen` has no line under the tier gitdir;
   - `seen` has exactly one line under `$TMPDIR`;
   - the repair is adopted.
2. **`mktemp` fails.** A new test uses the :558 fixture with `TMPDIR` set to a
   path that does not exist, for the command only. It asserts:
   - stderr contains `no scratch directory could be made`;
   - stderr contains the refusal header;
   - stderr contains `Run /gitlore:merge again.`;
   - the tier `HEAD` is back on the pin.

## Phase 2: Push publication (type: tdd)

### Item 2.1: the post-loop publication pass

**Target:** `scripts/lib/resolve.sh`, `gitlore_push_stores`.

**What changes.** A take that runs during the tier loop can repair a tier whose
own loop iteration already pushed. Every such repair is now published before
memory's push. The behind arm's retry push (the
`merge-base --is-ancestor live origin/live` block after
`GITLORE_TAKE_IN_PUSH=1 gitlore_merge_stores`) is removed. After the tier loop,
before the memory remote check, one pass over `gitlore_tier_paths`:
- skips a tier with no local `live`;
- pushes `live` to `origin` when `live` is not an ancestor of `origin/live`,
  including when `origin/live` is missing;
- on a failed push, reports and returns 1.

**Requirements:** M5.

**Slices:**
1. **Behind-arm race.** A new test in `tests/push_behind_vs_diverged.bats`,
   under the :320 section. Fixture:
   - two tiers, `aa` then `bb`, in `.gitmodules` order;
   - `aa` has a local fact ahead of its remote;
   - `aa`'s bare remote has a `post-receive` hook that, on its first run, moves
     `refs/heads/live` with `git update-ref` onto a commit whose `MEMORY.md`
     carries a duplicate pointer line;
   - `bb`'s remote is one commit ahead of `bb`.

   After `/gitlore:push`'s script runs, the test asserts:
   - the memory remote's recorded `aa` gitlink is a commit that
     `git -C <aa remote> cat-file -e <sha>^{commit}` finds.

   **Red:** the pre-job code leaves that commit missing from `aa`'s remote.
2. **Ahead-of-HEAD take race.** A variant of slice 1 where `bb`'s local `live`
   is ahead of its `HEAD` instead of its remote being ahead. It makes the same
   assertion. **Guard** if slice 1's green already covers it; the red is against
   the pre-job code.
3. **Existing cases still pass.** The tests at :338, :376 and :404 still pass,
   and :376 still publishes through the pass. **Guard**.

### Item 2.2: one reporter for a failed tier push

**Target:** `scripts/lib/resolve.sh`, a new helper beside `gitlore_push_stores`.
Callers:
- the pass from Item 2.1;
- the outer `*)` arm of the tier push `case`.

**What changes.** A failed tier push is worded by git's reason:
- an error containing `(fetch first)` or `(non-fast-forward)` gets the existing
  "was refused as a non-fast-forward, but its local 'live' already contains the
  remote's. The remote moved during the push, or the fetch before it failed."
  wording;
- anything else gets the existing "failed, and not because of divergence"
  wording.

Both go through `gitlore_say_for_agent_or_user` to stderr. The classified
`behind`, `diverged` and `*)` inner arms keep their own branches, and the inner
`*)` arm calls the helper.

**Requirements:** M4.

**Depends on:** Item 2.1.

**Slices:**
1. **Non-fast-forward refusal in the pass.** Uses slice 2.1/1's fixture plus a
   `git` stub that makes `aa`'s second `push -q origin live` print
   `! [rejected] live -> live (non-fast-forward)` to stderr and exit 1. The test
   asserts:
   - stderr contains `The remote moved during the push`;
   - stderr does not contain `not because of divergence`;
   - exit status 1.
2. **Policy refusal in the pass.** `aa`'s remote `pre-receive` hook accepts the
   first push and rejects the second. The test asserts that stderr contains
   `pushing tier 'aa' failed, and not because of divergence`, and that the
   status is 1. **Guard** on wording.

**Interfaces:**
- `gitlore_report_tier_push_failure <tier> <git_stderr>` → prints to stderr,
  returns 0

## Phase 3: Terminator preservation (type: tdd)

### Item 3.1: repair keeps line terminators

**Target:** `scripts/lib/index-compose.sh`, `gitlore_repair_index`.

**What changes.** The output ends unterminated only when its last element is the
input's last line, or that line's tail after a weld split, and the input was
unterminated. Every other element is written with a newline.

**Requirements:** M6, M8.

**Rider (M8):** the comment above `gitlore_compose_check_index` changes "a
defect no take can walk back from" to "a defect no take can adopt past".

**Slices:**
1. **Dropped duplicate at the end.** New test in the repair section of
   `tests/index_compose.bats`. Input: an unterminated index whose last line
   duplicates an earlier bullet, with an empty pin. The test asserts that the
   output bytes (`od -c` compared against a `printf`-built expected file) equal
   the input with that last line removed and the new last line ending in exactly
   one newline.
2. **Moved stray at the end.** Input: an unterminated index whose last line is
   the last bullet, with a non-bullet line between two bullets. The test asserts
   that the output bytes equal the stray moved after that bullet, the bullet
   ending in one newline, and the stray ending in one newline.
3. **Surviving last line.** An unterminated index whose last line survives a
   repair elsewhere stays unterminated, with byte equality. **Guard**, if an
   existing repair-section test already asserts it. In that case name the test
   instead of adding one.

## Phase 4: Continuation pre-landing exits (type: tdd)

### Item 4.1: not-committed lines

**Target:** `scripts/resolve.sh`:
- the merge message build and `commit` pair at :310-315;
- the comment at :105-109.

**What changes.**
- A failed build prints
  `gitlore: the merge message could not be built, so the merge was not committed; the merge stays prepared.`
  to stderr before removing the message file and exiting 1.
- A refused commit prints
  `gitlore: the merge commit was refused, so the merge was not committed; the merge stays prepared.`
  the same way.
- The comment at :105-109 adds: a failed staging command aborts under `errexit`
  with git's own text and no `gitlore:` line.

**Requirements:** M15.

**Slices:**
1. **Commit refused.** New test in `tests/resolve_compose.bats`. Fixture: a tier
   merge fixture as at :213 (a merged carrier that passes), with the tier
   store's `core.hooksPath` set to a directory whose `pre-commit` exits 1. The
   test asserts:
   - exit 1;
   - stderr contains the refused-commit line;
   - `MERGE_HEAD` still exists in the tier;
   - no `gitlore-merge-msg.*` file remains in `$TMPDIR`.
2. **Message build fails.** Same fixture, with a `git` stub that exits 1 on
   `log --format=%s` (the script runs under `pipefail`). The test asserts:
   - exit 1;
   - stderr contains the build line;
   - `MERGE_HEAD` still exists;
   - no message file remains.

## Phase 5: Test specificity (type: general)

Each item adds or tightens assertions only. For each named mutant, the executor
applies it to the production file, runs the file's tests and records the failing
test name, then reverts and confirms `git diff` shows no production change. The
report quotes each failure.

- **Item 5.1:** `tests/index_compose.bats`.
  - Remove `(K3)` from the :1143 header.
  - In the :1105 test, add a decoy line
    `memory/org/memory/MEMORY.md: duplicate pointer path x.md` to the input.
  - Assert that querying `memory/MEMORY.md` excludes the decoy.
  - *Mutant:* replace the `case` prefix match in `gitlore_compose_problems_in`
    with `grep -F -- "$file: "`.
  - **Requirements:** M9, M10.
  - **Model:** sonnet.
- **Item 5.2:** `tests/merge_memory.bats`, the :744 test as Item 1.1 leaves it.
  - Assert that no stderr line starts with `gitlore:   ` followed by the tier's
    worktree `MEMORY.md` path. *Mutant:* print `$line` unstripped.
  - Assert memory `HEAD` equals its pre-take value. *Mutant:* replace the arm's
    walk-back with a fall-through to `gitlore_adopt_stage_pair_and_commit`.
  - **Requirements:** M11.
  - **Depends on:** Item 1.1.
  - **Model:** sonnet.
- **Item 5.3:** `tests/git_hook_pre_commit.bats` and `tests/commit_memory.bats`.
  - **Root weld abort through the hook.** A new hook test, from the :391 fixture
    with root `memory/MEMORY.md` welded instead of the carrier. It asserts the
    abort line and the restamp exactly as :391 does. *Mutants:*
    - the `1)` arm of `gitlore_sync_memory_to_live` treats a dirty root index as
      advisory;
    - the arm skips the restamp.
  - **:391 test tightened.** It gains a tier `live` pin matching the fixture's
    other pinned-tier tests, and asserts the exact exit status instead of
    `-ne 0`. *Mutant:* the arm treats a dirty carrier as advisory.
  - **`commit_memory.bats`: rule 4 abort.** A test from the :140 fixture with an
    interleaved non-bullet line in place of the duplicate. It asserts the abort
    and the problem line. *Mutant:* `gitlore_compose_check_index` skips rule 4.
  - **`commit_memory.bats`: rule 2 advisory.** A test from the :236 fixture with
    a rule 2 problem. It asserts the commit lands and the problem line is
    reported. *Mutant:* the advisory arm prints only the lines
    `gitlore_compose_problems_in` selects for some index file.
  - **Requirements:** M12, M13.
  - **Model:** sonnet.
- **Item 5.4:** `tests/resolve_compose.bats`.
  - A test from the :415 fixture, with an interleaved non-bullet line in the
    merged root index. It asserts that the merge is unlanded and names the
    problem line.
  - *Mutant:* `gitlore_compose_check_index` skips rule 4.
  - **Requirements:** M13.
  - **Depends on:** Item 4.1.
  - **Model:** sonnet.

## Phase 6: Agent-facing prose (type: inline)

- **Item 6.1:** `agents/memory-merger.md`.
  - Step 6's index rules add "no two bullets naming the same path".
  - Turn 2's `approved` branch keys on any line containing
    `the merge was not committed`:
    - for the merged-index line, keep the current handling;
    - for the build or refused-commit line, quote it with git's reason printed
      above it, say the merge is unlanded, and stop without re-running the
      continuation.
  - "Otherwise" stays as the post-landing branch.
  - **Requirements:** M14, M15.
  - **Depends on:** Item 4.1.
- **Item 6.2:** `skills/resolve/SKILL.md`, Summarize section.
  - A merged-index refusal is re-synthesized, as now.
  - A build or refused-commit line is relayed with git's reason: the merge stays
    prepared, and the remedy is to fix that reason and run `/gitlore:resolve`
    again.
  - Every other `gitlore:` line stays post-landing.
  - **Requirements:** M15.
  - **Depends on:** Item 4.1.

## Phase 7: Docs (type: inline)

- **Item 7.1:** `docs/references/git-hooks.md:155-157`. Replace the clause with
  "A duplicate, interleaved or welded line in an index file with uncommitted
  changes — root's `MEMORY.md` or a tier carrier — aborts". **Requirements:**
  M16.
- **Item 7.2:** `docs/references/tier-arrival-repair.md`.
  - In the opening at :20-26, frame the wedge as the unrepaired case ("Left
    unrepaired, …").
  - At :34-35, the scratch copy lives outside the repository.
  - At :92-98, a take's repair is published by the push pass after the tier
    loop, which also covers a tier that a later iteration's take repaired.
  - A failed repair ends `Run /gitlore:merge again.`, except the unrepairable
    arm.
  - The walk-back names what `live` holds.
  - **Requirements:** M17.
  - **Depends on:** Items 1.1, 1.2, 2.1.
- **Item 7.3:** `docs/references/tier-stores.md`.
  - At :190-195, "The remedy is printed instead" becomes "It prints the remedy —
    …".
  - Grep for any claim about the scratch location, the behind arm's publication
    or the walk-back wording, and align it.
  - **Requirements:** M18.
  - **Depends on:** Items 1.1, 2.1.
- **Item 7.4:** `docs/references/index-authoring-sync.md:5` and
  `docs/references/tiered-memory.md:5`.
  - Count the sibling nodes listed at `tiered-memory.md:30-45`, and state that
    count in both files.
  - `rg -n 'four (sibling )?nodes' docs/` finds no other stale instance.
  - **Requirements:** M19.
- **Item 7.5:** `docs/references/commit-gate.md:57-61`. Replace the sentence
  with "A refusal that needs the agent to act lands only once it is done: an
  edit, for a problem in an index file the commit changes (D50, in
  [git-hooks.md](git-hooks.md)), or a checkout or take, for an off-pin tier."
  **Requirements:** M21.
- **Item 7.6:** the quote and mechanism sweep.
  - Run `rg -n` over `docs/` and `skills/` for each string Phases 1, 2 and 4
    changed or added: `keeps what arrived`, `Fix the store, then run`,
    `not because of divergence`, `the merge was not committed`, `gitdir` beside
    `repair`, and `both push arms`.
  - Align every hit with the shipped wording.
  - `docs/design.md` and `docs/decisions.md` get the D52 line's publication
    wording if they carry it.
  - **Requirements:** M1–M5, M7, M15.
  - **Depends on:** Items 7.1–7.5, 6.1, 6.2.
- **Item 7.7:** `docs/changelog.md` and `docs/changelog/`.
  - At :15-16 and in the matching line of the 2026-09-15 entry file, replace
    "refused for any other reason" with "refused for any reason but divergence".
  - Add a new 2026-09-15 entry file with its index line covering this job.
  - **Requirements:** M20.
  - **Depends on:** Item 7.6.
