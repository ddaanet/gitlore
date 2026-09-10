# Item 1.3 slice 2 — code review

Your call is right and is implemented. The `merge-base` guard, the branch order
and the whitespace handling all hold up under measurement. Two findings you did
not anticipate, both measured, one of which needs a scope decision from you
before the slice commits.

## Verdict on the call you handed me

**Agreed, implemented.** The wrapper now names no remedy of its own. Every
branch of `gitlore_compose_check_pins` already prints the one its cause takes,
so a cause-independent pointer is true for all of them, correct for a multi-tier
abort with mixed causes, and has no dead pointer for an ahead tier. I found no
reason to prefer keeping the sentence and adding an ahead-specific one — that
really would be a second cause analysis in the wrapper.

Your four pushback prompts, answered:

- **Agent arm too vague?** No. `$pin_problems` is embedded verbatim in
  `$pin_header`, on the lines immediately above the sentence, and each of those
  lines names a concrete remedy. The pointer resolves for the agent by reading
  one line up.
- **User arm.** Leave it. "Open this project in Claude Code and ask it to repair
  the memory store" is correct for all four causes, and specifically for ahead:
  the ahead line's own remedy is "inspect and stage the gitlink by hand", which
  is exactly what an agent asked to repair the store would do. It is also not a
  dead pointer, because it names an actor rather than a command.
- **Header.** "a tier was moved off the commit the memory store records for it"
  reads correctly for an ahead tier. Moving forward off the pin is still moving
  off it, and the word that would have been wrong — "reverted", "lost" — is not
  there. No change.
- **Does repointing the assertion lose coverage?** Yes, and more than you
  expected. See finding 1.

## Finding 1 — the wrapper's remedy sentence is now unpinned (measured)

Repointing `tests/commit_memory.bats:220` onto the problem line leaves
`gitlore_sync_memory_to_live`'s agent-arm remedy sentence with
**zero coverage**. Measured: I deleted the sentence outright from `resolve.sh`
and ran the five-file set — **134 passed, 0 failed**. Before this slice that
mutation would have red at line 220.

The reason the repointed assertion buys nothing back is that the property it now
asserts is already pinned twice, on the producer, in `tests/index_compose.bats`:

- `tests/index_compose.bats:322` (orphan/sideways) —
  `[[ "$output" == *"git -C \"$abs\" checkout --detach $pinned"* ]]`
- `tests/index_compose.bats:357` (diverged) — the same assertion

So `commit_memory.bats` spent its one wrapper-facing assertion on a property
`index_compose.bats` already owns, and gave up the only assertion in the suite
that looks at the wrapper's remedy prose.

I implemented your instruction as written — it is unambiguous, and the
non-negotiable you attached to it is met (measured below). But if you want the
wrapper's own sentence pinned, the one-line alternative is to point line 220 at
the wrapper instead:

```bash
  [[ "$stderr" == *"Follow the remedy on each line above, then retry the commit"* ]]
```

That is still one assertion in the same place, and "the sideways case still
offers a runnable return-to-the-pin command" stays red-able through
`index_compose.bats:322`/`:357`. Your call; I did not take it unilaterally,
because you named the sideways-command property as the thing that must not
weaken and this variant moves it to a different file.

## Finding 2 — a stranded assertion outside my scope

`tests/commit_memory.bats:523`, in "the pin-abort user arm tells a user to
retry" (Item 1.2/3, already committed, not in this slice's diff):

```bash
  [[ "$stderr" != *"Return the tier to its pin"* ]]
```

After this slice no producer in the tree emits that string —
`grep -rn "Return the tier to its pin" scripts/ hooks/ commands/ skills/ agents/`
returns nothing. The assertion can no longer fail. Its own comment (`:515-521`)
says so explicitly and is now wrong on two counts:

> a wording drift in the agent remedy reds
> `a tier moved off its pin aborts the commit`, which asserts
> `Return the tier to its pin with the command above` positively over this same
> fixture

The named test no longer exists (RED renamed it to "a tier moved **sideways**
off its pin aborts the commit"), it is no longer "this same fixture" (that test
now uses an orphan commit; this one uses `commit --allow-empty`, i.e. the
**ahead** fixture, so after slice 2 it exercises the ahead branch), and the
positive it pairs with is gone.

Arm discrimination itself survives — the positive at `:511`
(`ask it to repair the memory store, then retry.`) still carries it — so this is
a dead assertion and a false comment, not a hole. The fix, which I did not apply
because it is a second `tests/` edit and outside the one you authorized:

```bash
  # The agent arm's remedy sentence, refuted here: the user arm sends the
  # reader to Claude Code rather than reciting the per-cause remedies, and
  # `the pin-abort's ahead wording reaches both arms` asserts it positively
  # over the agent arm on this same fixture.
  [[ "$stderr" != *"the approved summary is still in place"* ]]
```

That string is agent-arm-only and lives in the sentence this slice rewrote, so
it goes red on drift. Under Finding 1's alternative it is paired with a positive
at line 220; under your version it is unpaired but at least live.

## Also check — results

### 1. The `rev-parse -q --verify "${pinned}^{commit}"` guard — confirmed

GREEN's reasoning holds, and I confirmed each leg empirically rather than by
reading.

- **Silent on the miss.** `git rev-parse -q --verify <absent-sha>^{commit}`
  returns 1 with **no output on stdout or stderr**. Verified in a scratch repo,
  and end to end: I repointed a memory store's gitlink at a commit from an
  unrelated repository (`update-index --cacheinfo 160000,…`) and ran
  `gitlore_compose_check_pins` with stderr tagged through `sed`. Nothing reached
  stderr; the tier fell through to the sideways branch, which is the pre-slice
  behaviour for an unknown pin. Without the guard, `merge-base --is-ancestor`
  prints `fatal: Not a valid commit name <sha>` and returns 128.
- **The ancestry argument.** A pin genuinely ancestral to a checked-out HEAD is
  necessarily an object in that repository, so the guard can only reject a tier
  that was never ahead. No coverage cost. The one theoretical exception is a
  shallow tier clone, where ancestors past the graft point are absent — but
  `grep -rn -- "--depth\|shallow" scripts/ hooks/` finds nothing, gitlore never
  clones a tier shallow, and in that hypothetical `merge-base --is-ancestor`
  would answer wrongly too, so the guard is not the weak link.
- **Pin exists but is not a commit.** `-q` does **not** cover this: git prints
  `error: <sha>^{commit}: expected commit type, but the object dereferences to blob type`
  and returns 1. I reproduced it by forcing a blob into memory's index at the
  tier path. This is correct behaviour, not a defect: the state is genuinely
  broken (memory's index holding a non-gitlink at a path that is a materialized
  submodule — no gitlore path produces it, and `[ -e "$tierpath/.git" ]`
  upstream makes it near-unreachable), and `no-stderr-suppression` wants git's
  real message surfaced on an unanticipated state rather than swallowed.
  Suppressing it would be the violation. No change.
- **Ordering.** Guard, then the test — the rule's first preference, and the
  file's own idiom two lines above
  (`pinned=$(git … rev-parse -q --verify ":$tier") || continue`). No
  `2>/dev/null` anywhere in the slice. Confirmed, not assumed.

### 2. Branch order — pinned (measured)

Mutation: swapped the mid-merge block and the ahead block in
`gitlore_compose_check_pins`, ran
`tests/index_compose.bats tests/commit_memory.bats`.

```
not ok 27 a moved tier holding MERGE_HEAD is sent to /gitlore:resolve instead
  (line 428) `[[ "$output" == *"tier 'ddaanet' is mid-merge"* ]]' failed
not ok 28 a moved tier with a merge state file and no MERGE_HEAD is mid-merge too
  (line 450) `[[ "$output" == *"tier 'ddaanet' is mid-merge"* ]]' failed

bats: 83 passed, 2 failed
```

Both mid-merge predicates are covered, and both fixtures assert their own
ahead-ness first, so the pin cannot go vacuous by a helper drifting. Order
restored; file sha verified identical to the pre-mutation copy.

Worth noting: a plain `git diff --stat` does **not** detect this mutation — a
pure block swap renders as the same 19 insertions, 0 deletions. Only the sha
comparison proved the restore.

### 3. Whitespace safety — clean (measured)

The slice parses nothing and splits nothing: `"$tierpath"`,
`"${pinned}^{commit}"`, `"$pinned"`, `"$head"` are all quoted, and the loop is
`while IFS= read -r tier`.

Run against a spaced input rather than judged by reading — a memory store at
`/tmp/claude/rev132/ws probe/mem store` with a tier named `my tier`, ahead of
its pin:

```
rc=1
tier 'my tier' is checked out at 16669e392054, ahead of the pin the memory store
records at 0042805e7859: …
```

Correct branch, correct tier name, no stray output, no fatal.

### 4. Citation boundary — fixed

`resolve.sh`'s comment cited `(Item 1.3)`, `tests/commit_memory.bats:220` and
"see the GREEN report". All three are gone; the reasoning they carried (why
`/gitlore:merge` is wrong here, why the wrapper cannot choose per-tier wording)
is kept in the rewritten comment. `index-compose.sh`'s new comment had no
`plans/`, `memory/`, runbook or line-number citation to strip.

Verified across both files:
`grep -nE "plans/|memory/[a-z]|Item [0-9]|slice|GREEN|\.bats:[0-9]|runbook"`
returns only the pre-existing `# Tier index composition (D17 slice 3-ii)` header
line, which is a decision id, the file's established convention.

### 5. Comments — tightened, nothing stale

- `resolve.sh`: rewritten. The old block's second paragraph documented a
  residual defect that the change removes, so leaving it would have described
  behaviour the code no longer has. 21 lines to 11.
- `index-compose.sh`: kept the argument, cut a four-line sentence with a nested
  parenthetical down to two clauses; 13 lines to 11, in line with the
  surrounding branches. The guard rationale now states the coverage claim
  positively ("what the guard rejects was never ahead") rather than by double
  negative.

## Observation, no change made

The ahead branch says "inspect and stage the gitlink by hand" without printing
`git -C "<abs>" add -- "<tier>"`, while the sideways branch prints its command
in full. That asymmetry is your explicit instruction to GREEN (naming the cost
is not the same as printing the command) and nothing in the suite forbids
printing the `add`. Flagging it only because the shared convention on
verbatim-runnable commands cuts the other way; not a defect as specified.

## Final user-facing text

The ahead branch's report line (`scripts/lib/index-compose.sh`,
`gitlore_compose_check_pins`):

> tier '<tier>' is checked out at <head12>, ahead of the pin the memory store
> records at <pin12>: it advanced without composing, and projecting the root
> index onto it would overwrite what it holds. There is no automatic remedy:
> inspect and stage the gitlink by hand, or return the tier to the pin, which
> discards the commits it carries ahead of it.

The wrapper's agent arm (`scripts/lib/resolve.sh`,
`gitlore_sync_memory_to_live`), after `$pin_header`:

> gitlore: composing would have overwritten what that tier holds, and committing
> would have adopted the move silently. Follow the remedy on each line above,
> then retry the commit — the approved summary is still in place.

The wrapper's user arm, unchanged:

> gitlore: composing would have overwritten what that tier holds. Open this
> project in Claude Code and ask it to repair the memory store, then retry.

Both arms are preceded by `$pin_header`:

> gitlore: a tier was moved off the commit the memory store records for it, so
> the commit was aborted rather than adopt the move:
> <the problem lines, verbatim>

## The one test edit

`tests/commit_memory.bats`, in "a tier moved sideways off its pin aborts the
commit". One assertion replaced, with four lines of comment:

```bash
-  [[ "$stderr" == *"Return the tier to its pin with the command above"* ]]
+  # The remedy is read off the problem line rather than the wrapper's prose:
+  # the wrapper names no remedy of its own, because $pin_problems can carry
+  # tiers with different causes in one abort. Verbatim-runnable — absolute
+  # path, full sha — so a drift into a bare `checkout --detach` still reds.
+  [[ "$stderr" == *"git -C \"$(cd memory/ddaanet && pwd)\" checkout --detach $pin_before"* ]]
```

**Not weakened — measured.** I replaced the sideways branch's printed command
with a bare "Return it to the pin by hand" and ran `tests/commit_memory.bats`:

```
not ok 12 a tier moved sideways off its pin aborts the commit
  (line 224) `[[ "$stderr" == *"git -C \"$(cd memory/ddaanet && pwd)\" checkout --detach $pin_before"* ]]' failed

bats: 19 passed, 1 failed
```

It is strictly stronger than the assertion it replaced on that property: the old
one accepted any wording change to the command, this one pins the absolute path
and the full sha.

## Suites

`scripts/run-bats.sh --jobs 1 tests/index_compose.bats tests/commit_memory.bats tests/resolve.bats tests/resolve_recovery.bats tests/tier_divergence.bats`

| world | result |
| --- | --- |
| `CLAUDECODE=1` | 134 passed, 0 failed |
| `env -u CLAUDECODE` | 134 passed, 0 failed |
| `env CLAUDECODE=0` | 134 passed, 0 failed |

Baseline before my edits was also 134/0, so no test changed its verdict — the
changes are wording and comments plus one repointed assertion, all measured
individually by mutation above.

`shellcheck scripts/lib/index-compose.sh scripts/lib/resolve.sh tests/commit_memory.bats`
— clean, no output.

I did not run `just precommit`.

## Tree state

```
 M scripts/lib/index-compose.sh
 M scripts/lib/resolve.sh
 M tests/commit_memory.bats
 M tests/index_compose.bats
?? plans/index-edit-propagation/reports/item-1-3-s2-code-review.md
?? plans/index-edit-propagation/reports/item-1-3-s2-green.md
?? plans/index-edit-propagation/reports/item-1-3-s2-red.md
?? plans/index-edit-propagation/reports/item-1-3-s2-test-review.md
```

`git diff --cached --name-only` is empty. `git log --oneline -1` is
`a0b416b 📝 measure where an orchestrate session's context goes` — unmoved.
Nothing staged, nothing committed.

`git diff --stat tests/` shows `tests/index_compose.bats | 156`, byte-identical
to the test-review's tree state — I did not touch it. `tests/commit_memory.bats`
grew by the four comment lines above and nothing else; its diff against the
test-review's state is the one repointed assertion.

Every mutation was applied in place and restored, each restore verified by sha
against a pre-mutation copy. Scratch fixtures under `/tmp/claude/rev132` are
removed. Nothing is left mutated.
