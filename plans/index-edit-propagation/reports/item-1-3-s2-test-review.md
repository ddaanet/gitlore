# Item 1.3 slice 2 — test review

Verdict: **fixed, still red for the right reasons.** Every point the dispatch
raised was a real defect; all are repaired in the test files. Two findings are
handed back rather than fixed, one of them a defect in `scripts/lib/resolve.sh`
that slice 2's GREEN will expose.

**Read the incident section at the end first**: a probe I ran left this
repository's `HEAD` on an unborn orphan branch for a few minutes. It is repaired
and no commit was lost, but the team lead is committing from this tree and
should know it happened.

## The mechanical check

Run, not read.
`scripts/run-bats.sh --jobs 1 tests/index_compose.bats tests/commit_memory.bats`,
incoming state:

```
not ok 25 a tier ahead of its pin is refused with ahead-of-the-pin wording, not the return-to-pin remedy
# (in test file tests/index_compose.bats, line 324)
#   `[[ "$output" == *"ahead of"* ]]' failed
not ok 77 the pin-abort's ahead wording reaches both the agent arm and the user arm
# (in test file tests/commit_memory.bats, line 244)
#   `[[ "$stderr" == *"ahead of"* ]]' failed

bats: 82 passed, 2 failed
```

Both FAILED on an assertion; neither PASSED, neither ERRORed, and no test
aborted on a missing fixture or helper. bats runs each body under `set -e` and
reports the first command that returns non-zero, so the reported line being the
first *new* assertion is itself the evidence that every assertion above it —
`[ "$status" -eq 1 ]` / `-ne 0`, and the `"tier 'ddaanet'"` substring — already
passed against unchanged code. The RED report's account of the mechanical state
is accurate.

## What was wrong, and what changed

### 1. The sideways fixture was the extreme case only, and it hid a real one

`merge-base --is-ancestor` behaves identically for an unrelated root and for a
genuine divergence — measured, not assumed (git 2.47.3):

| head shape | `merge-base --is-ancestor pinned head` | `merge-base pinned head` |
| --- | --- | --- |
| descendant of the pin (ahead) | rc 0 | rc 0 |
| sibling of the pin (diverged) | rc 1, silent | rc 0, prints the base |
| unrelated root (orphan) | rc 1, silent | **rc 1** |

So the orphan hides nothing *about the specced predicate*, and nothing else in
the compose path reads differently under it — `${head:0:12}` is a parameter
expansion over a sha, `gitlore_active_tiers` reads the manifest, and the
mid-merge predicate reads a state file and `MERGE_HEAD`. The orphan is a valid
sideways fixture.

It is not a sufficient one. The two shapes come apart under
`merge-base "$pinned" "$head"` — the natural wrong reading of "the tier has gone
somewhere else", *does it share history at all* — and an implementation that
branched on that would call a diverged tier ahead, offer it the wrong remedy,
and leave the orphan test green. The diverged shape is also the one the guard
actually meets: a hand-run `reset --hard origin/live` after the remote's history
was rewritten.

Added, per the dispatch's "add the second, not swap it":

- `move_tier_diverged_off_pin` (`tests/index_compose.bats:259`). A root commit
  has no sibling and `pinned_store_with_tier` leaves the tier on its root
  commit, so the helper advances the tier once and re-pins there
  (`git -C memory add -- "$tier"`, the D43 gitlink move), which gives the pin a
  parent, then commits a second child of that parent.
- `@test "compose refuses a tier diverged from its pin with the same return-to-pin remedy"`
  (`tests/index_compose.bats:339`). Born-green, red under mutation A below.

Both sideways tests now assert their own fixture's shape
(`run ! git … merge-base …`) rather than trusting the helper's name, so a later
repoint of a helper cannot make them vacuous in silence.

### 2. The assertion substrings

`"ahead of"` was weak in the way the dispatch said — satisfiable anywhere in the
report, by a sentence saying the opposite. `"no automatic adoption"` dictated
GREEN's sentence, which slice 2's spec explicitly leaves open.

`tests/index_compose.bats:369` now reads:

```bash
tierline=$(printf '%s\n' "$output" | grep -F "tier 'ddaanet'")
[[ "$tierline" == *"${moved:0:12}"* ]]
[[ "$tierline" == *"${pinned:0:12}"* ]]
[[ "$tierline" == *"ahead"* ]]
[[ "$tierline" == *"discard"* ]]
[[ "$output" != *"checkout --detach"* ]]
[[ "$output" != *"/gitlore:merge"* ]]
```

- Extracting the tier's own report line first is what stops any positive from
  being satisfied by a different line — including, in the commit-path test, the
  wrapper's own remedy prose. `grep -F` failing is itself an assertion under
  `set -e`.
- **Both truncated shas** replace the weak framing with content: which commit
  the tier is on and which one the store records. "Inspect and stage the gitlink
  by hand" is not a runnable remedy without them, and the sideways message
  already prints both, so this asks GREEN for nothing new in kind.
- **`"ahead"`** stays, but tied to that line, where it cannot belong to another
  sentence.
- **`"no automatic adoption"` is gone**, replaced by the behaviour it names, as
  two negatives. `checkout --detach` was already asserted absent;
  `/gitlore:merge` is new and is the sideways message's *other* half — the
  item's own finding is that for a tier ahead of its pin the remote is already
  contained in HEAD and the take reports nothing to take, so offering it sends
  the user in a circle. A negative cannot be satisfied by accident, and neither
  of these prescribes a word GREEN must type.
- **`"discard"` is kept**, and it is the one residual wording constraint. The
  meaning — returning to the pin costs the commits the tier carries — needs some
  word, the runbook fixes this one for the branch, and a synonym would read
  identically to a user. Flagged rather than hidden: if GREEN prefers "lose" or
  "destroy", this line is the one to change, not to work around.

`tests/commit_memory.bats:249` gets the same treatment minus the shas — that
test's job is that the wording *crosses the wrapper into both arms*, not to
re-pin the message's content. It does **not** get the `/gitlore:merge` negative;
see finding A below.

The set is satisfiable, which matters as much as its being red: under mutation A
(a plausible GREEN message) both ahead tests pass. I have not written an
assertion GREEN cannot meet.

### 3. "The abort writes nothing", so the fixture is reusable — verified

Confirmed against the code and then pinned in the test rather than left as a
comment. `gitlore_sync_memory_to_live` (`scripts/lib/resolve.sh:1001`) runs
`gitlore_compose_check_pins` after the stale-merge guards and before
`gitlore_compose` and `gitlore_sync_tiers_to_live`, and returns 1 without a
write. The guards write only on a stale merge state, which this fixture has none
of. `scripts/commit-memory.sh:64` rewrites the commit-msg file at the top of
*every* run, so the second run re-satisfies the freshness gate by construction
rather than by inheriting the first run's stamp; and the file lives in the
*superproject's* `.claude/` (`_gitlore_ipc_dir`, `scripts/lib/util.sh:116`), so
it is not even inside the trees the test snapshots.

The test now snapshots the pin, the tier HEAD, and both `status --porcelain`
outputs before the first run and re-asserts them between the two runs. A first
run that had staged the gitlink, left merge state or moved HEAD now fails there
instead of silently changing what the second run means.

One further hole in the original: nothing proved the second run was the *other*
arm. `CLAUDECODE=1 run …` does not leak in bash 5.2 (measured), and the explicit
`unset` covers the ambient case, but the test could still have passed with the
agent arm answering twice. It now reads the user arm's own sentence
(`"Open this project in Claude Code"`) positively, and asserts the two extracted
tier lines are byte-identical — which is the actual claim, that `$pin_problems`
crosses into both arms verbatim.

### 4. Branch order — pinned by assertion, and now proven

The suite does pin the ordering, and not by accident: `move_tier_off_pin` leaves
the tier ahead, so once the ahead branch exists both mid-merge tests satisfy
both predicates and only the order decides which answers; their
`"tier 'ddaanet' is mid-merge"` assertion fails if the ahead branch runs first.
No separate ordering test is owed.

What was missing is the proof and the load-bearing fact. Both tests now assert
their fixture *is* ahead
(`git -C memory/ddaanet merge-base --is-ancestor "$pinned" HEAD`) — otherwise a
later repoint of `move_tier_off_pin` turns the ordering pin vacuous with nothing
failing — and both gain `[[ "$output" != *"ahead"* ]]`. Mutation B below is the
proof the RED report did not have.

### 5. Names

- `tests/index_compose.bats` — "compose refuses a moved tier and names the
  commands that return it" → **"compose refuses a tier moved sideways onto
  unrelated history and names the commands that return it"**. The old name
  described a fixture the test no longer uses and now collides with its diverged
  sibling.
- `tests/commit_memory.bats` — "a tier moved off its pin aborts the commit" →
  **"a tier moved sideways off its pin aborts the commit"**. The file now holds
  two pin-abort tests and this one is the sideways arm.
- The two new ahead tests' names already describe what they assert; unchanged.

## Mutation proofs, re-run here

Both applied to `scripts/lib/index-compose.sh` and reverted; the file carries no
diff (`git diff --name-only scripts/` empty).

**Mutation A — the ahead branch with the `merge-base --is-ancestor` test
omitted**, so it fires for every off-pin tier. This is the RED report's own
mutation, re-run rather than taken on trust. All three born-green sideways pins
go red, and both ahead tests go green:

```
not ok 24 compose refuses a tier moved sideways onto unrelated history …
#   `[[ "$output" == *"the memory store records ${pinned:0:12}"* ]]' failed
not ok 25 compose refuses a tier diverged from its pin with the same return-to-pin remedy
#   `[[ "$output" == *"the memory store records ${pinned:0:12}"* ]]' failed
not ok 77 a tier moved sideways off its pin aborts the commit
#   `[[ "$stderr" != *"ahead"* ]]' failed

bats: 82 passed, 3 failed
```

**Mutation B — the correct ahead branch placed BEFORE the mid-merge test.** The
proof the branch-order guarantee is pinned. Exactly the two mid-merge tests go
red, and nothing else moves:

```
not ok 27 a moved tier holding MERGE_HEAD is sent to /gitlore:resolve instead
#   `[[ "$output" == *"tier 'ddaanet' is mid-merge"* ]]' failed
not ok 28 a moved tier with a merge state file and no MERGE_HEAD is mid-merge too
#   `[[ "$output" == *"tier 'ddaanet' is mid-merge"* ]]' failed

bats: 83 passed, 2 failed
```

## Handed back, not fixed

### A. `gitlore_sync_memory_to_live`'s abort remedy goes stale for an ahead tier

`scripts/lib/resolve.sh:1005-1009` wraps `$pin_problems` in a fixed remedy
sentence whose agent arm reads:

> Return the tier to its pin with the command above, or run /gitlore:merge to
> take its content properly, then retry the commit …

Once slice 2 lands, an ahead tier's report line names **no** return-to-the-pin
command, so "the command above" points at nothing; and `/gitlore:merge` is the
take this very item establishes reports nothing to take for such a tier. The
commit path therefore ends by offering an ahead tier two remedies, one of which
does not exist and one of which does nothing.

Not fixed here, and not asserted: fixing it means editing
`scripts/lib/resolve.sh`, which slice 2's spec does not name (it scopes the
change to `gitlore_compose_check_pins`), and adding the assertion would force
that edit through a test rather than through the lead's scope call. It is why
`tests/commit_memory.bats` gets the `checkout --detach` negative but **not** the
`/gitlore:merge` one — the latter would fail on the wrapper's own text no matter
what GREEN writes.

Item 1.3's own heading is "`scripts/lib/resolve.sh` **and**
`scripts/lib/index-compose.sh`", so this is plausibly in the item's scope and
merely absent from slice 2's paragraph. Your call whether it rides slice 2 or
becomes a slice 3.

### B. `merge-base --is-ancestor` on a pin that is not in the tier's object DB

`gitlore_compose_check_pins` truncates with `${pinned:0:12}` precisely because
"the pinned commit need not exist in either store's object database"
(`scripts/lib/index-compose.sh:337`). Measured: with a pin the tier does not
have, `merge-base --is-ancestor` exits **128** and prints
`fatal: Not a valid commit name <sha>` on stderr. Under
`if git … merge-base …; then` that lands in the sideways branch, which is the
right answer — but the fatal escapes to the user's terminal, and
`.claude/rules/shell.md`'s rule on `2>/dev/null` applies (failure here is normal
*and* expected, so a guard or a capture-and-match, not a bare redirect).

No test added: the case is outside slice 2's stated case list, and adding one
would expand the RED contract. Flagging it for the GREEN dispatch and the code
review.

### C. One inaccuracy in the RED report

It records (`item-1-3-s2-red.md:57-61`) that `tests/commit_memory.bats`'s
mid-merge test uses "`move_tier_off_pin`/an ahead commit". It does not: that
fixture leaves the tier exactly on its pin and writes `MERGE_HEAD` — its own
comment says rule 7 is never reached. Nothing follows for the tests (it is
unaffected either way, which is what the report concluded), but the reasoning
behind that conclusion does not hold, and it confirmed under mutation B by not
moving.

## Ambient CLAUDECODE

`scripts/run-bats.sh --jobs 1 tests/index_compose.bats tests/commit_memory.bats`,
after all fixes, byte-identical in all three worlds:

| world | result |
| --- | --- |
| `CLAUDECODE=1` | 83 passed, 2 failed — `index_compose.bats:395`, `commit_memory.bats:266` |
| `env -u CLAUDECODE` | 83 passed, 2 failed — same two lines |
| `env CLAUDECODE=0` | 83 passed, 2 failed — same two lines |

Both failures are the two ahead tests, both on `*"ahead"*` — the first assertion
whose subject does not yet exist. The three born-green pins and the two
mid-merge ordering pins are green in all three.

Worth recording for future dispatches: `gitlore_say_for_agent_or_user` tests
`[ -n "${CLAUDECODE:-}" ]` (`scripts/lib/log.sh:10`), so
**`CLAUDECODE=0` takes the AGENT arm**. "Unset" is the only user-arm world; a
test that wants the user arm must `unset`, never set 0.

## shellcheck

`shellcheck -x tests/index_compose.bats tests/commit_memory.bats` — clean, no
output. `-x` because that is what `scripts/lint-shell.sh:45` uses.

## Incident: this repository's HEAD was left on an unborn orphan branch

Repaired, verified, nothing lost — but it happened in the tree the lead commits
from, so it is reported rather than quietly cleaned up.

A probe I wrote to measure `merge-base --is-ancestor` began
`W="$TMPDIR/mbprobe"; mkdir -p "$W"; cd "$W"`. `$TMPDIR` is unset under this
tool (`.claude/rules/shell.md` records exactly this), so `W=/mbprobe`, the
`mkdir` and the `cd` both failed — and `set -e` does not abort a Bash tool
command, so the rest of the script ran **in `/Users/david/code/gitlore`**. It
re-ran `git init` (a harmless re-init), had its `git commit` attempts refused by
the gitmoji hook, created a stray branch `diverged`, and ran
`git checkout --orphan orph`, which moved `HEAD` to an unborn branch and
therefore showed the entire tree as staged.

Damage and repair:

- `refs/heads/main` never moved — `a0b416b` before and after, confirmed against
  `git reflog show main`. No commit was created, amended or lost, and `--orphan`
  does not touch the working tree, so no file content was affected.
- Repaired with `git symbolic-ref HEAD refs/heads/main`, `git reset` (mixed —
  index back to HEAD, working tree untouched), `git branch -D diverged`.
- `core.hooksPath`, `gitlore.hooksDir` and the `memory` submodule verified
  intact afterwards (`memory` clean at the recorded sha, in sync).

The window was roughly three minutes and no commit landed in it. Everything in
this report that ran during that window — the first post-edit run and both
mutations — was **re-run from scratch on the repaired tree**, and every result
quoted above is from a repaired-tree run.

## Tree state

```
$ git status --porcelain
 M tests/commit_memory.bats
 M tests/index_compose.bats
?? plans/index-edit-propagation/reports/item-1-3-s2-red.md

$ git diff --stat
 tests/commit_memory.bats | 101 +++++++++++++++++++++++++++---
 tests/index_compose.bats | 156 ++++++++++++++++++++++++++++++++++++++++++++++-
 2 files changed, 247 insertions(+), 10 deletions(-)

$ git diff --name-only scripts/
(empty)
```

Nothing staged, nothing committed, no branch created or switched. `scripts/`
carries no diff. This report is a fourth untracked file once written.
