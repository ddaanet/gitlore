# Review: Item 1.1 slice 1 — test review (RED)

**Scope**: `tests/commit_memory.bats` "a dirty carrier with a duplicate pointer
aborts the memory commit"; `reports/item-1-1-s1-red.md`; the
`gitlore_compose_problems_in` stub in `scripts/lib/index-compose.sh`, checked
only for stub completion. **Date**: 2026-09-14 **Mode**: review + fix

## Summary

The test was red for the right reason: it fails on `[ "$status" -eq 1 ]`, not on
an error. The RED report's claim about `branch -f live` holds. Two plausible
wrong implementations still passed, though. One aborted but still printed the
advisory text. The other aborted only on the agent arm (`CLAUDECODE` set) and
left the user arm, the other half of `gitlore_say_for_agent_or_user`, printing
"the commit went ahead". Both gaps are fixed. The test is still red on the same
assertion, and a correct abort turns it green.

**Overall Assessment**: Ready

## Mechanical check

`scripts/run-bats.sh tests/commit_memory.bats --filter 'a dirty carrier with a duplicate pointer'`,
after the fixes:

```
not ok 1 a dirty carrier with a duplicate pointer aborts the memory commit
# (in test file tests/commit_memory.bats, line 161)
#   `[ "$status" -eq 1 ]' failed
bats: 0 passed, 1 failed
```

The test fails on an assertion. The stub needs nothing more: the test never
reaches `gitlore_compose_problems_in`, and the stub only has to define it.

## Mutation probes

Each probe changed `scripts/lib/resolve.sh` in place from a saved copy, ran the
test and restored the file. Afterwards `git diff --quiet scripts/lib/resolve.sh`
confirmed the file was restored.

| Mutant | Shape | Before fixes | After fixes |
|---|---|---|---|
| m1 | the rc 1 arm aborts on both arms (plausible correct green) | pass | **pass** |
| m2 | abort placed after `gitlore_sync_tiers_to_live` (tier committed, `live` moved) | red | red |
| m4 | the rc 1 arm keeps the advisory text, appends "aborted", returns 1 | **pass** | red (line 165) |
| m5 | only the agent arm says "aborted"; the user arm still says "went ahead" | **pass** | red (line 179) |

Other results:
- **The `live` assertion catches m2 by itself.** Under m2, with the dirtiness
  and tier-`HEAD` assertions removed, the test fails at
  `[ "$(git -C memory/ddaanet rev-parse live)" = "$tier_live_before" ]`. The RED
  report's claim is verified. A fresh mount has no local `live` (see the fixture
  notes in `tests/helpers/tier-fixtures.bash`), so `branch -f live` is what
  gives the assertion something to catch.
- **Ambient `CLAUDECODE`.** The ambient value is `1`. Under m5 with
  `env -u CLAUDECODE`, the agent-arm run still passed. So the `CLAUDECODE=1`
  prefix on `run` does reach `commit-memory.sh`, and that run does not depend on
  the environment.

## Issues Found

### Critical Issues

None.

### Major Issues

1. **The user arm was never exercised**
   - Location: `tests/commit_memory.bats`, the new test
   - Problem: Item 1.1 requires the abort text on both arms of
     `gitlore_say_for_agent_or_user`. The test ran only with `CLAUDECODE=1`. An
     implementation that changed only the agent string passed (m5), and so did
     one that aborted on both arms with the user arm still printing "the commit
     went ahead". No other slice covers the user arm.
   - Fix: a second run with `unset CLAUDECODE`, following the existing two-arm
     test in this file. It asserts status 1, "aborted", no "the commit went
     ahead", a positive read of the user arm's own sentence ("Open this project
     in Claude Code"), and that memory `HEAD`, tier `HEAD` and tier `live` are
     unchanged.
   - **Status**: FIXED

2. **"aborted" also matched an abort that kept the advisory text**
   - Location: `tests/commit_memory.bats`, the `*"aborted"*` assertion
   - Problem: an implementation that kept "the commit went ahead…" and appended
     an abort line with return 1 passed (m4). The output then says both that the
     commit went ahead and that it aborted. K5 says the abort replaces the
     advisory text.
   - Fix: pair the positive with
     `[[ "${output}${stderr}" != *"the commit went ahead"* ]]` on both arms. The
     positive stays the slice's bare `aborted`. Narrowing it further would tie
     the test to wording the GREEN step has not written yet. Every other abort
     in the function also says "the commit was aborted", so a longer phrase
     would not discriminate any better. The negative is what discriminates.
   - **Status**: FIXED

### Minor Issues

1. **The carrier and staging state were not pinned**
   - Location: `tests/commit_memory.bats`, after the run
   - Note: K5 says compose rc 1 writes nothing, and the slice requires the tier
     and memory to stay uncommitted. `status --porcelain -- MEMORY.md` being
     non-empty would not catch an abort that rewrote the carrier (for example
     one that ran S2's repair on the commit path) or one that staged changes
     before returning. Added: the carrier bytes are unchanged, and the full tier
     and memory `status --porcelain` output is unchanged, as the neighbouring
     pin-guard test already asserts.
   - **Status**: FIXED

2. **The test comment cited a runbook item and described today's code**
   - Location: `tests/commit_memory.bats`, the comment at the top of the test
   - Note: "Item 1.1 (K5)" breaks the dispatch constraint that source files cite
     no runbook item. "today it does" becomes false once the slice is green.
     Rewritten as the present-tense contract.
   - **Status**: FIXED

3. **The stub comment cited a slice, and the wrong one**
   - Location: `scripts/lib/index-compose.sh`, the comment above
     `gitlore_compose_problems_in`
   - Note: "Stub: Item 1.1 slice 2 implements it" breaks the same constraint,
     and the helper's own slice is slice 6. Now reads "Stub: matches nothing."
   - **Status**: FIXED

## Checks that raised nothing

- **Fixture matches the slice.** `make_tier_in_memory`, `set_tier_manifest`, the
  tier bullet seeded twice and the root bullet are all left uncommitted. The
  added `branch -f live` is the only extra step, and it is justified above.
- **The problem-line substring is specific.** Only `gitlore_compose_check_index`
  prints `memory/ddaanet/MEMORY.md: duplicate pointer path shared.md`. The
  assertion already passes on today's code, since the rc 1 arm prints it now. It
  is the positive a GREEN needs, not the assertion that turns the test red, and
  the report says so.
- **`CLAUDECODE=1` suits the first run.** `commit-memory.sh` is the agent's
  entry point, and the prefix makes the run independent of the environment
  (probed above).
- **Exit 1 for an unrelated reason.** A wrong implementation that exits 1 after
  committing the tier fails the tier `HEAD`, `live`, porcelain and dirtiness
  assertions. One that exits 1 while still printing the advisory text fails the
  new negative.

## Fixes Applied

- `tests/commit_memory.bats`, the new test: comment rewritten; carrier, tier and
  memory state captured before the run and compared after; negative
  `"the commit went ahead"` added; a second `unset CLAUDECODE` run added with
  its arm-identifying positive and the three ref checks.
- `scripts/lib/index-compose.sh`, the stub comment: slice citation removed.
- `shellcheck` passes on both files. The test is still red on
  `[ "$status" -eq 1 ]`.

## Positive Observations

- The RED report backs its failure claim with a probe run outside bats and shows
  the actual stderr.
- `branch -f live` addresses a real vacuity, and the report explains why.
