# Item 1.1 slice 2 — code review

Dispatch (d). Subject: everything `502703c` added to
`tests/git_hook_pre_commit.bats` — the shared fixture builder
`committed_stale_carrier_store`, the negative
`a clean store is not composed by the commit path`, and the positive
`the same store, made dirty, IS composed`. No implementation in this slice;
`scripts/lib/resolve.sh` is byte-identical to HEAD after this review.

Verdict: one major finding, fixed in place. One minor finding (a false mechanism
claim in the builder's comment), fixed in the same hunk. Everything else the
dispatch named checked out, including the report's own claims.

## Major — the negative could go vacuous, and nothing in the suite noticed

This is exactly the path staleness the runbook's own text worries about, left
unguarded. `gitlore_sync_memory_to_live` returns early when the store is clean
**and** `HEAD` equals `live`; the negative only tests the `dirty = 1` guard
because the fixture sits one commit past `live`. Nothing asserted that.

**Reproduced, not inferred.** With the SUT mutated so a clean store *is*
composed (mutation A below) and the builder's last line changed from
`branch -f live HEAD~1` to `branch -f live HEAD`:

```
bats: 16 passed, 0 failed
```

Both cases green against a SUT with the guard widened. The negative's four
assertions all held — `status 0`, `dirty = 0`, HEAD unchanged, carrier still
`stale hook` — because the function returned before reaching anything. The
positive stayed green too, so the runbook's prescribed pairing (a positive over
the same fixture, differing only in the trigger input) does **not** cover this
staleness: `dirty = 1` skips the early return, so the positive is insensitive to
the precondition the negative depends on.

The `live`-advanced observable does not discriminate either — under the drift
`live == HEAD` both before and after the run — so the only assertion that can
catch it is the precondition itself.

### The fix

Two checks at the end of `committed_stale_carrier_store`, where both cases pick
them up and each fails with its own reason:

```bash
  [ "$(gitlore_memory_dirty memory)" = "0" ] || {
    echo "committed_stale_carrier_store: store is dirty; the clean case would not reach the guard" >&2
    return 1
  }
  [ "$(git -C memory rev-parse HEAD)" != "$(git -C memory rev-parse live)" ] || {
    echo "committed_stale_carrier_store: HEAD is at live; a clean store returns before the guard" >&2
    return 1
  }
```

`commit_memory_state` and the `branch -f` also took the `|| return 1` the two
git calls above them already carry, so a fixture failure names itself rather
than arriving as a baffling assertion later.

Re-running the drift with mutation A still active now gives:

```
not ok 15 a clean store is not composed by the commit path
# committed_stale_carrier_store: HEAD is at live; a clean store returns before the guard
not ok 16 the same store, made dirty, IS composed
# committed_stale_carrier_store: HEAD is at live; a clean store returns before the guard
```

No assertion was added to either test body. A "the function body ran" check
there would have been the dead weight the dispatch asks about: given the
precondition and `status 0`, the only two exits are the early return (excluded
by the precondition) and the bottom `return 0`, which implies the `HEAD:live`
fast-forward already.

## Minor — `git -C memory branch -f live HEAD~1` is a no-op, and the comment said otherwise

The builder's comment claimed a clean store "built the obvious way" leaves HEAD
at `live`, and that "forcing HEAD one commit ahead of `live` instead" is what
gets past the early return. Measured:

```
after make_parent:          HEAD=624e187 live=624e187
after make_tier_in_memory:  HEAD=ab85e6e live=ab85e6e
after commit_memory_state:  HEAD=f0a184c live=ab85e6e  HEAD~1=ab85e6e
branch -f no-op: YES
```

`commit_memory_state` is what moves HEAD past `live` — `make_tier_in_memory`'s
fast-forward loop runs before it, and the memory commit after it advances HEAD
alone. The `branch -f` sets `live` to where it already is. The state the case
needs was real; the stated mechanism was not.

The line is kept rather than deleted — it *states* the required shape instead of
inheriting it from an incidental property of two other helpers, so it keeps the
fixture right if either stops producing it — and the comment now says that,
along with what the two new checks are for.

## Checked and sound — no change made

- **The fixture reaches the guard.** Measured directly, not read: after the
  builder, memory is on a detached HEAD (so `branch -f live` is legal),
  `gitlore_memory_dirty memory` = `0`, `git -C memory status --short` empty,
  `HEAD != live`. Running the hook over it advances `live` to HEAD, which only
  happens at the bottom of `gitlore_sync_memory_to_live` — so the run passes the
  clean-and-at-live early return, skips the `dirty = 1` branch, and reaches the
  `HEAD:live` fast-forward, which is the guard's own path.

- **The executor's deviation from the runbook's fixture recipe is correct, for
  the reason it gives.** Verified by dropping the tier-side commit: with only
  `seed_tier_bullet` + `commit_memory_state`, `gitlore_memory_dirty memory`
  prints `1` and `git -C memory status --short` shows ` m ddaanet`. The
  submodule stays "modified content", so the clean fixture is unreachable
  without a commit inside `memory/ddaanet`.

- **The negative is discriminating, and on the guard rather than on
  collateral.** Mutation A — the `dirty = 1` guard *widened* rather than the
  compose call hoisted:

  ```bash
    if [ "$dirty" = "0" ] && [ "$head_sha" = "$live_sha" ]; then
      return 0
    fi
    if [ "$dirty" = "0" ]; then gitlore_compose "$mempath" >/dev/null || true; fi
  ```

  ```
  not ok 15 a clean store is not composed by the commit path
  #   `[ "$(gitlore_memory_dirty memory)" = "0" ]' failed
  bats: 15 passed, 1 failed
  ```

  Only the negative reds, on the dirty-state assertion the dispatch names as the
  discriminating one. Re-run after the fix: identical result.

- **The other three assertions in the negative are not dead weight.**
  `[ "$status" -eq 0 ]` fails under a guard widened to run the whole dirty
  branch (no approved summary on a clean store → rc 1 and the FR11 directive);
  the HEAD-unchanged check fails under any mutation that lets the clean path
  commit; `assert_bullets` fails under mutation A too, and is only unreached
  because the dirty assertion precedes it. Exact-block equality rather than a
  present/absent pair is the right form here — `stale hook` is a variant of
  `fresh hook`.

- **The positive is a real control.** Same builder, and the delta is the guard's
  trigger input: one uncommitted `memory/local.md` plus its root bullet flips
  `dirty` 0 → 1 without touching the tier side. The approved summary it also
  writes is a consequence of that flip (the FR11 gate refuses a dirty store
  without one), not a second variable. It stayed green under mutation A, as a
  control must, and it has its own test body rather than sitting behind the
  negative under errexit.

- **The collateral red in the GREEN report is a mutation artifact, not a
  fragility in the committed ordering.** The report attributes slice 1's case
  redding to the executor's mutation being hoisted above
  `gitlore_commit_msg_freshness`. That holds: `gitlore_commit_msg_freshness`
  (`scripts/lib/util.sh:275`) compares the msgfile's mtime against the newest
  mtime under `$mempath` (`find "$mempath" -type f -not -path '*/.git/*'`),
  which includes the tier worktrees — so a compose ahead of it restamps a
  carrier and the approved summary reads stale, which is the FR11 message the
  report quotes. Mutation A, which leaves the dirty path's ordering untouched,
  reds nothing but the negative. In the committed code the compose sits after
  `$fresh` is read, and `gitlore_sync_tiers_to_live` never re-checks freshness.
  No finding.

- **Whitespace, quoting, portability.** Every command substitution in the new
  code is quoted at its use site; the only unquoted paths are the two literals
  `memory/ddaanet/MEMORY.md` and `ddaanet`. No word-split of a path, no `ls`
  parse. Nothing bash-4 (no `mapfile`, no `${v^^}`, no associative array, no
  `&>>`), and no GNU-only `sed`/`find`/`stat`/`grep`/`mktemp` invocation is
  introduced — the new lines are `git`, `printf`, `[`, `echo` only. macOS bash
  3.2 safe. `shellcheck -s bash tests/git_hook_pre_commit.bats` clean.

## Test evidence

- Baseline before any change:
  `scripts/run-bats.sh tests/git_hook_pre_commit.bats` → 16 passed, 0 failed.
- Mutation A against the committed tests → 15 passed, 1 failed (negative only).
- Fixture drift (`branch -f live HEAD`) + mutation A against the committed tests
  → **16 passed, 0 failed** — the vacuity this review fixes.
- After the fix: suite → 16 passed, 0 failed; mutation A → 15 passed, 1 failed
  on the same assertion; drift + mutation A → 2 failed, each naming the
  precondition.
- `scripts/lib/resolve.sh` restored after every probe; `git diff HEAD` names
  only `tests/git_hook_pre_commit.bats`.
- Two scratch `.bats` probes under `tests/` were run and deleted in the same
  call; `git status --short` carries no trace of them.
- `just precommit` not run — the orchestrator owns the gate.

## Not touched

`scripts/lib/resolve.sh` (mutated only as the probe above, then restored —
`git diff HEAD -- scripts/lib/resolve.sh` empty), the `|| true` placeholder,
slice 1's three cases, slice 3's `case` over `gitlore_compose`'s return code and
its message texts, every pre-existing case in either suite, `docs/`, and Phases
2 through 4. No test was relocated.

## Flagged refactoring

None.
