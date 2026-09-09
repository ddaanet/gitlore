# Item 1.2 slice 3 — RED

Verdict:
**one new case, born green, every assertion red'd by its own named mutation.**
`scripts/lib/resolve.sh` was mutated four times and restored after each; final
`git diff --exit-code` clean and `git hash-object` back to
`320eca29c44c95bab495b08e19cb36d6f75eafda`, the tree's pre-mutation blob.

## The case

`the pin-abort user arm tells a user to retry` in `tests/commit_memory.bats`
(new test, appended after `the rc-2 user arm tells a user to retry`). Fixture is
slice 1's pin-abort induction verbatim
(`a tier moved off its pin aborts the commit`'s fixture: an empty commit made
directly inside the tier worktree, never staged into memory's index), with
`CLAUDECODE` explicitly `unset` so the run reads the **user** arm.

## Per-assertion discrimination

Every mutation below was applied to `scripts/lib/resolve.sh` in place, run with
`env -u CLAUDECODE scripts/run-bats.sh --jobs 1 tests/commit_memory.bats`, and
restored from `/tmp/claude/i12s3/resolve.sh.orig` before the next. Baseline
(unmutated): `bats: 19 passed, 0 failed`.

| # | assertion | mutation that reds it | verdict | other tests moved |
|---|---|---|---|---|
| 1 | `[ "$status" -ne 0 ]` | the pin-abort arm's `return 1` → `return 0` | red, line 420 (`[ "$status" -ne 0 ]`) | yes — also reds `a tier moved off its pin aborts the commit` (line 184, same assertion shape, same guard) |
| 2 | `$stderr` has `moved off the commit the memory store records for it` | `pin_header` reworded `moved off` → `relocated away from` | red, line 425 | yes — also reds `a tier moved off its pin aborts the commit` (line 202), which asserts the same header positively over the agent arm |
| 3 | `$stderr` has `ask it to repair the memory store, then retry.` | the user remedy's `repair` → `fix` | red, line 426 | none — only test 19 failed (`18 passed, 1 failed`) |
| 4 | `$stderr` does **not** have `Return the tier to its pin` | the user remedy reworded to `Return the tier to its pin, or open this project in Claude Code and ask it to repair the memory store, then retry.` (mutation 3's shape, applied so the earlier text stays intact) | red, line 427 (`[[ "$stderr" != *"Return the tier to its pin"* ]]' failed`) | none — only test 19 failed (`18 passed, 1 failed`) |

Verbatim, in order:

```
not ok 19 the pin-abort user arm tells a user to retry
# (in test file tests/commit_memory.bats, line 420)
#   `[ "$status" -ne 0 ]' failed

not ok 19 the pin-abort user arm tells a user to retry
# (in test file tests/commit_memory.bats, line 425)
#   `[[ "$stderr" == *"moved off the commit the memory store records for it"* ]]' failed

not ok 19 the pin-abort user arm tells a user to retry
# (in test file tests/commit_memory.bats, line 426)
#   `[[ "$stderr" == *"ask it to repair the memory store, then retry."* ]]' failed

not ok 19 the pin-abort user arm tells a user to retry
# (in test file tests/commit_memory.bats, line 427)
#   `[[ "$stderr" != *"Return the tier to its pin"* ]]' failed
```

All four discriminate: each was observed failing on its own line, so each is
proven to execute *and* to be capable of failing.

### Assertion 4 — the dispatch's target mutation, isolated

The dispatch's literal mutation 3 — collapsing the two
`gitlore_say_for_agent_or_user` arguments so the agent text is passed as both —
was tried first and does red assertion 4, but under errexit the test body never
reaches line 427: that full collapse also deletes
`ask it to repair the memory store, then retry.` from the user arm, so assertion
3 reds first (`not ok 19 … line 426`) and the run stops there. That proves the
collapse is a real defect, but it does not prove assertion 4 *specifically*,
since assertion 3's fragment happens to be destroyed by the same edit.

The mutation recorded in the table above is the narrower one that isolates
assertion 4: it keeps `ask it to repair the memory store, then retry.` intact in
the user text and prepends the agent's `Return the tier to its pin` fragment
ahead of it, the shape a partial arm-collapse (or a copy-paste of the agent
sentence into the user one) would produce. Assertions 1–3 hold under it (the run
reaches line 427), and assertion 4 reds there and only there. This is the
discriminating proof the dispatch asked for; the full-collapse mutation is
recorded above as the literal mutation 3, which also reds the case but via
assertion 3, one line earlier.

### Assertion 3's fragment, checked for what it discriminates

`ask it to repair the memory store, then retry.` is shared verbatim with the
rc-2 and `*)` user arms (`scripts/lib/resolve.sh:973,996`), so on its own it
cannot tell this test's arm apart from those. Paired with assertion 2 (the pin
header, which has exactly one producer — `scripts/lib/resolve.sh:928` — and is
unique to this arm), the pair pins the arm correctly: assertion 2 proves *which*
header fired, assertion 3 proves the retry-remedy ending is intact. Measured
directly rather than inferred: mutating only the pin-abort arm's `repair` →
`fix` (leaving the rc-2 and `*)` arms' own
`repair the memory store, then retry.` text untouched) reds test 19 alone —
`18 passed, 1 failed`, no other case moved — which confirms the fragment's
producer for *this* test is the pin arm's own string, not a coincidental match
against a sibling arm.

## Overlap with the neighbouring user-arm tests — checked, none found

- `the rc-1 user arm does not tell a user to retry a commit that succeeded` —
  different fixture (manifest `phantom` induction, a `gitlore_compose_check`
  refusal that leaves the commit reached and `HEAD` advanced) and opposite
  outcome (`status -eq 0`, `HEAD` changed). No assertion in common: that test
  asserts absence of `repair the memory store, then retry` (no comma-then form)
  and presence of the period-ended `ask it to repair the memory store.`; this
  test asserts the opposite ending, correctly, since here a retry is the right
  instruction. Disjoint fixtures and disjoint assertions.
- `the rc-2 user arm tells a user to retry` — different fixture (`chmod a-w`
  write-failure induction) and different header producer
  (`could not write an index`, not `moved off the commit …`). Shares the literal
  `ask it to repair the memory store, then retry.` ending — the same sharing the
  dispatch flagged and this report's "assertion 3" section addresses — but no
  other overlap; the two tests pin different headers and different fixtures, so
  consolidating them is not indicated.

No duplication found. This case is the only one pinning the pin-abort arm's
user-facing text.

## The three-ambient-world `CLAUDECODE` runs

`gitlore_say_for_agent_or_user` branches on `[ -n "${CLAUDECODE:-}" ]`, and this
subagent's shell has `CLAUDECODE=1` ambient — exactly the environment that would
hide a broken `unset CLAUDECODE` in the test body. All three worlds give the
same verdict:

```
scripts/run-bats.sh --jobs 1 tests/commit_memory.bats      (ambient CLAUDECODE=1)
  bats: 19 passed, 0 failed

env -u CLAUDECODE scripts/run-bats.sh --jobs 1 tests/commit_memory.bats
  bats: 19 passed, 0 failed

env CLAUDECODE=0 scripts/run-bats.sh --jobs 1 tests/commit_memory.bats
  bats: 19 passed, 0 failed
```

The unset run is the load-bearing one: the new test's own body calls
`unset CLAUDECODE` regardless of the ambient value, so all three worlds exercise
the same (user) arm and agree. `shellcheck -s bash tests/commit_memory.bats` —
exit 0, no findings.

## Restoration and cleanup

```
git diff --exit-code scripts/lib/resolve.sh   → clean
git hash-object scripts/lib/resolve.sh
320eca29c44c95bab495b08e19cb36d6f75eafda      # pre-mutation blob, matches item-1-2-s2-test-review.md's recorded value
git status --short
 M tests/commit_memory.bats
```

No scratch files created outside `/tmp/claude/i12s3/` (the mutation backup,
outside the repo tree). `just precommit` not run, per the dispatch. Nothing
committed.
