# Item 1.2 slice 1 — code review

Verdict: **ships, with one comment added and one Major flagged for the
orchestrator rather than fixed.** The guard is correct, correctly placed, and
whitespace-safe; its two message arms and the forwarded problem lines are pinned
by the tests. What the mutation round found is not a defect in the six new lines
but a sentence *outside* them that this item has silently emptied of meaning —
and which slice 2 is scheduled to lock in with a test.

## Mutation table

`scripts/lib/resolve.sh` saved to `/tmp/claude/i12s1/resolve.sh.orig`, mutated
in place,
`scripts/run-bats.sh --jobs 1 tests/commit_memory.bats tests/git_hook_pre_commit.bats`
after each, restored before the next. Baseline: `bats: 34 passed, 0 failed`.
Final restore verified by blob id (`git hash-object` → `ee19c2d…`, matching the
pre-review index entry) before the one fix was applied.

| # | mutation | tests | verdict |
|---|---|---|---|
| 1 | guard moved **after** `compose_result=$(gitlore_compose "$mempath")` | 34 passed | green — and correctly so, see below |
| 2 | `>&2` dropped from the `gitlore_say_for_agent_or_user` call | `not ok 12` on the header fragment | red, as designed |
| 3 | two arms collapsed (agent text passed as both args) | 34 passed | green — known gap, slice 3's |
| 4a | `return 1` → `return 0` | `not ok 12`, `not ok 30`, both on `[ "$status" -ne 0 ]` | red |
| 4b | `return 1` deleted, control falls through into compose (the literal pre-Item-1.2 behaviour) | `not ok 12`, `not ok 30`, both on `[ "$status" -ne 0 ]` | red |
| 5 | `$pin_problems` dropped, header emitted alone | `not ok 12` on `is checked out at` | red on the forwarded fragment, as designed (also SC2034 from shellcheck) |
| 6 | `touch "$msgfile"` added to the new arm | 34 passed | green — accepted residual, unobservable |
| 7 | `if ! local pin_problems=$(…)` — the status folded into `local` | `not ok 12`, `not ok 30`, both on `[ "$status" -ne 0 ]` | red |
| 8 | guard hoisted above the whole `if [ "$dirty" = "1" ]` block | 34 passed | green — see the ordering note |

### Mutation 1 — the placement is unpinned because it is unobservable

`gitlore_compose` (`scripts/lib/index-compose.sh:806-812`) runs
`gitlore_compose_check` and `gitlore_compose_check_pins` **before** its first
write and returns 1 on either. So on an off-pin store the compose call writes
nothing, returns 1, and the pin guard then aborts with the same message — the
two placements are observationally identical, and no assertion on any surface
could separate them. This is not a coverage gap and no test should be added for
it. The runbook's placement is still the right one: it costs one fewer full
`gitlore_compose_check` pass and one fewer `check_pins` pass on the abort path,
and it keeps the abort's reason adjacent to the check that produced it.

I looked for a residual difference and found none: an off-pin store cannot reach
compose rc 2, because rc 1 is decided before any write.

### Mutation 3 — recorded as slice 3's gap, not fixed

The user arm ships unasserted at this slice, exactly as the dispatch
anticipated. Both arms are built from one `local pin_header`, so the header half
cannot drift; what is unpinned is the user remedy sentence
`Open this project in Claude Code and ask it to repair the memory store, then retry.`
Slice 3 owns it.

### Mutation 6 — accepted residual, confirmed

Reproduced the test review's finding from a run rather than taking it on trust:
adding `touch "$msgfile"` to the new arm leaves all 34 green. Sound, for the
reason the test's own comment now gives — reaching this arm means the freshness
gate above already read `yes`, so a restamp changes no later answer. The
runbook's "No restamp" is a rule about not copying a line whose reason does not
apply, and the code follows it; it is simply not a behaviour with an observable
of its own.

### Mutation 8 — the ordering against the freshness gate and the stale-merge loop

Hoisting the guard above the whole dirty block leaves all 34 green, so the
ordering is unpinned. It is nonetheless right where it is, on two grounds I
verified rather than assumed:

- **After the freshness gate.** A dirty store with an off-pin tier *and* no
  approved summary needs the summary regardless; the current order reports that
  first.
- **After the per-tier stale-merge loop.** This one is load-bearing. Hoisted
  above the loop, a mid-merge tier would be reported by `check_pins`' own
  mid-merge line instead of by `gitlore_guard_stale_merge_state`'s merge
  directive — the weaker of the two remedies. No test in either suite builds a
  mid-merge tier, so nothing catches a re-ordering.
  **Recorded for the orchestrator, not fixed**: adding that case is outside
  slice 1's listed scope.

## Answers to the specific questions

### The guard sits inside `if [ "$dirty" = "1" ]` — right, and here is why

**Correct.** A memory store with an off-pin tier cannot be clean as this
function measures cleanliness. Measured, not reasoned: a throwaway bats probe
(`tests/zz_probe.bats`, deleted; not in the tree) built the fixture, committed
everything so `gitlore_memory_dirty memory` read `0`, then made the tier's empty
commit and re-read it:

```
clean-before-move: dirty=0
after-move: dirty=1
status: [ M ddaanet]
```

`gitlore_memory_dirty` (`scripts/lib/util.sh:243`) is
`git -C "$mempath" status --porcelain`, and a submodule whose HEAD differs from
the index gitlink is reported ` M <tier>`. So the off-pin condition *is* a dirty
condition.

The clean path was checked for an adoption route anyway, in case a
`submodule.<name>.ignore` / `diff.ignoreSubmodules` setting ever hides the move
(gitlore sets neither —
`grep -rn 'ignoreSubmodules\|submodule\..*\.ignore' scripts/ tests/` is empty).
With `dirty = 0` the function does exactly one thing: `git push -q . HEAD:live`,
a local ref update. It calls neither `gitlore_sync_tiers_to_live` nor
`git -C "$mempath" add -A` — both are inside the dirty block. Nothing on that
path stages a gitlink.

Callers are the two documented ones and no others —
`scripts/git-hooks/pre-commit:68` (`|| exit $?`) and
`scripts/commit-memory.sh:66` (`set -euo pipefail`, bare call then `exit $?`).
Neither stages memory's own tier gitlinks; the pre-commit hook's
`GIT_INDEX_FILE="$saved_index" git add -- "$mempath"` stages the *parent's*
pointer to memory, a different gitlink.

Not a Critical. The guard is where it belongs.

### `gitlore_compose_check_pins`' mid-merge branch

**Unreachable from this call site, reachable from the other three, nothing to
delete, and the comment should stay silent about it.**

The loop immediately above iterates `gitlore_tier_paths` (every `.gitmodules`
path) and `return 1`s on any non-clean tier; `check_pins` iterates
`gitlore_active_tiers` (the manifest). Both skip an unmaterialized tier on
`[ -e "$path/.git" ]`. The predicates match: `check_pins`' mid-merge test is
"merge-state file **or** `MERGE_HEAD`", which is precisely the set of states
`gitlore_detect_stale_merge_state` calls anything other than `clean`.

Two bounds on "unreachable", both worth stating rather than glossing:

- A manifest entry that is materialized but absent from `.gitmodules` escapes
  the loop. It also escapes `check_pins`' mid-merge branch, because
  `git -C "$mempath" rev-parse -q --verify ":$tier"` finds no gitlink and
  `continue`s. A gitlink staged in memory's index with no `.gitmodules` record
  would reach the branch; that is a hand-built state, not one gitlore produces.
- `gitlore_guard_stale_merge_state` does not always `return 1` on a non-clean
  tier: `stale-no-merge-head` delegates to
  `gitlore_recover_stale_no_merge_head`, which can repair and return 0. In every
  such case the repair has already run `gitlore_drop_merge_preparation` and
  `MERGE_HEAD` is absent by definition, so the tier is `clean` by the time
  `check_pins` looks. (That path has a consequence of its own — see Minor 1.)

Still reachable from `session-start.sh:326` (which uses
`gitlore_detect_stale_merge_state` per tier to *skip* a re-detach, not to
refuse), and from `scripts/cc-hooks/index-compose.sh` and `add-tier-batch.sh`,
neither of which guards stale merge state at all.
`grep -rn 'guard_stale_merge_state' scripts/cc-hooks/` returns nothing.

On documenting it in the new comment: no. The comment's job is why the check
sits at this call site; a note that one of the callee's branches happens to be
shadowed here would be a claim about `gitlore_compose_check_pins` made from the
wrong place, and it would rot the moment the loop above changes.

### Exit-status capture — load-bearing, and now documented

`local pin_problems` on its own line followed by
`if ! pin_problems=$(gitlore_compose_check_pins "$mempath")` does propagate the
function's status. Mutation 7 proves the fold is fatal: with
`if ! local pin_problems=$(…)`, `local`'s own status (0) is read, the refusal is
swallowed, and both cases red on `[ "$status" -ne 0 ]`.

The tests do catch a regression here, so it cannot ship silently — but the
reason is invisible in the source, and the fold is exactly the kind of tidy-up a
later reader makes. The nearest neighbour (`local compose_result compose_rc=0`
then `compose_result=$(…) || compose_rc=$?`) has the same split without a
comment, but there the split is *forced* by the `|| compose_rc=$?` and
self-documents. Here it is not. **Fix applied** — two lines above the
declaration:

```
    # The declaration stays on its own line: folded into `local pin_problems=$(…)`
    # the status read is `local`'s, always 0, and the refusal is swallowed.
```

### Whitespace and errexit

**Whitespace: safe, measured against a spaced input rather than read.** A probe
mounted a tier at `sha red tier` (two spaces in the path), moved it off its pin
and drove `commit-memory.sh`:

```
rc=1
gitlore: a tier was moved off the commit the memory store records for it, so the commit was aborted rather than adopt the move:
tier 'sha red tier' is checked out at 4f204647e6b0 but the memory store records c8d01117ee3a: … Return it to the pin with `git -C "/tmp/…/memory/sha red tier" checkout --detach c8d01117ee3a…`, …
gitlore: composing would have overwritten what that tier holds, …
pin-after == pin-before
```

One problem line, the tier name intact, the printed command quoted and
paste-runnable, the pin unmoved. The new block has no whitespace surface of its
own — it passes `"$mempath"` and interpolates `"$pin_problems"` quoted — and the
producers upstream are already NUL-delimited (`gitlore_tier_paths` uses
`git config -z --get-regexp` with `read -r -d ''`).

**errexit: holds under both settings**, and the two entry points differ, which
is worth being explicit about. Under `commit-memory.sh` the function is called
bare under `set -euo pipefail`, so errexit is **on** inside it; under the
pre-commit hook it is called `|| exit $?`, so errexit is **off**. Neither breaks
the new code: the command substitution sits in an `if !` condition, where
errexit is suspended for it and everything it calls, and `local`, the
`pin_header` assignment and `gitlore_say_for_agent_or_user` all return 0. Both
entry points are exercised green by the two slice cases, so this is covered by a
run and not only by reading.

**A `check_pins` that fails for a non-pin reason:** it returns only an explicit
0 or an explicit 1, and every internal failure is absorbed by `|| continue`
(`rev-parse -q --verify`) or by `[ -e … ] || continue`. `$problems` is only ever
appended to with non-empty literals, so a non-zero return with empty output is
not producible; were it ever produced, the message would carry the header, a
blank line and the remedy — degraded but not silent.

The inherited **fail-open** is worth naming: a `rev-parse` that errors for a
real reason (a corrupt index, a missing gitlink) is `continue`d, so a broken
store is read as having no pin problems and the commit proceeds. That is
`gitlore_compose_check_pins`' pre-existing contract — the same one
`gitlore_compose` has always had — and this guard inherits it rather than
introducing it. Out of scope; noted so it is not rediscovered as new.

### Failure reporting — who learns about each path

| path | agent | user |
|---|---|---|
| `check_pins` returns 1 with problem lines | stderr, agent arm (`CLAUDECODE=1` in an agent's Bash) — carries the verbatim `git -C "<abs>" checkout --detach <sha>` | stderr, user arm, via git's hook output |
| the abort itself (rc 1) | `pre-commit`: `\|\| exit $?` → the commit fails visibly. `commit-memory.sh`: `set -e` plus `exit $?` → non-zero exit | same |
| `check_pins` returns non-zero with empty output | header + blank line + remedy on stderr — degraded, not silent; not producible today | same |
| `gitlore_say_for_agent_or_user` itself fails (closed stderr) | message lost, `return 1` still fires, commit still aborts | same |

No silent-to-everyone path. Nothing to fix.

### Citation boundary — clean

The new comment cites `D31`, `D36`, `gitlore_compose`, `add -A`, `$msgfile`. No
`plans/`, no `memory/`, no runbook or slice identifier, no line number. Checked
`D31`/`D36` against their source rather than assuming:
`docs/references/ index-composition.md:66,99` and
`docs/changelog/ 2026-08-26-compose-refuses-a-tier-off-its-pin.md` — "the down
projection refuses a tier that was moved off its pin (FR15, D31, D36)". The
right pair.

The comment I added cites nothing.

Adjacent, **pre-existing and not mine to change**: the rc-1 arm's comment eight
lines below carries `(index-compose.sh:787)`, a line number in shipped source.
It landed with Item 1.1 and is committed. Flagging only.

### Comment accuracy — every claim checked against code

- *"A tier off its pin refuses composition itself (D31, D36)"* — true.
  `gitlore_compose:811` calls `gitlore_compose_check_pins` and returns 1.
- *"leaving that refusal to `gitlore_compose`'s own rc-1 arm would let this
  function's `add -A` below stage the moved gitlink anyway"* — true. The rc-1
  arm falls through to `gitlore_sync_tiers_to_live` and then
  `gitlore_git -C "$mempath" add -A`, which stages a submodule whose HEAD moved.
- *"adopting the move silently in the very commit that reported it as a
  problem"* — true, and it is exactly what mutation 4b restores.
- *"Checked here, ahead of compose, so an off-pin tier aborts instead"* — true.
- *"No restamp: this writes nothing"* — true. `gitlore_compose_check_pins` runs
  only `rev-parse`, a subshell `cd … && pwd`, `printf` and `grep`.
- *"so the tree is no newer than `$msgfile` and the approval survives for the
  retry"* — true, and asserted (`gitlore_commit_msg_freshness memory` = `yes`).

## Findings

### Major 1 — the rc-1 agent remedy now ends in a clause nothing can satisfy

**Flagged, not fixed: design-level and slice 2's arm.**

The rc-1 arm's agent remedy ends:

> This commit also stages each tier at the commit its worktree is on now, so a
> pin figure printed above is the one from before it.

That clause exists to warn that a pin SHA in the refusal text is stale by the
time the commit lands. After this item, no pin SHA can appear there. The pin
guard aborts before `gitlore_compose` runs, so the rc-1 arm is now reachable
only via a `gitlore_compose_check` refusal — whose four rules (manifest lists an
unmounted tier; the two index checks; a root bullet prefix naming no mounted
tier) print no SHA at all.

Measured, not inferred. Driving `commit-memory.sh` with `CLAUDECODE=1` on the
`set_tier_manifest ddaanet phantom` induction the re-homed test uses:

```
rc=0
gitlore: tier composition refused — the memory indexes were left untouched:
the tier manifest lists 'phantom', which is not mounted in memory/.gitmodules
gitlore: the commit went ahead with the memory indexes as they stand. Fix the problems above by hand — composition runs again at the next memory commit. This commit also stages each tier at the commit its worktree is on now, so a pin figure printed above is the one from before it.
```

No pin figure above it, and none is now possible.

Why it matters beyond tidiness: the test review already recorded that this
sentence lost its only assertion when
`an off-pin compose refusal is reported and does not abort the commit` was
replaced, and that **slice 2 is expected to re-pin it**. Re-pinning it would
lock a sentence whose second half describes a state the code can no longer
produce — the assertion would pass forever while asserting nothing about
behaviour, which is the shape the recall artifact's `green-is-not-evidence`
entry warns about.

I did not touch it. The message texts were fixed at plan time, the arm belongs
to slice 2's case, and the choice — drop the trailing clause, or keep the whole
sentence and have slice 2 assert only the first half — is the orchestrator's.
The first half
(`This commit also stages each tier at the commit its worktree is on now`)
remains true and is worth keeping either way.

### Minor 1 — an interrupted `/gitlore:merge` continuation now blocks the commit, with a remedy that would undo the repair

`gitlore_guard_stale_merge_state` on a tier can *repair* rather than refuse:
`stale-no-merge-head` → `gitlore_recover_stale_no_merge_head` →
`gitlore_recover_landed_merge`, which returns 0 after either clearing the
leftover state (HEAD already carries the merge) or checking HEAD back onto the
landed merge. Neither branch stages the moved gitlink in memory's index — the
staging that the normal continuation does at `scripts/resolve.sh:227`
(`gitlore_git -C "$memroot" add -- "$merged_tier"`, D43).

So the loop can hand the new guard a tier that is off its pin
*because gitlore just repaired it*. The commit then aborts, and the remedy says
the tier "was moved outside /gitlore:merge" and offers
`checkout --detach <pinned>` — which would move HEAD off a landed, approved
merge.

Bounded, and why I left it:

- Reachability is narrow: a `/gitlore:merge` continuation interrupted between
  its merge commit and its staging, in a tier.
- Nothing is destroyed. The merge commit stays reachable, and the
  *same sentence* offers the correct alternative —
  `or run /gitlore:merge to take its content properly`.
- The user is not left silent: `gitlore_recover_landed_merge`'s own message
  prints immediately before the abort.
- The fix is not in the six lines under review. It is either "the recovery path
  should stage the gitlink it moved" or "the runbook's accepted cost covers this
  too" — both design calls, and the runbook explicitly accepted a blocking
  refusal as the trade.

### Accepted residual — `touch "$msgfile"` in the new arm is unobservable

Reconfirmed by mutation 6 rather than carried over from the test review. Not a
defect: the code is correct (no restamp), the test's comment states what it can
and cannot see, and no fixture can manufacture the distinction — reaching this
arm implies the freshness gate already read `yes`.

### Known gap for slice 3 — the user arm

Mutation 3 ships green. Recorded, not fixed.

### Recorded for the orchestrator — no mid-merge tier fixture in either suite

Mutation 8's green means nothing pins the guard's position *after* the per-tier
stale-merge loop. A case with a mid-merge tier and dirty memory, asserting the
merge directive rather than `check_pins`' mid-merge line, would pin it. Outside
slice 1's listed scope.

## Fix applied

One, to `scripts/lib/resolve.sh`:

```
    # The declaration stays on its own line: folded into `local pin_problems=$(…)`
    # the status read is `local`'s, always 0, and the refusal is swallowed.
```

Two comment lines above `local pin_problems`. Rationale under "Exit-status
capture" above: the separation is load-bearing (mutation 7), the neighbouring
split self-documents through its `|| compose_rc=$?` while this one does not, and
the fold is a plausible later tidy-up.

No other change. `scripts/lib/index-compose.sh` untouched
(`git diff --exit-code scripts/lib/index-compose.sh` clean); the two test files
carry exactly the diff they had on arrival (`65` and `28` changed lines,
unchanged from the pre-review `git diff --stat`).

## Verification after the fix

- `shellcheck -s bash scripts/lib/resolve.sh` — exit 0, no findings.
- `scripts/run-bats.sh --jobs 1 tests/commit_memory.bats tests/git_hook_pre_commit.bats`
  → `bats: 34 passed, 0 failed`.
- `scripts/run-bats.sh --jobs 1 tests/tier_divergence.bats tests/tier_lockstep.bats tests/index_compose.bats tests/index_sync.bats`
  → `bats: 180 passed, 0 failed`.
- Restoration proved: `git diff scripts/lib/resolve.sh` shows the slice's guard
  plus the two comment lines and nothing else; the scratch probe file is deleted
  and `git status --short` lists no untracked test.
- `just precommit` not run, per the dispatch. Nothing committed.
