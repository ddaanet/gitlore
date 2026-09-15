# Deliverable review: tests (unadoptable tier arrival)

## Scope reviewed

Range `e60ff38..HEAD`, test files only, against outline S1–S4 and the code under
test (`scripts/lib/index-compose.sh`, `scripts/lib/resolve.sh`,
`scripts/resolve.sh`, `scripts/cc-hooks/memory-commit-batch.sh`).

- `tests/index_compose.bats` 1105–1127, 1143–1369
- `tests/commit_memory.bats` 140–322
- `tests/git_hook_pre_commit.bats` 391–426
- `tests/merge_memory.bats` 558–980
- `tests/push_behind_vs_diverged.bats` 320–452
- `tests/resolve_compose.bats` 12–14, 140–288, 394–466, 519–651
- `tests/tier_divergence.bats` 179–199
- `tests/cc_hook_memory_commit_batch.bats` 141–160
- RED claims: `reports/item-*-red.md`, `reports/tdd-audit.md`,
  `reports/phase-{1..4}-corrector.md`. I read them and did not rerun them.

What I checked beyond the S1–S4 map:

- **Lock-holding tests.** All four export `GITLORE_GIT_RETRY_SCHEDULE=0`:
  `merge_memory.bats:813` and `resolve_compose.bats:556, 579, 612`. The
  message-file test at `resolve_compose.bats:394` fails on a `commit-msg` hook,
  not on a lock.
- **Dependence on `CLAUDECODE`.** Every assertion whose text differs between the
  agent arm and the user arm sets `CLAUDECODE` explicitly
  (`commit_memory.bats:159, 176`, `git_hook_pre_commit.bats:414`,
  `cc_hook_memory_commit_batch.bats:150`). The other suites match only text both
  arms print. I checked this against the sources: the merge-directive header,
  "no approved commit summary", "could not fetch", "has uncommitted changes, so
  nothing was adopted", "was not committed", the rest-guard remedy (plain
  `printf`) and "not because of divergence".
- **Bats pitfalls.** No test has a bare top-level `! cmd`; negations use `run !`
  or `! … || false`. No assertion comes after an early return. No `run` goes
  unchecked where its status matters.
- **BSD portability.** `sed -i.bak`, `touch -t`, `find -print0` / `-quit`,
  `cmp --` and `ls -A` ordering all work on BSD.
- **Invocation path.** The take runs through `scripts/merge-memory.sh` and the
  push through `scripts/push-memory.sh`. The continuation runs through
  `resolve.sh continue-after-merge` directly or via `run_stub_synth`, which
  reads the continuation from the state file. The hooks run through
  `scripts/git-hooks/pre-commit` / `pre-push`. All of these are the production
  entry points. `gitlore_repair_index` and `gitlore_compose_problems_in` are
  called with the same argument shape their production callers use.

## Critical

None.

## Major

None. Every postcondition in S1–S4 maps to at least one test that can fail (see
the map below). Where a postcondition is only partly asserted, it is listed
under Minor.

## Minor

### m1. The attribution helper's test does not pin the anchored prefix

- **Location:** `tests/index_compose.bats:1105-1127`
- **Axes:** specificity, vacuity

**The gap.** The test is named "matches the exact file prefix". Its decoys catch
a regex matcher (`my memXd`), a word-splitting matcher and a
prefix-of-another-tier matcher (`a` vs `ab`). None of them catches an unanchored
fixed-string match. No input line has the queried file as a *suffix* of a longer
path.

**Probe.** I ran a scratch function `grep -F -- "$1: "` against the test's own
input:

- It returned exactly the expected output for all three queries: rc 0 / 0 / 1.
- It also attributed `memory/org/memory/MEMORY.md: duplicate pointer path x.md`
  to `memory/MEMORY.md`.

**Consequence of that mutant.** A tier whose path ends in the store's own
basename would have its carrier problems attributed to root. In K5 the abort
would then read root's dirtiness. In K4 a memory-root merge would be blocked on
a tier problem.

**RED report.** The slice 6 mutations in `item-1-1-s2-6-red.md` tried
`grep "^$file: "` and word-splitting, not this.

**Fix.** Add a decoy line such as `x/my mem.d/MEMORY.md: …`.

### m2. The unrepairable-arrival test does not pin the worktree-carrier attribution

- **Location:** `tests/merge_memory.bats:744-778`
- **Axis:** specificity

**Unpinned attribution.** K2 says the report attributes the remaining problems
"to the arrival held in the tier's `live`, never to the worktree carrier". The
test asserts:

- the `live:MEMORY.md: line $weld_line_n welds` line;
- no `line $((weld_line_n - 1))`;
- no "Fix the store".

Nothing rejects a `memory/ddaanet/MEMORY.md:`-prefixed line. A mutant that also
prints the first refusal block would survive: today's
`gitlore: the root index could not take …` header plus the worktree-prefixed
problems, ahead of the new report. The slice 3 negative on
`duplicate pointer path` (line 719) cannot stand in for it here, because this
arrival's own `live:`-prefixed list legitimately contains that phrase.

**Unasserted commit.** "Nothing is committed" is asserted only for the tier.
Memory HEAD is not captured.

**Status:** unprobed.

### m3. S1's "aborts the same way" is only partly asserted per entry point

- **Locations:** `tests/commit_memory.bats:187-203`,
  `tests/git_hook_pre_commit.bats:391-426`
- **Axis:** coverage

What the tests leave out:

- **Root weld.** It runs only through `commit-memory.sh`, with no
  approval-restamp assertion and no `pre-commit` run.
- **Carrier-duplicate hook test.** It has no tier `live` pin, because a fresh
  mount has no local `live`, and it checks `status -ne 0` rather than `-eq 1`.
- **Restamp.** It is asserted only on the hook path.

The shared `gitlore_sync_memory_to_live` body keeps the practical risk low.
Still, the outline's per-entry-point postcondition is spread across the two
suites rather than held by both.

### m4. Rules asserted only through a sibling rule

- **Axis:** coverage

What is not tested:

- **Rule 4 (interleaved line), K5 abort.** No commit-path test aborts on a dirty
  root or dirty carrier holding an interleaved line.
- **Rule 2 (manifest lists an unmounted tier), K5 advisory arm.** Nothing tests
  it.
- **Rule 4, K4 merged-root gate.** Nothing tests it.

All three go through the same `"<file>: "` attribution as rules 1, 6 and 3,
which are tested, so the gap is small. The outline lists them under K4/K5 rather
than as S1/S3 postconditions.

### m5. A shipped test cites an outline decision id

- **Location:** `tests/index_compose.bats:1143`
- **Axis:** conformance

The section header reads `# --- gitlore_repair_index (K3): …`. K3 is an
`outline.md` id. `git grep -E '\bK[0-9]\b' HEAD -- tests scripts` finds only
this line. Drop the parenthetical.

### Tracked follow-ups

- (tracked) Item 2.2 slice 6 (`merge_memory.bats:812`): its red came from the
  feature being absent, and no red comes from a mutation of the refused `push .`
  arm.
- (tracked) Untested: a failed `git status` in the rc 1 arm; the repair keeping
  the file mode; `--no-filters` keeping CRLF.
- (tracked) `resolve_compose.bats` is over the 400-line cap.

### RED evidence check (read, not rerun)

The claimed reds fit the assertions as written:

- **2.2 slices 1–5.** Each red came from pre-job code walking the tier back
  (status 1, old header). That is consistent with the `status -eq 0` and
  report-line assertions. Slice 3's red on the report line is correct: status
  and `gone/x.md` held by coincidence.
- **2.3 slice 2 (behind arm).** Without the retry push, memory's pre-receive
  snapshot records the unrepaired arrival, so `[ "$(cat "$hookfile")" = "$R" ]`
  reds. The fixture really reaches the behind arm: `mount_tier_at_live` leaves
  HEAD equal to `live`, so the live-ahead arm cannot fire.
- **2.3 slice 3 (fetch first).** Adopting before the fetch builds a sibling R
  that diverges from `fixed_sha`. That reds `HEAD = fixed_sha` and the
  `!= *"repaired"*` negative.
- **3.1.** On pre-job code a merge that lands exits 0, which reds `status -eq 1`
  in slices 1 and 4. The guards in slices 2 and 3 were proven by mutating a
  green sketch.
- **3.1 corrector guard, no mutation on record** ("incoming side welds",
  `resolve_compose.bats:255`). By reading, deleting the gate's `exit 1` sends
  the attributed carrier problem to the `tier_unadopted` arm, which lands with
  exit 0. That reds line 272's `status -eq 1`, so the guard is not vacuous.
- **Review-added test with no author and no red on record**
  (`merge_memory.bats:594`). By reading, a missing or empty pin path makes the
  pin "lack all" lines, so the first line (`— old`) survives. That reds the
  `grep -cxF '— new'` count, so the claim is plausible.
- **4.1.** On pre-job code, `push_or_report` exited before the rest, which reds
  `HEAD = pin` at line 543. The remedy-cascade reds are consistent too.
- **Phase 4 corrector.** On pre-job order memory's gates ran first and published
  memory, which reds the check that memory's remote is still at `$published`
  (`tier_divergence.bats:198`). The leftover-message-file test reds on the
  leftover `gitlore-merge-msg.*`.

## Conformance map

### S1 — Prevention

| Postcondition | Test |
|---|---|
| Dirty carrier duplicate aborts via `commit-memory.sh`: names problem, tier and memory uncommitted, `live` unmoved | `commit_memory.bats:140` (both arms, 159–184) |
| … via `pre-commit`, approval restamped | `git_hook_pre_commit.bats:391` (restamp at 425; no `live` pin, m3) |
| Dirty root weld aborts the same way | `commit_memory.bats:187` (commit-memory only, no restamp, m3); batch hook: `cc_hook_memory_commit_batch.bats:141` |
| Abort names every changed problem file, no clean one | `commit_memory.bats:205` |
| Clean-tier carrier defect commits and reports | `commit_memory.bats:236` |
| Tier dirty only outside its carrier commits and reports | `commit_memory.bats:253`; root counterpart `:289` |
| Rule 3 leftover in dirty root commits and reports | `commit_memory.bats:308` |
| Helper: `$mempath` with a space, prefix tier names | `index_compose.bats:1105` (anchoring unpinned, m1) |
| Arm comment states abort vs report | code comment at `scripts/lib/resolve.sh` rc 1 arm (not a test) |

### S2 — Unit (`gitlore_repair_index`)

| Postcondition | Test |
|---|---|
| Weld alone | `index_compose.bats:1188` |
| Interleaved line alone | `index_compose.bats:1263` |
| Identical duplicate alone | `index_compose.bats:1174` |
| Three-bullet weld | `index_compose.bats:1204` |
| Bare `[x](y.md)` with `y.md` in tier unchanged | `index_compose.bats:1248` |
| Weld naming no tier file unchanged | `index_compose.bats:1220`; containment `:1235` |
| Differing duplicate keeps pin-lacking line, even second | `index_compose.bats:1277`; several lacking `:1293` |
| New to both keeps first | `index_compose.bats:1305` |
| Known to both keeps first | `index_compose.bats:1315` |
| Pin with no `MEMORY.md` | `index_compose.bats:1325` |
| Result passes check; unnamed lines keep bytes and order | `index_compose.bats:1174, 1188, 1204, 1263, 1334` (cmp and check) |
| Clean index byte-identical | `index_compose.bats:1150` (including inode and unterminated) |
| Unwritable rewrite leaves file unchanged | `index_compose.bats:1350` |

### S2 — Take

| Postcondition | Test |
|---|---|
| Carrier-only: exit 0, R single parent, HEAD and `live` are R, pair committed, report lists edits, origin unchanged, names `/gitlore:push` | `merge_memory.bats:558`; weld `:634`; interleaved `:682`; pin-aware pick `:594` |
| … through push, `live`-ahead arm, tier origin holds R before memory records it | `push_behind_vs_diverged.bats:338` |
| … through push, `behind` arm | `push_behind_vs_diverged.bats:376` |
| Carrier plus root problem: R in `live`, tier on pin, exit 1 listing only the root problem; next take adopts R with no second repair | `merge_memory.bats:703`; inside a push, publishes nothing until fixed `push_behind_vs_diverged.bats:404` |
| No problem names carrier: walk back, `live` on arrival | `merge_memory.bats:356` (existing, unchanged) |
| Check still refuses after repair: nothing committed, clean walk-back, problems attributed to `live` | `merge_memory.bats:744` (m2) |
| Refused `live` update: pin, clean, `live` on arrival, no ref reaches R, git's message, next take repairs | `merge_memory.bats:812` (slice 6 red tracked) |
| Walk-back leaves `live` containing HEAD | implied by `HEAD = pin` plus `live` = arrival or stranded commit at `merge_memory.bats:744, 812`, `:356` (no explicit `merge-base`) |
| Fetch first: takes another consumer's published repair | `merge_memory.bats:859` |
| Failed fetch still adopts, reports, exit 1 | `merge_memory.bats:908`; no remote `:933`; failed adoption plus failed fetch `:958` |
| Reach via `gitlore_adopt_advanced_live` | `merge_memory.bats:780` |
| Reach via remote fast-forward | `merge_memory.bats:558` |

### S3 — Continuation gate

| Postcondition | Test |
|---|---|
| `head-vs-remote` tier merge with duplicate: exit 1, problems listed, state and `MERGE_HEAD` kept, no tier commit, root untouched | `resolve_compose.bats:164` |
| Same for `head-vs-live` | `resolve_compose.bats:183` |
| Later gate re-emits directive | `resolve_compose.bats:202`; unapproved parent commit `:232` |
| Fixed carrier lands | `resolve_compose.bats:213`; incoming weld then split synthesis publishes `:255` |
| Passing carrier beside root problem lands and rests | `resolve_compose.bats:290` (existing) |
| Memory-root merge with welded line exits 1 | `resolve_compose.bats:434` |
| Old "never strands the merge" inverts | `resolve_compose.bats:415` |
| Rule-3-only root merge commits uncomposed | `resolve_compose.bats:452` |

### S4 — Per-arm exits and rest guard

| Postcondition | Test |
|---|---|
| Origin push declined by `pre-receive`: tier on pin, `live` on merge, exit 1 | `resolve_compose.bats:527` |
| Held `live.lock`: tier on merge, remedy printed, exit 1 | `resolve_compose.bats:547` |
| Following the remedy then `/gitlore:merge` adopts | `resolve_compose.bats:573`; remedy's second line inert while still locked `:607` |
| Default-mode `check_store_gates` exits 1 on status 2 | `resolve_compose.bats:632` |
| Tier gates before memory's | `tier_divergence.bats:179` |
