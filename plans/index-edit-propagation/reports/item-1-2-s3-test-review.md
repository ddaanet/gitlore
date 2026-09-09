# Item 1.2 slice 3 — test review

Verdict: **ships, with one comment fix applied.** Every assertion in the new
case was individually red'd by a mutation I reproduced myself, including the one
the RED report's table omits. The RED report's central finding — that the
literal arm-collapse reds assertion 3 rather than assertion 4 — is correct as
written, and the collapse does red the committed test, so slice 1's mutation-3
gap is closed. The negative cannot go vacuous: a misrouted message reds a
positive above it, measured rather than argued.

`scripts/lib/resolve.sh` was mutated seven times and restored after each; final
`git diff --exit-code` clean and `git hash-object` back to
`320eca29c44c95bab495b08e19cb36d6f75eafda`, the pre-review blob.

## Baseline

Born green, so a passing run proves nothing on its own. Recorded to establish
the starting point (ambient `CLAUDECODE=1`):

```
scripts/run-bats.sh --jobs 1 tests/commit_memory.bats
bats: 19 passed, 0 failed
```

## The case has five assertions, not four

The RED report's table covers four. The test body carries five:

| line | assertion |
|---|---|
| 420 | `[ "$status" -ne 0 ]` |
| 421 | `git -C memory rev-parse HEAD` unchanged |
| 425 | `$stderr` has `moved off the commit the memory store records for it` |
| 426 | `$stderr` has `ask it to repair the memory store, then retry.` |
| 427 | `$stderr` does **not** have `Return the tier to its pin` |

Line 421 is an addition beyond what the runbook's slice 3 lists (non-zero exit
plus the three `$stderr` assertions). It is measured below rather than left
implied.

## Per-assertion discrimination — reproduced, not accepted

Every mutation was applied to `scripts/lib/resolve.sh` in place, run with
`scripts/run-bats.sh --jobs 1 tests/commit_memory.bats`, and restored from
`/tmp/claude/i12s3rev/resolve.sh.orig` before the next.

| # | assertion | mutation that reds it | verdict | other tests moved |
|---|---|---|---|---|
| 1 | line 420, `status` | the pin arm's `return 1` → `return 0` (`resolve.sh:935`) | red, line 420 | yes — `a tier moved off its pin aborts the commit` reds too, line 184 |
| 1′ | line 420, `status` | the pin arm's `return 1` **deleted** — report and continue, the pre-Item-1.2 behaviour | red, line 420 | yes — test 12, line 184 |
| 2 | line 421, HEAD | mutation 1′ **plus** the two assertions swapped in the test body so HEAD runs first | red, line 420 (`rev-parse HEAD` = `$head_before`) | yes — test 12, line 184 |
| 3 | line 425, header | `pin_header` reworded `moved off` → `relocated away from` (`:928`) | red, line 425 | yes — test 12, line 202, same phrase asserted positively over the agent arm |
| 4 | line 426, retry ending | the **user** remedy's `repair` → `fix` (`:934` only) | red, line 426 | none — `18 passed, 1 failed` |
| 5 | line 427, the negative | the user remedy reworded to `… Return the tier to its pin, or open this project in Claude Code and ask it to repair the memory store, then retry.` — the agent fragment prepended, the retry ending left intact | red, line 427 | none — `18 passed, 1 failed` |

Verbatim, in order:

```
not ok 19 … line 420  `[ "$status" -ne 0 ]' failed                       (mutation 1)
not ok 19 … line 420  `[ "$status" -ne 0 ]' failed                       (mutation 1′)
not ok 19 … line 420  `[ "$(git -C memory rev-parse HEAD)" = "$head_before" ]' failed   (mutation 2, swapped body)
not ok 19 … line 425  `[[ "$stderr" == *"moved off the commit the memory store records for it"* ]]' failed
not ok 19 … line 426  `[[ "$stderr" == *"ask it to repair the memory store, then retry."* ]]' failed
not ok 19 … line 427  `[[ "$stderr" != *"Return the tier to its pin"* ]]' failed
```

All five discriminate: each was observed failing on its own line, so each is
proven to execute *and* to be capable of failing. Nothing here is verified
solely by having been written.

**Line 421 is non-vacuous but not independently discriminating.** Mutation 1
(`return 0`) returns from `gitlore_sync_memory_to_live` before the commit, so
HEAD does *not* advance and only the exit code moves — the measurement that
distinguishes the two mutations, and the reason 1′ was needed. Under 1′ the
commit lands and HEAD advances, which is the state line 421 exists to catch, but
line 420 reds first under errexit. No single mutation reds 421 while 420 holds.
It duplicates `a tier moved off its pin aborts the commit`'s own HEAD-unchanged
assertion over the same fixture, differing only in `CLAUDECODE` — the same
genuine-duplicate shape slice 2's review found between the manifest agent- and
user-arm cases, and kept for the same reason: dropping it would not make the
case any sharper, and its red under 1′ is real. Recorded, not removed; the
slice's own list does not carry it, so removing it is the orchestrator's call
rather than mine.

## The full arm-collapse versus the narrow mutation

**Does the committed test red under the literal full arm-collapse? Yes.** I ran
it — both `gitlore_say_for_agent_or_user` arguments replaced by the agent text,
`resolve.sh:930-934`:

```
not ok 19 the pin-abort user arm tells a user to retry
# (in test file tests/commit_memory.bats, line 426)
#   `[[ "$stderr" == *"ask it to repair the memory store, then retry."* ]]' failed

bats: 18 passed, 1 failed
```

It reds on **assertion 3 (line 426)**, exactly as the RED report says, and for
the reason it gives: the agent sentence ends
`…, then retry the commit — the approved summary is still in place.`, so
collapsing the arms destroys the
`ask it to repair the memory store, then retry.` fragment, and errexit stops the
body one assertion before the negative.

**That is sufficient to call slice 1's mutation 3 closed.** The defect is
detected by the case, on an assertion, with no other test moving. Which line
catches it is a property of ordering, not of coverage — the requirement is that
the arm-collapse cannot ship green, and it cannot.

**And the narrow mutation is not doing something materially different.** It is
the same defect with one degree of freedom removed. A collapse has two
observable consequences on the user channel: the user's own text disappears
(caught by assertion 3) and the agent's text appears (caught by assertion 4).
The full collapse produces both at once and errexit reports only the first; the
narrow mutation — the agent's `Return the tier to its pin` prepended to an
otherwise-intact user remedy, the shape a partial collapse or a copy-paste of
the agent sentence produces — produces only the second, which is what isolates
assertion 4. Together the two runs show the pair covers both halves of the
collapse rather than one half twice. The narrow mutation pins nothing the
literal one does not; it proves assertion 4 is live, which the literal one
cannot.

## Vacuity of the negative — measured

Assertion 4 is satisfied trivially by an empty or missing `$stderr`. What stops
that is assertions 2 and 3, which run first under errexit on the same channel.
Confirmed by mutation, not by argument: dropping the pin arm's own `>&2` so the
whole message goes to stdout instead —

```
not ok 12 a tier moved off its pin aborts the commit
# (in test file tests/commit_memory.bats, line 202)
#   `[[ "$stderr" == *"moved off the commit the memory store records for it"* ]]' failed
not ok 19 the pin-abort user arm tells a user to retry
# (in test file tests/commit_memory.bats, line 425)
#   `[[ "$stderr" == *"moved off the commit the memory store records for it"* ]]' failed

bats: 17 passed, 2 failed
```

The case reds on a **positive**, never passes on the negative. The second
protection is the pairing over the same fixture that
`memory/ddaanet/green-is-not-evidence.md` prescribes for a negative: the
neighbouring `a tier moved off its pin aborts the commit` asserts
`Return the tier to its pin with the command above` *positively* over this
identical fixture, differing only in `CLAUDECODE`. Measured — rewording the
agent remedy so `Return the tier to its pin` appears nowhere in `scripts/`
(`grep -c` → 0) reds test 12 alone on line 204 and leaves test 19 green
(`19 passed, 1 failed`, the count including the throwaway probe below). So a
wording drift that would leave this negative refuting a phrase no producer emits
is caught by the positive, not silently absorbed.

## Assertion order and death points

The body runs under errexit, so each mutation names where the body stops:

- mutation 1 and 1′ — stops at 420; nothing after it runs.
- mutation 2 (1′ with 420/421 swapped) — stops at the HEAD assertion; so 421 is
  reached and can fail.
- mutation 3 — stops at 425; 420 and 421 ran and held.
- mutation 4 — stops at 426; 420, 421 and 425 ran and held.
- mutation 5 — stops at 427; every earlier assertion ran and held.
- unmutated — all five run and hold, in all three ambient `CLAUDECODE` worlds.

## `unset CLAUDECODE` scoping — measured, no leak

bats runs each `@test` body in its own subshell, so the `unset` cannot reach a
later test in the file. Measured rather than assumed: a throwaway probe test
appended after the case under review, asserting `[ -n "${CLAUDECODE:-}" ]`, run
in the ambient `CLAUDECODE=1` world. It **passed** (only test 12 failed in that
run, from the agent-remedy mutation it was bundled with), so `CLAUDECODE` was
still set for the following test after test 19 unset it. The probe was deleted;
`git status --short` below shows no untracked test.

All three ambient worlds agree, re-run after the comment fix below:

```
scripts/run-bats.sh --jobs 1 tests/commit_memory.bats      (ambient CLAUDECODE=1)
  bats: 19 passed, 0 failed
env -u CLAUDECODE scripts/run-bats.sh --jobs 1 tests/commit_memory.bats
  bats: 19 passed, 0 failed
env CLAUDECODE=0 scripts/run-bats.sh --jobs 1 tests/commit_memory.bats
  bats: 19 passed, 0 failed
```

The unset run is the load-bearing one — the case's assertions are on the user
arm, which only prints when `CLAUDECODE` is empty or unset — and the
`CLAUDECODE=0` run covers the non-empty-but-falsy ambient value, which selects
the *agent* arm for any call the test body did not unset for.
`shellcheck -s bash tests/commit_memory.bats` — exit 0, no findings.

## Single-producer checks

| phrase | producers in `scripts/` | account |
|---|---|---|
| `moved off the commit the memory store records for it` | 1 — `resolve.sh:928` | unique to this arm's header; mutating it reds tests 12 and 19 and nothing else |
| `Return the tier to its pin` | 1 — `resolve.sh:932`, the agent remedy | the negative's subject; removing it from the tree leaves test 19 green and reds test 12 |
| `ask it to repair the memory store, then retry.` | 3 — `resolve.sh:934` (this arm), `:973` (rc-2 user), `:996` (`*)` user) | shared, and the RED report's account is confirmed |

**The RED report's account of the shared fragment holds.** Mutating only `:934`,
leaving `:973` and `:996` intact, reds test 19 alone (`18 passed, 1 failed`),
which proves the fragment's producer *for this test* is the pin arm's own string
rather than a coincidental match against a sibling arm — the siblings' text was
still present in the tree and did not satisfy it, because their arms never run
on this fixture. On its own the fragment would not tell this arm apart from
those; paired with assertion 2, whose header has exactly one producer and is
unique to this arm, the pair pins the arm correctly. The comment in the test
body already says this.

## Item-level completeness — Item 1.2's message contract

Item 1.2 fixes three texts (`resolve.sh:928-934`). Each now has at least one
test that reds when that text alone changes, every one of them measured in this
review:

| text | pinned by | measured |
|---|---|---|
| header (`:928`) | `a tier moved off its pin aborts the commit` (line 202) and `the pin-abort user arm tells a user to retry` (line 425) | mutation 3 |
| agent remedy (`:932`) | `a tier moved off its pin aborts the commit` (line 204) | agent-remedy reword, reds test 12 alone |
| user remedy (`:934`) | `the pin-abort user arm tells a user to retry` (line 426) | mutation 4 |
| forwarded `$pin_problems` lines | `a tier moved off its pin aborts the commit` (line 203, `is checked out at`) | not re-measured — Item 1.1-era text from `gitlore_compose_check_pins`, outside this item's contract |

**The item's message-text contract is fully pinned at sentence granularity.**
What remains unasserted is sub-sentence text, reported and not fixed:

- Header — only `moved off the commit the memory store records for it` is
  asserted. The opening `gitlore: a tier was ` and the trailing
  `, so the commit was aborted rather than adopt the move:` could be rewritten
  without a red.
- Agent remedy — only `Return the tier to its pin with the command above` is
  asserted.
  `composing would have overwritten what that tier holds, and committing would have adopted the move silently.`
  and
  `or run /gitlore:merge to take its content properly, then retry the commit — the approved summary is still in place.`
  are unpinned. The `/gitlore:merge` clause is the one worth naming: it is the
  remedy the slice-1 residual (an interrupted merge continuation) relies on
  being present.
- User remedy — only `ask it to repair the memory store, then retry.` is
  asserted.
  `composing would have overwritten what that tier holds. Open this project in Claude Code and`
  is unpinned.
- `the parent pre-commit hook aborts on an off-pin tier`
  (`tests/git_hook_pre_commit.bats:225`) asserts no message text at all, by
  design — it is the second entry point for the *behaviour*, and the message
  arms live in the shared body one call below it.

None of these is a gap this slice should close: each is a fragment of a sentence
whose distinguishing phrase is already pinned, and adding assertions on the rest
would pin wording without pinning behaviour.

## Fix applied

One comment, to `the pin-abort user arm tells a user to retry` in
`/Users/david/code/gitlore/tests/commit_memory.bats`, immediately above the
negative. No assertion, fixture or name changed; suite still
`19 passed, 0 failed` in all three ambient worlds and `shellcheck -s bash`
clean.

The two things that keep the negative from going vacuous are findings of this
review and both go stale silently if unrecorded: that an empty or misrouted
`$stderr` reds a positive above it rather than passing here, and that the
protection against wording drift is
`a tier moved off its pin aborts the commit`'s positive assertion over the same
fixture. A later edit to that test — or to the agent arm — is exactly the change
that would hollow this line out without failing anything, and nothing else in
the file says so.

## Restoration and cleanup

```
git diff --exit-code scripts/lib/resolve.sh   → clean
git hash-object scripts/lib/resolve.sh
320eca29c44c95bab495b08e19cb36d6f75eafda      # pre-review blob
git status --short
 M tests/commit_memory.bats
?? plans/index-edit-propagation/reports/item-1-2-s3-red.md
```

The throwaway probe test and the temporary assertion swap were both reverted
from `tests/commit_memory.bats`; its only diff against `HEAD` is slice 3's new
case plus this review's comment. The mutation backup under
`/tmp/claude/i12s3rev/` is deleted. `just precommit` not run, per the dispatch.
Nothing committed.
