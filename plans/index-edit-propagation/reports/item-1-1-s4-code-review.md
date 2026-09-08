# Item 1.1 slice 4 — code review

Verdict: **accepted, no fixes applied.** All four mutations red the test they
were meant to red, on the first attempt, each on the assertion that carries the
behaviour. No implementation defect surfaced. One coverage residual is flagged
rather than fixed (§Residual), and one housekeeping note about gate sentinels is
left for the orchestrator (§Gates).

## The committed state is what it claims

Both checks run rather than taken from the GREEN report:

- `git show --stat 03fa5af` — two files, `tests/commit_memory.bats` (+93) and
  `tests/git_hook_pre_commit.bats` (+48), 141 insertions and 0 deletions.
  Nothing under `scripts/`.
- `git diff 62258fa..HEAD -- scripts/lib/resolve.sh` — empty. The RED back-out
  left no residue; the file is byte-for-byte what `62258fa` committed.

Baseline before any mutation,
`scripts/run-bats.sh tests/commit_memory.bats tests/git_hook_pre_commit.bats`:

```
bats: 33 passed, 0 failed
```

## Discrimination by mutation

Protocol for each: mutate `scripts/lib/resolve.sh` in place with a `python3`
edit that asserts the target line's exact current text before touching it (so a
mis-aimed mutation aborts rather than silently hitting a neighbour), run both
suites, restore with `git checkout HEAD -- scripts/lib/resolve.sh`, and confirm
`git diff --exit-code scripts/lib/resolve.sh` before the next one. No test file
was edited, moved or reordered at any point.

### Mutation 1 — rc-2 arm's `touch "$msgfile"` deleted (`resolve.sh:957`)

```
not ok 33 an aborted compose keeps the approved summary usable
# (in test file tests/git_hook_pre_commit.bats, line 377)
#   `[ "$status" -eq 0 ]' failed

bats: 32 passed, 1 failed
```

Reds on the *second* hook run's exit status — the retry that the restamp exists
to make possible — not on the first run or the fixture. Same test, same
assertion and same line as RED and the test review both recorded, now against
the committed tree rather than the backed-out one. Restored clean.

### Mutation 2 — `*)` arm's `touch "$msgfile"` deleted (`resolve.sh:974`)

```
not ok 14 an unrecognised compose status aborts and keeps the approval
# (in test file tests/commit_memory.bats, line 254)
#   `[ "$(gitlore_commit_msg_freshness memory)" = "yes" ]' failed
```

`bats: 32 passed, 1 failed`. Reds on the freshness assertion specifically — the
test's declared half of the red — while its non-zero-exit, unchanged-`HEAD` and
`unrecognised status (7)` assertions all still hold, so the arm is reached and
only the restamp is missing. Restored clean.

### Mutation 3 — rc-1 user arm's remedy sentence (`resolve.sh:937`)

`… ask it to repair the memory store."` →
`… ask it to repair the memory store, then retry."` — i.e. the exact regression
the slice-3 review's register fix removed, reintroduced.

```
not ok 15 the rc-1 user arm does not tell a user to retry a commit that succeeded
# (in test file tests/commit_memory.bats, line 278)
#   `[[ "$stderr" == *"ask it to repair the memory store."* ]]' failed
```

`bats: 32 passed, 1 failed`. Bats stops at the first failing assertion, so line
278 (the positive) is what is reported; the negative on line 279 would have
failed on the same output. This is the only evidence this characterization has,
and it is the right evidence: the mutation is the defect, not an arbitrary text
change. Restored clean.

### Mutation 4 — rc-2 user arm's remedy sentence (`resolve.sh:949`)

`… ask it to repair the memory store, then retry."` →
`… ask it to repair the memory store."`. Targeted at the rc-2 arm specifically,
as the test review's warning requires — the edit asserted
`'half-written carrier' in line` before applying, which is the rc-2 arm's own
text and absent from the `*)` arm.

```
not ok 16 the rc-2 user arm tells a user to retry
# (in test file tests/commit_memory.bats, line 304)
#   `[[ "$stderr" == *"ask it to repair the memory store, then retry."* ]]' failed
```

`bats: 32 passed, 1 failed`. Restored clean.

### Probe 5 — the shared-string claim, confirmed empirically

The test review's claim is that the rc-2 and `*)` user arms end with the same
sentence verbatim, so test 4 cannot distinguish them. Confirmed from source
first — `resolve.sh:949` and `resolve.sh:972` both end
`Open this project in Claude Code and ask it to repair the memory store, then retry."`
— and then by mutation: the same edit as mutation 4 applied to the `*)` arm at
line 972 (guarded on `'unknown state' in line`) gives

```
bats: 33 passed, 0 failed
```

**What that means, stated plainly.** A future edit to the rc-2 user arm's remedy
sentence alone is caught by test 4. A future edit to the `*)` user arm's remedy
sentence alone is caught by nothing: `grep -rn "repair the memory store" tests/`
returns exactly three hits, all in the two tests above, and none of them runs
against the `*)` arm's user branch. The two arms are not distinguished by test
4, and test 4's green in this probe is not evidence about the `*)` arm at all.

Restored clean after the probe.

## Slice 3's three gaps

- **Gap 1 — the lost approval: closed.**
  `an aborted compose keeps the approved summary usable`
  (`tests/git_hook_pre_commit.bats`) is the two-tier hook case the slice-3
  review described, and mutation 1 shows it is load-bearing on the restamp
  rather than on the fixture. This is the regression test `62258fa` shipped
  without.
- **Gap 2 — the user arm: closed, for both arms named.** Slice 3's report names
  the rc-1 register fix as the unasserted one;
  `the rc-1 user arm does not tell a user to retry a commit that succeeded`
  closes it (mutation 3), and `the rc-2 user arm tells a user to retry` covers
  the rc-2 side too (mutation 4). Both reach the user branch by
  `unset CLAUDECODE`, and neither agent arm contains the string its test
  asserts, so a `CLAUDECODE` leak fails the test rather than passing it
  vacuously.
- **Gap 3 — the `*)` arm: closed for its behaviour, open for its user text.**
  `an unrecognised compose status aborts and keeps the approval` drives the arm
  through a stub and pins the abort, the unchanged `HEAD`, the arm's own
  `unrecognised status (7)` literal and the restamp (mutation 2). What slice 3
  called "reasonable to leave uncovered" is now covered. The arm's user-facing
  remedy sentence is the one thing that remains unpinned — see below.

## Residual (flagged, not fixed)

The `*)` arm's user-branch remedy sentence has no assertion anywhere in the
suite (probe 5). Closing it is one `unset CLAUDECODE` plus one substring
assertion added to the `*)` test, but that test was reviewed and accepted at
dispatch (b), and the runbook enumerates that test's assertions by name without
this one — so adding it is a scope change, not a review fix, and it is the
orchestrator's call at the Phase 1 boundary checkpoint.

Weight, so the checkpoint can size it: the `*)` arm is unreachable through the
real `gitlore_compose`, which returns only 0, 1 or 2, so this text can only ever
be seen after some future change to that contract — at which point the arm's
behaviour is still pinned by the existing test and only its wording is not. Low
stakes; a deliberate decision either way is fine.

Not a new finding, and not a defect in the implementation: it is the exact
consequence the test review predicted, now measured rather than reasoned.

## Gates

`scripts/lib/resolve.sh` is byte-identical to `HEAD` — `git hash-object` gives
`6abbd2f4f680a9821f6c41d7280793b5517e7766`, matching
`git rev-parse HEAD:scripts/lib/resolve.sh`. But the five `git checkout`
restores bumped its mtime to `1788856910`, which now **postdates** all three
gate sentinels (`lint` 1788855915, `test-unit` 1788856428, `test-integration`
1788856482). So the sentinel test reads stale for this tree even though the
gated content never changed.

Left as is rather than back-dated: the sentinel mechanism exists so nobody has
to trust a content claim from a report, and quietly restoring the mtime would
defeat that. The orchestrator's call — either re-run `just precommit`, or accept
the hash identity above as the evidence.

`scripts/lint-shell.sh`: `lint-shell: 137 files clean` (run after the final
restore).

## Checks that passed

- `git show --stat 03fa5af` — no file under `scripts/`.
- `git diff 62258fa..HEAD -- scripts/lib/resolve.sh` — empty.
- Baseline both suites — 33 passed, 0 failed.
- Mutations 1–4 — each reds its intended test, on its intended assertion, one
  failure per run.
- Probe 5 — 33 green, establishing the non-discrimination between the rc-2 and
  `*)` user arms.
- `git diff --exit-code scripts/lib/resolve.sh` — clean after every mutation and
  at the end.
- `git status --short -- scripts/ tests/` — empty.
- `git hash-object scripts/lib/resolve.sh` ==
  `git rev-parse HEAD:scripts/lib/resolve.sh`.
- `scripts/lint-shell.sh` — 137 files clean.

`tests/integration_gitlink_staging.bats` was not run: nothing was left changed,
so the `GIT_INDEX_FILE` handoff boundary is untouched.

## Scope

No file changed. Nothing staged, nothing committed. The three earlier report
files under `plans/index-edit-propagation/reports/` were left untracked, and the
untracked dotfiles at the repo root were not touched.
