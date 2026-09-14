# Runbook Review: unadoptable-tier-arrival

**Artifact**: plans/unadoptable-tier-arrival/runbook.md **Design**:
plans/unadoptable-tier-arrival/outline.md **Date**: 2026-09-14 **Mode**:
review + fix-all

**Unfixed Critical issues: none.** No finding is marked UNFIXABLE. Two are fixes
my human partner should confirm at `/proof`, because the review chose something
the outline leaves open: Major 6 and Minor 5.

## Summary

The runbook traces every key decision and follows the outline's structure. Its
file, function and line citations are accurate. But several slices could not be
written, or could not go red, as specified. Slice 1.1/1 asserted a restamp that
`commit-memory.sh` makes impossible to observe. Slice 1.1/2 drove a parent
`git commit` that the suite never uses. The weld slices would break once the
tier-file guard landed. One take assertion had no specified producer. Several
comments and docs that the change makes false had no item. All of these are
fixed in place.

**Overall Assessment**: Ready

## Requirements Coverage

| Requirement | Phase | Items | Coverage | Notes |
|---|---|---|---|---|
| K1 repair commit inside the take | 2, 6 | 2.2, 6.5, 6.7 | Complete | R built with `commit-tree`, advanced by `push .`, checked out at `live`; FR11/D49 exemption records added |
| K2 attribution and resting | 2, 5 | 2.2, 5.3 | Complete | carrier-matched repair, resting with R, unrepairable report; the no-carrier arm stays covered by `tests/merge_memory.bats:356` |
| K3 restructuring rules | 2, 7 | 2.1, 7.1 | Complete | welds, then interleaved lines, then duplicates; the tier-file guard; byte preservation; a write failure |
| K4 continuation gate | 3, 5, 6 | 3.1, 5.1, 5.2, 6.3 | Complete | tier merges and memory-root merges; line 241 inverts; line 137 stays green |
| K5 prevention | 1, 6 | 1.1, 6.2 | Complete | dirty carrier, dirty root under rules 1/4/6, and the advisory cases |
| K6 publication | 2, 5 | 2.2, 2.3, 5.3 | Complete | `/gitlore:push` line, fetch-first, retry in the `behind` arm, both push arms |
| K7 decision records | 6 | 6.1–6.7 | Complete | D52, D50 amended, rejected alternatives, D44/D49/FR11 propagation |
| m4 per-arm exits and rest guard | 4, 6 | 4.1, 6.1 | Complete | statuses 0/1/2, rest guard, runnable remedy, default-mode gates |

## Review Findings

### Critical Issues

None.

### Major Issues

1. **Slice 1.1/1 asserted a restamp nobody can observe**
   - Location: Item 1.1, slice 1.
   - Problem: `commit-memory.sh -m` writes the summary just before
     `gitlore_sync_memory_to_live` runs. Backdating the summary alone makes
     `gitlore_commit_msg_freshness` read `no`, so the run refuses with "no
     approved commit summary" before it composes. The slice would stay red even
     after a correct implementation.
   - Fix: slice 1 now asserts the exit status, the message, and that HEAD and
     `live` did not move. The restamp moved to slice 2 (`pre-commit`, where the
     summary is written ahead of the run). There, the summary and every file
     that freshness's own `find` lists are backdated to one `touch -t` stamp,
     and the test asserts that `_gitlore_mtime` of the summary is newer. The
     slice-1 fixture is spelled out with the existing helpers.
   - **Status**: FIXED

2. **Slice 1.1/2 drove a parent `git commit`**
   - Location: Item 1.1, slice 2.
   - Problem: `tests/git_hook_pre_commit.bats` runs `bash "$HOOK"` directly, so
     "the parent HEAD is unchanged" has nothing to measure.
   - Fix: the slice now runs `bash "$HOOK"` and asserts memory HEAD instead.
   - **Status**: FIXED

3. **The weld unit slice would break when the guard landed**
   - Location: Item 2.1, slices 3 and 4.
   - Problem: slice 3's fixture did not create the file the welded path names.
     Slice 4's guard (split only when that file exists in the tier) would then
     turn slice 3 red. Slice 4's bare-link test is already green once slice 3
     uses `gitlore_welded_path`.
   - Fix: slice 3 creates `welded_b.md` and `welded_c.md`. In slice 4, the
     missing-file weld carries the red and the bare-link test is marked guard.
   - **Status**: FIXED

4. **The take's weld arrival could not be built with the existing helpers**
   - Location: Item 2.2, fixture.
   - Problem: `push_tier_fact` only appends to `MEMORY.md`. A weld arrival also
     needs the file its second path names, and the take passes the worktree at
     the arrival as `<tier-dir>`.
   - Fix: a suite-local `push_tier_files` helper, shaped like `push_tier_fact`.
     The runbook now names each fixture's source: `:331` and `:518` in
     `tests/merge_memory.bats`, and the double `seed_tier_bullet` before
     `strand_live_ahead_of_pin` for the stranded duplicate.
   - **Status**: FIXED

5. **Printing the first refusal would break slice 2.2/3**
   - Location: Item 2.2, flow.
   - Problem: today's arm prints the refusal before walking back. If the repair
     flow still printed the first refusal, `duplicate pointer path` would appear
     in the output that slice 3 says must not contain it. The runbook's prose
     also disagreed with its own `Interfaces:` block about when the repair lines
     print. And a retry that returns rc 2 had no arm.
   - Fix: the first refusal's problem list is not printed when the repair runs.
     Repair lines print once R is in `live`, whether the tier is then adopted or
     resting. A retry rc 1 or 2 prints under today's refusal header and walks
     back. A repair returning 1 walks back. The function's header comment gains
     the repair arm.
   - **Status**: FIXED

6. **No producer for "output names `/gitlore:push`"** *(confirm at /proof)*
   - Location: slice 2.2/1.
   - Problem: `merge-memory.sh` mentions `/gitlore:push` only when the store is
     dirty, and no item said what prints this line.
   - Fix: when a repair is adopted, the take prints
     `gitlore: tier '<tier>' — the repair is committed in its local 'live'; /gitlore:push publishes it.`
     The line is also true inside a push, which publishes R immediately
     afterwards. It is added to Item 2.2's flow and its `Interfaces:` block, and
     K6 is added to 2.2's requirements. Before this fix, two executors would
     have emitted two different lines.
   - **Status**: FIXED

7. **Fetch-first did not say what happens on the early returns**
   - Location: Item 2.3.
   - Problem: moving the fetch ahead of `gitlore_adopt_advanced_live` also moves
     the remote-URL checks ahead of it. Today, a tier with no remote, a
     placeholder URL, or a remote without `live` still adopts its local `live`
     before failing. Only the failed-fetch arm said adoption still runs.
   - Fix: every return before the ancestry test runs the local adoption first.
     `head` is read after the adoption. A missing ref also runs the adoption.
     The comment above the call is rewritten. A refused retry in the `behind`
     arm prints the outer `*)` message and returns 1.
   - **Status**: FIXED

8. **Tests that hold a lock would sit through ten seconds of retries**
   - Location: slices 2.2/6 and 4.1/2.
   - Problem: a probe shows that a held `live.lock` makes `push .` print
     `cannot lock ref … live.lock … File exists`. `gitlore_git_is_lock_error`
     matches that text, so the default schedule retries for about ten seconds.
   - Fix: the run constraints and slice 4.1/2 require
     `GITLORE_GIT_RETRY_SCHEDULE=0`, following `tests/resolve_compose.bats:221`.
   - **Status**: FIXED

9. **Slice 4.1/3 ran the remedy in the wrong order**
   - Location: Item 4.1, slice 3.
   - Problem: the slice committed the root fix before running the printed
     commands. `commit_memory_state` runs `add -A`, which would stage the tier's
     gitlink at the merge commit before the remedy's `checkout --detach <pin>`.
     That order does not follow the remedy.
   - Fix: run the printed commands first, then delete the root line with `sed`
     (as `tests/resolve_compose.bats:168` does), then run `merge-memory.sh`. The
     remedy's print format is now specified: each command on its own line after
     `gitlore:   `, so the test can extract it. The guard's position in
     `rest_unadopted_tier` is named.
   - **Status**: FIXED

10. **Slice 4.1/4 passed under the wrong implementation**
    - Location: Item 4.1, slice 4.
    - Problem: `push_or_report` prints "not because of divergence" itself. A
      caller left as `if ! push_or_report` would still exit 1 through the `*)`
      arm, where `gitlore_classify_refusal` returns `ahead`.
    - Fix: the slice adds a negative assertion on
      `refused as a non-fast-forward` and spells out the fixture for memory's
      bare remote.
    - **Status**: FIXED

11. **Comments and docs the change makes false had no item** (semantic
    propagation)
    - Location: Items 3.1, 4.1, 6.1, 6.2, 6.5, and a new 6.7.
    - Problem: `rg` finds claims that stop being true:
      - the "A refusal never blocks the merge" comment at
        `scripts/resolve.sh:85-90`;
      - `push_or_report` "EXITS 1" and `rest_unadopted_tier` "Exit status stays
        the caller's";
      - `git-hooks.md:15-16` and `:55`, "rc 1 reports and continues";
      - D44 in `tier-stores.md`, "no duplicate-pointer residue arises on any
        path and no dedup pass is needed";
      - FR11 at `design.md:51` and D49 at `merge-and-resolve.md:306`, which list
        merge and bookkeeping commits as the only exemptions, while R is a third
        unprompted commit (K1).
    - Fix: each is added to its item. The new Item 6.7 covers the D49 node, and
      Item 6.5 gains the FR11 line.
    - **Status**: FIXED

### Minor Issues

1. **Several slices cannot go red after the slice before them**
   - Location: 1.1/5, 2.1/4 (bare link), 2.2/2, 2.2/5, 2.3/1, 3.1/2, 3.1/3,
     3.1/5.
   - Problem: each one is red against the pre-job code but already green once
     the previous slice passes. An executor would either fake a red or stall.
   - Fix: a **guard** convention in the run constraints, and each slice marked,
     stating what it is red against where that is narrower.
   - **Status**: FIXED

2. **Slice 2.2/4 repeated an existing test**
   - Location: old slice 2.2/4, "no carrier problem walks back".
   - Problem: `tests/merge_memory.bats:356` already has this fixture and these
     assertions, including `live` on the arrival.
   - Fix: the slice is removed, the remaining slices are renumbered, and a
     post-state note names the existing test as the guard for that K2 arm. The
     local-live reach slice now reuses the stranded-duplicate fixture.
   - **Status**: FIXED

3. **The helper test could not fail a regex implementation**
   - Location: slice 1.1/6.
   - Problem: a space is not a regex metacharacter, and the prefix pair `a`/`ab`
     cannot collide once `/MEMORY.md: ` is included. A `grep "^$file: "`
     implementation would pass.
   - Fix: `$mempath` becomes `my mem.d`, with a decoy line for `my memXd`.
   - **Status**: FIXED

4. **Gaps in the unit slices for `gitlore_repair_index`**
   - Location: Item 2.1.
   - Problem: nothing tested an unterminated last line, which the file header
     requires every read to keep. Nothing tested the "known to both" duplicate
     row that K3 names ("lacks none"). Nothing tested the interface's return 1.
   - Fix: an unterminated clean index is added to slice 1 and an unterminated
     last line to slice 7. The row is added to slice 6. A new slice 8 covers a
     directory that cannot be written, skipped under root. The rename happens
     only when there is an edit.
   - **Status**: FIXED

5. **Line numbers in the unrepairable report** *(confirm at /proof)*
   - Location: Item 2.2, the unrepairable report.
   - Problem: the recheck runs on the repaired scratch copy. Its lines had a
     scratch path prefix, which was never specified. They now print as
     `live:MEMORY.md: …`, but a `line <n>` refers to the repaired copy whenever
     an earlier rule split, moved or dropped a line above it. The outline says
     "the remaining problems", so the runbook keeps the recheck's lines rather
     than the arrival's own problem list, whose line numbers would be exact.
   - Fix: the prefix is replaced by `live:MEMORY.md: `. The numbering is left
     for my human partner to decide.
   - **Status**: FIXED (prefix); the choice of numbering is flagged, not changed

6. **Citation and dependency fixes**
   - Location: Items 4.1, 5.3, 6.1, 6.5, 6.6.
   - Problem and fix:
     - the D50 sentence in `design.md` runs over lines 230-232, not just 232;
     - Item 6.1 now declares that it depends on 2.2, 2.3 and 3.1, since it
       describes them;
     - Item 6.6 now depends on 6.2 as well;
     - Item 4.1 now depends on 3.1, per its own post-state;
     - Item 5.3 gains K2 (it relays what a resting repair waits on);
     - the changelog file name carries the landing date instead of a fixed
       2026-09-14.
   - **Status**: FIXED

7. **Target files are already past the cap** (growth projection)
   - Location: Phases 1–4.
   - Problem: current sizes are `scripts/lib/index-compose.sh` 880 lines,
     `scripts/lib/resolve.sh` 1952 and `scripts/resolve.sh` 445. The job
     projects roughly +100, +100 and +40. All three were over 400 lines before
     this job, so no split point can be placed before a phase that crosses the
     cap, and splitting the files is outside the outline's scope.
   - Fix: none in the runbook.
   - **Status**: UNFIXABLE: the overage predates the job, and splitting is out
     of scope

## Fixes Applied

- Run constraints: the lock-retry export and the **guard** convention.
- Mapping table: rows for K2, K6 and K7 updated. Item 6.7 added.
- Item 1.1:
  - which tiers are read, and the text on both message arms;
  - slices 1–3 rewritten with concrete fixtures and message paths (`memory/…`,
    the spelling `gitlore_memory_path` returns);
  - the restamp moved to slice 2 and asserted through mtimes;
  - slice 4's fixture records the pin;
  - slice 6's decoy added.
- Item 2.1: read guard, rename only on an edit, tier files for the weld
  fixtures, guard marks, the "known to both" row, unterminated lines, slice 8.
- Item 2.2:
  - the argument to `<tier-dir>`, the first refusal left unprinted, when the
    repair lines print;
  - the `/gitlore:push` line, the retry's rc 2 arm and the repair's rc 1 arm;
  - the `live:MEMORY.md:` prefix and the header-comment update;
  - fixture sources and `push_tier_files`;
  - the old slice 4 removed in favour of `:356`, and slices renumbered.
- Item 2.3:
  - adoption on every early return, and the ancestry reads;
  - the rewritten comment and the retry's refusal arm;
  - fixture sources, and a `pre-receive` hook that unsets git's quarantine
    variables before reading the tier remote.
- Item 3.1:
  - the `:85-90` comment rewrite and the exact duplicate-line assertion;
  - the head-vs-live fixture source (`tests/tier_divergence.bats:143`);
  - the memory-root fixture (`diverge_memory_with_index`, `run_stub_synth`);
  - guard marks.
- Item 4.1: the guard's position and `live` read, the remedy's line format,
  header comments, slice-1 hook placement, the slice-2 retry export and `abs`
  spelling, slice-3 order, the slice-4 negative assertion and fixture.
- Items 5.3 and 6.1–6.7: propagation additions and dependency fixes, as listed
  under Major 11 and Minor 6.

## Design Alignment

- **K1:** `commit-tree` in a temporary index in the gitdir, `push . R:live`,
  then `checkout --detach live`. The worktree never holds an uncommitted repair.
  A refused `live` update walks back with no ref reaching R.
- **K2:** attribution uses the check's own `$mempath` spelling. Resting with R
  in `live` needs no second repair (2.2/3). The unrepairable report attributes
  the problems to `live`, not to the clean worktree.
- **K3:** rule order, the tier-file guard, the duplicate pick against the pin,
  and byte preservation match the outline.
- **K4:** only problems attributed to the merged index block, and all others
  keep today's arms. The problem list prints, and `exit 1` comes before any
  `add`, which keeps `MERGE_HEAD` and the state file.
- **K5:** abort on rules 1/4/6 in a dirty file, restamp, and the advisory cases
  are unchanged. `gitlore_compose` rc 1 reaches the arm only from
  `gitlore_compose_check` (the pin guard runs first), so the helper sees only
  check output.
- **K6:** both push arms publish R before memory's push, which the `pre-receive`
  recording checks. `/gitlore:merge` leaves R local and names `/gitlore:push`.
- **m4:** statuses, the rest guard and the remedy match the minor-pass-2
  recommendation.
- Citations verified against the tree:
  - `tests/resolve_compose.bats:137`, `:143-147`, `:168`, `:221` and `:241`;
  - `tests/merge_memory.bats:331`, `:356`, `:375` and `:518`;
  - `tests/push_behind_vs_diverged.bats:234` and `:268`;
  - `tests/tier_divergence.bats:143`;
  - `tests/git_hook_pre_commit.bats:396`;
  - `docs/references/index-composition.md:116-120` and `docs/design.md:51`;
  - the four `push_or_report` call sites.
- The bats suites were not run, per the task constraints. One scratch probe (git
  2.47.3, under `$TMPDIR`) confirmed the text of a held-`live.lock` refusal for
  a local push.

## Orchestrator dispositions

The runbook `/proof` is skipped at my human partner's instruction, so the two
confirm-at-proof items were settled here:

- **Major 6 — accepted.** K6 already requires the take's report to name
  `/gitlore:push`; the line the review specified is its producer.
- **Minor 5 — changed.** The unrepairable report prints the first refusal's
  carrier problems, the arrival's own lines, so every `line <n>` uses the
  arrival's numbering. Slice 2.2/4 places an identical duplicate above the weld
  and asserts the arrival's line number, which differs from the repaired copy's.
