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
  The orchestrator runs `just precommit` in the background at each phase
  boundary; executors never do.
- **Fixtures.** Store fixtures come from `tests/helpers/tier-fixtures.bash` and
  the suite's own helpers.
- **Stubs.** Use a stub only to inject errors. Follow
  `tests/merge_memory.bats:415-427`: a `$BATS_TEST_TMPDIR/fakebin/<tool>` shell
  script that matches its arguments with `case " $* "` and `exec`s the real tool
  otherwise. Put it on `PATH` only for the command under test. When only the Nth
  matching call must fail, the stub counts matches in a file under
  `$BATS_TEST_TMPDIR`.
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
| M14, M15 merger and resolve prose | 6 | 6.1 | |
| M16–M21 docs, plus mechanism and quote sweep | 7 | 7.1–7.5 | |

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
  `live` advance and checkout follow. Each keeps its own `could not …` line,
  then calls `gitlore_adopt_report_refusal_and_walk_back` with `$composed` and
  the remedy `Run /gitlore:merge again.`, which prints the full refusal under
  the same header and walks back.
- **Walk-back wording.** Each walk-back helper gains whichever of the optional
  arguments shown under **Interfaces** it lacks: `gitlore_adopt_walk_back_tier`
  gains `<live_holds>`, the report helper gains both and passes them through,
  and an empty remedy keeps the default. The message reads
  `its local 'live' keeps <live_holds>.` The retry-refusal call passes an empty
  remedy and `the repair`; the checkout-follow arm passes
  `Run /gitlore:merge again.` and `the repair`.

**Slices:**
1. **Unrepairable arrival beside a root duplicate.** New test in
   `tests/merge_memory.bats` after the test at :744, built from that test's
   fixture plus a duplicate pointer in the dirty root `memory/MEMORY.md`. The
   test asserts:
   - stderr carries a `gitlore:   live:MEMORY.md:` line;
   - stderr carries the `could not take tier 'ddaanet''s lines:` header, and
     under it a line naming `memory/MEMORY.md`;
   - stderr ends with the two-fix remedy string above.

   The test at :744 carries no other problem, so its assertion at :771 holds
   unchanged; it is not edited.
2. **Commit build fails.** A new test uses the :558 duplicate-arrival fixture
   with a `git` stub that exits 1 on `commit-tree`. It asserts:
   - stderr contains `building the repair commit failed`;
   - stderr contains the refusal header, then a `gitlore:   ` line containing
     `ddaanet/MEMORY.md: duplicate pointer path a.md`;
   - stderr contains `Run /gitlore:merge again.`;
   - stderr does not contain `Fix the store`;
   - the tier `HEAD` is back on the pin.
3. **Retry refused on root.** The test at :703
   (`a repair beside a root problem lands in live and waits`) gains two
   assertions: stderr contains `its local 'live' keeps the repair.`, and does
   not contain `keeps what arrived`.
4. **Checkout follow fails.** A new test uses the :558 fixture with a `git` stub
   that exits 1 on the *second* `checkout -q --detach live` (the first is the
   take's own fast-forward at `gitlore_merge_one_store`) and forwards every
   other call. It asserts:
   - stderr contains `could not follow`;
   - stderr contains `keeps the repair.`;
   - stderr contains `Run /gitlore:merge again.`;
   - the tier's `live` equals the repair commit, whose parent is the arrival;
   - the tier `HEAD` is back on the pin.
5. **`live` advance fails.** **Guard** (slice 2's GREEN rewired this arm). A new
   test uses the :558 fixture with `GITLORE_GIT_RETRY_SCHEDULE=0` and a `git`
   stub that exits 1 on the `push -q . <sha>:refs/heads/live` advance. It
   asserts:
   - stderr contains the arm's own failure line;
   - stderr contains the refusal header, then the carrier's duplicate line;
   - stderr contains `Run /gitlore:merge again.` and not `Fix the store`;
   - the tier `HEAD` is back on the pin.

   The test review proves it with the mutant "the arm calls
   `gitlore_adopt_walk_back_tier` directly".

**Interfaces:**
- `gitlore_adopt_repair_arrival <mempath> <tier> <old_gitlink> <root_dirty_before> <label> <carrier_problems> <composed>`
  → 0 when adopted, 1 after emitting and walking back
- `gitlore_adopt_report_refusal_and_walk_back <mempath> <tier> <old_gitlink> <label> <composed> [<remedy>] [<live_holds>]`
  → 1
- `gitlore_adopt_walk_back_tier <mempath> <tier> <old_gitlink> <label> [<remedy>] [<live_holds>]`
  → 1; `<live_holds>` defaults to `what arrived`

### Item 1.2: scratch directory under `$TMPDIR`

**Target:** `scripts/lib/resolve.sh`, in `gitlore_adopt_repair_arrival`.

**What changes.** The scratch directory is created with
`mktemp -d "${TMPDIR:-/tmp}/gitlore-repair.XXXXXX"`, and the
`rev-parse --absolute-git-dir` lookup it no longer needs is dropped. The
function comment's clause "a scratch copy inside the tier's gitdir" becomes "a
scratch copy outside the repository". The `mktemp` arm prints
`gitlore: tier '<t>' — its arrival could not be repaired: no scratch directory could be made.`,
then calls `gitlore_adopt_report_refusal_and_walk_back` with
`Run /gitlore:merge again.`

**Requirements:** M7.

**Depends on:** Item 1.1 (the full-refusal argument and remedy).

**Slices:**
1. **Scratch directory location.** A new test uses the :558 fixture with a `git`
   stub, and `TMPDIR` set for the command to a fresh `$BATS_TEST_TMPDIR/tmp`. On
   `commit-tree`, the stub appends the output of
   `ls -d "<tier gitdir>"/gitlore-repair.* "$TMPDIR"/gitlore-repair.*` to
   `$BATS_TEST_TMPDIR/seen`, ignoring failures, before `exec`ing the real git.
   The test asserts:
   - `seen` has no line under the tier gitdir;
   - `seen` has exactly one line under `$TMPDIR`;
   - the repair is adopted.
2. **`mktemp` fails.** A new test uses the :558 fixture with a `mktemp` stub
   that exits 1 when an argument contains `gitlore-repair.`. A nonexistent
   `TMPDIR` cannot stand in: `gitlore_git`'s own `mktemp` fails first, at the
   take's fast-forward. It asserts:
   - stderr contains `no scratch directory could be made`;
   - stderr contains the refusal header;
   - stderr contains `Run /gitlore:merge again.`;
   - the tier `HEAD` is back on the pin.

## Phase 2: Push publication (type: tdd)

### Item 2.1: the post-loop publication pass

**Target:** `scripts/lib/resolve.sh`, `gitlore_push_stores`.

**What changes.** A take that runs during the tier loop can repair a tier whose
own loop iteration already pushed. Every such repair is now published before
memory's push. The behind arm keeps its retry push (the
`merge-base --is-ancestor live origin/live` block after
`GITLORE_TAKE_IN_PUSH=1 gitlore_merge_stores`), so its own tier's repair is out
before a later tier's failure returns 1 from the loop. After the tier loop,
before the memory remote check (so a memory with no remote still publishes every
tier), one pass over `gitlore_tier_paths`:
- skips a tier with no checkout or no local `live`, as the loop does;
- pushes `live` to `origin` when `live` is not an ancestor of `origin/live`,
  including when `origin/live` is missing;
- on a failed push, prints the removed retry's "failed, and not because of
  divergence" message and returns 1 (Item 2.2 classifies it).

The pass's comment names what it publishes: a repair to a tier whose iteration
already finished. It notes that the loop's pushes move `origin/live`, so a tier
already out is not pushed again.

**Requirements:** M5.

**Slices:**
1. **Mid-loop repairs are published (the reproduction).** Two new tests in
   `tests/push_behind_vs_diverged.bats`, under the :320 section. Shared fixture,
   built as :338 builds its one tier:
   - tiers `aa` then `bb`, mounted with `mount_tier_at_live` in that order and
     both in the manifest; memory composed, committed and published;
   - `aa` holds a tier commit P ahead of its remote, adding a file and no index
     line, with `live` at P and P recorded as memory's pin before publishing;
   - a child of P, D, appending one bullet line twice to `MEMORY.md` (the
     arrival shape of :376), is pre-pushed to a side ref of `aa`'s bare remote;
   - that remote has a one-shot `post-receive` hook (it removes itself, as
     `half_landed_tier_fixture` does) running
     `git update-ref refs/heads/live D`.

   Variant **behind**: `bb`'s remote is one commit ahead (`push_tier_fact bb`).
   Variant **ahead-of-HEAD**: `strand_live_ahead_of_pin bb`. After
   `scripts/push-memory.sh` runs, each test asserts exit 0 and that the memory
   remote's recorded `aa` gitlink is a commit
   `git --git-dir=<aa remote> cat-file -e <sha>^{commit}` finds.

   **Red:** each variant fails on its own against the current code. If neither
   does, stop and report; nothing is fixed on reasoning alone. A variant that
   does not reproduce is kept as a guard and reported as such.

2. **A behind arm's repair survives a later tier's failure.** A new test in the
   same section. Tiers `aa` then `bb`, mounted and published as in slice 1.
   `aa`'s remote receives a duplicate-bullet fact (`push_tier_fact`), so `aa` is
   behind and its own take repairs it. `bb` is ahead of its remote, whose
   `pre-receive` hook rejects every push. After `scripts/push-memory.sh` runs,
   the test asserts:
   - exit status 1, and stderr names `bb`'s failed push;
   - `aa`'s remote `live` equals `aa`'s local `live`, the repair commit.

   **Red** against the slice 1 commit, which removed the retry; the pre-change
   code published it.

After green, the tests at :338, :376 and :404 pass unchanged.

### Item 2.2: one reporter for a failed tier push

**Target:** `scripts/lib/resolve.sh`, a new helper beside `gitlore_push_stores`.
Callers:
- the pass from Item 2.1;
- the outer `*)` arm of the tier push `case`;
- the inner `*)` arm under `gitlore_classify_refusal`, whose message the
  helper's divergence wording reproduces.

**What changes.** A failed tier push is worded by git's reason:
- an error containing `(fetch first)` or `(non-fast-forward)` gets the existing
  "was refused as a non-fast-forward, but its local 'live' already contains the
  remote's. The remote moved during the push, or the fetch before it failed."
  wording;
- anything else gets the existing "failed, and not because of divergence"
  wording.

Both go through `gitlore_say_for_agent_or_user` to stderr. The `behind` and
`diverged` arms keep their own branches.

**Requirements:** M4.

**Depends on:** Item 2.1.

**Slices:**
1. **Non-fast-forward refusal in the pass.** Uses slice 2.1/1's behind-variant
   fixture plus a `git` stub that makes the second call ending
   `aa push -q origin live` print `! [rejected] live -> live (non-fast-forward)`
   to stderr and exit 1. The test asserts:
   - stderr contains `The remote moved during the push`;
   - stderr does not contain `not because of divergence`;
   - exit status 1.
2. **Policy refusal in the pass.** The same fixture, with no stub; `aa`'s remote
   `pre-receive` hook accepts the first push and rejects the second. The test
   asserts that stderr contains
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
   duplicates an earlier bullet, with an empty pin. The test asserts, with
   `cmp -s` against a `printf`-built expected file as :1334 does, that the
   output equals the input with that last line removed and the new last line
   ending in exactly one newline.
2. **Moved stray at the end.** **Guard** (slice 1's GREEN implemented the whole
   rule). Input: an unterminated index whose last line is the last bullet, with
   a non-bullet line between two bullets. The test asserts that the output bytes
   equal the stray moved after that bullet, the bullet ending in one newline,
   and the stray ending in one newline.

An unterminated index whose last line survives a repair elsewhere is already
covered with byte equality by :1334
(`welds are split before duplicates are resolved`), which passes unchanged after
green; no test is added for it.

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
1. **Commit refused.** The existing test at :394
   (`a refused merge commit leaves no message file behind …`) already refuses
   the commit with a `commit-msg` hook and asserts the kept `MERGE_HEAD` and the
   absent message file. It is tightened: `-ne 0` becomes `-eq 1`, and stderr
   contains `commit refused by hook` followed later by the refused-commit line.
2. **Message build fails.** New test in `tests/resolve_compose.bats`:
   `prepare_tier_merge_with_new_lines`, `TMPDIR` set as :394 sets it, and a
   `git` stub that exits 1 on `log --format=%s HEAD..` (the only such call
   before the commit; the script runs under `pipefail`). The test asserts:
   - exit 1;
   - stderr contains the build line;
   - `MERGE_HEAD` still exists;
   - no message file remains.

## Phase 5: Test specificity (type: general)

Each item adds or tightens assertions only. For each named mutant, the executor
applies it to the production file, runs the file's tests and records the failing
test name and the assertion line bats reports, then reverts and confirms
`git diff` shows no production change. The report quotes each failure. A new
assertion in an existing test goes ahead of any existing assertion its mutant
would also trip, so the reported line is the new one.

- **Item 5.1:** `tests/index_compose.bats`.
  - Remove `(K3)` from the :1143 header.
  - In the :1105 test, add a suffix decoy in the fixture's own spelling,
    `nested/my mem.d/MEMORY.md: duplicate pointer path suffix.md`, to the input.
    The existing exact-output assertion on the `my mem.d/MEMORY.md` query then
    excludes it.
  - *Mutant:* replace the `case` prefix match in `gitlore_compose_problems_in`
    with `grep -F -- "$file: "`.
  - **Requirements:** M9, M10.
  - **Model:** sonnet.
- **Item 5.2:** `tests/merge_memory.bats`, the :744 test as Item 1.1 leaves it.
  - Assert that no stderr line starts with `gitlore:   ` and contains
    `ddaanet/MEMORY.md: `. *Mutant:* the unrepairable arm prints every refusal
    line under the root-index header, the carrier's included. (An unstripped
    `live:` line already fails :768.)
  - Assert memory `HEAD` equals its pre-take value. *Mutant:* replace the arm's
    walk-back with a fall-through to `gitlore_adopt_stage_pair_and_commit`.
  - **Requirements:** M11.
  - **Depends on:** Item 1.1.
  - **Model:** sonnet.
- **Item 5.3:** `tests/git_hook_pre_commit.bats` and `tests/commit_memory.bats`.
  - **Root weld abort through the hook.** A new hook test: no tier; the welded
    root line appended as `commit_memory.bats:191` does; the summary written and
    everything backdated as :401-412 does. It asserts status 1, the
    `memory/MEMORY.md: line <n> welds two pointer bullets` line, `aborted`, no
    `the commit went ahead`, memory `HEAD` unchanged and the restamp as :425.
    *Mutants:*
    - the `1)` arm of `gitlore_sync_memory_to_live` treats a dirty root index as
      advisory;
    - the abort arm skips `touch "$msgfile"`.
  - **:391 test tightened.** It gains `git -C memory/ddaanet branch -f live` as
    `commit_memory.bats:148` does, asserts the tier `live` unmoved, and asserts
    `-eq 1` instead of `-ne 0`. The advisory-carrier mutant is already killed by
    :421, so it proves neither. *Mutants:*
    - the abort arm returns 2 instead of 1 (exact status); before tightening,
      confirm this mutant passes the test as it stands;
    - the abort arm calls `gitlore_sync_tiers_to_live "$mempath" "$msgfile"`
      before returning (tier `live` unmoved, placed ahead of :422-423, which the
      same mutant trips).
  - **`commit_memory.bats`: rule 4 abort.** A test from the :140 fixture with a
    non-bullet line (`printf 'Stray line\n'`) appended between two different
    seeded carrier bullets in place of the duplicate. It asserts status 1, a
    `memory/ddaanet/MEMORY.md: interleaved non-bullet line` line and `aborted`.
    *Mutant:* `gitlore_compose_check_index` skips rule 4.
  - **`commit_memory.bats`: rule 2 advisory.** Already covered: :717
    (`a manifest refusal is reported and does not abort the commit`) runs rule 2
    through the advisory arm with root and carrier dirty, and asserts the commit
    lands and the `phantom` line. No test is added. The executor proves it with
    the mutant "the advisory arm prints only the lines
    `gitlore_compose_problems_in` selects for some index file" and reports the
    failure.
  - **Requirements:** M12, M13.
  - **Model:** sonnet.
- **Item 5.4:** `tests/resolve_compose.bats`.
  - A test from the :415 fixture, with the pending index `- [P](p.md) — one`,
    `Stray line`, `- [Q](q.md) — two`. It asserts status 1, `was not committed`,
    a `memory/MEMORY.md: interleaved non-bullet line` line, `MERGE_HEAD` kept
    and memory `HEAD` unchanged.
  - *Mutant:* `gitlore_compose_check_index` skips rule 4.
  - **Requirements:** M13.
  - **Depends on:** Item 4.1.
  - **Model:** sonnet.

## Phase 6: Agent-facing prose (type: inline)

- **Item 6.1:** `agents/memory-merger.md` and `skills/resolve/SKILL.md`, the two
  readers of Item 4.1's lines, edited together so they split them the same way.
  - `agents/memory-merger.md`:
    - Step 6's index rules add "no two bullets naming the same path".
    - Turn 2's `approved` branch keys on any line containing
      `the merge was not committed`:
      - for the merged-index line, keep the current handling;
      - for the build or refused-commit line, quote it with git's reason printed
        above it, say the merge is unlanded, and stop without re-running the
        continuation.
    - "Otherwise" stays as the post-landing branch.
  - `skills/resolve/SKILL.md`:
    - At :68, beside the merged-index arm: a sub-agent report of the build or
      refused-commit line gets no `rejected:` and no **Loop** (a rerun re-emits
      the same directive and meets the same refusal); go to **Summarize**.
    - Summarize section (:82-87): a merged-index refusal is re-synthesized, as
      now. A build or refused-commit line is relayed with git's reason: the
      merge stays prepared, and the remedy is to fix that reason and run
      `/gitlore:resolve` again. Every other `gitlore:` line stays post-landing.
  - **Requirements:** M14, M15.
  - **Depends on:** Item 4.1.

## Phase 7: Docs (type: inline)

- **Item 7.1:** single-clause fixes in three nodes, none depending on another
  item.
  - `docs/references/git-hooks.md:155-157` (M16): replace the clause with "A
    duplicate, interleaved or welded line in an index file with uncommitted
    changes — root's `MEMORY.md` or a tier carrier — aborts".
  - `docs/references/index-authoring-sync.md:5` (M19):
    - The subsystem has five nodes: `tiered-memory.md` and the four siblings it
      lists at :30-45. "One of the four nodes" becomes "One of the five nodes",
      as `index-composition.md:4-5` says.
    - `tiered-memory.md:5` ("four sibling nodes") and :23 ("four siblings") are
      already correct and stay.
    - `rg -n 'of the (four|five) nodes|four sibling' docs/references/` finds no
      other stale instance.
  - `docs/references/commit-gate.md:57-60` (M21): replace the sentence with "A
    refusal that needs the agent to act is retried the same way but lands only
    once it is done: an edit, for a problem in an index file the commit changes
    (D50, in [git-hooks.md](git-hooks.md)), or a checkout or take, for an
    off-pin tier."
  - **Requirements:** M16, M19, M21.
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
- **Item 7.4:** the quote and mechanism sweep.
  - Run `rg -n` over `docs/` and `skills/` for each string Phases 1, 2 and 4
    changed or added: `keeps what arrived`, `Fix the store, then run`,
    `not because of divergence`, `the merge was not committed`, `gitdir` beside
    `repair`, and `both push arms`.
  - Align every hit with the shipped wording.
  - `docs/design.md` and `docs/decisions.md` get the D52 line's publication
    wording if they carry it.
  - **Requirements:** M1–M5, M7, M15.
  - **Depends on:** Items 7.1–7.3, 6.1.
- **Item 7.5:** `docs/changelog.md` and `docs/changelog/`.
  - At :15-16, replace "refused for any other reason" with "refused for any
    reason but divergence". The 2026-09-15 entry file already reads "any reason
    but divergence" (:55) and is not edited.
  - Add a new entry file, dated the day it is written, with its index line
    covering this job.
  - **Requirements:** M20.
  - **Depends on:** Item 7.4.
