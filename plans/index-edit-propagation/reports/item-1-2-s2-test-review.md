# Item 1.2 slice 2 — test review

Verdict: **ships, with two comment fixes applied to the mid-merge test.** Every
assertion in both cases was individually red'd by a mutation I reproduced
myself, except one — `a mid-merge tier …`'s exit-code assertion, which needs
three abort points removed at once and is recorded below as weakly
discriminating rather than left implied. The mid-merge fixture reaches the
`orphaned-merge-head` arm, not `stale-no-merge-head`, so the test passes through
the path it names. Both cases are deterministic under every ambient `CLAUDECODE`
value.

`scripts/lib/resolve.sh` was mutated eleven times and restored after each; final
`git diff --exit-code` clean and `git hash-object` back to
`320eca29c44c95bab495b08e19cb36d6f75eafda`, the pre-review blob.

## Baseline

Both cases are born green, so a passing run proves nothing on its own. Recorded
only to establish the starting point:

```
env -u CLAUDECODE scripts/run-bats.sh --jobs 1 tests/commit_memory.bats
bats: 18 passed, 0 failed
```

## Per-assertion discrimination

Every mutation below was applied to `scripts/lib/resolve.sh` in place, run with
`env -u CLAUDECODE scripts/run-bats.sh --jobs 1 tests/commit_memory.bats`, and
restored from `/tmp/claude/i12s2/resolve.sh.orig` before the next. Line numbers
in the `not ok` output are the shipped file's (the B rows were re-measured after
the comment fixes below shifted them).

### `a manifest refusal is reported and does not abort the commit`

| # | assertion | mutation that reds it | verdict |
|---|---|---|---|
| A1 | `[ "$status" -eq 0 ]` | `return 1` added to the rc-1 arm — abort on every refusal | red, line 224 |
| A2 | `git -C memory rev-parse HEAD` advanced | `return 0` added to the rc-1 arm — report, exit 0, never commit | red, line 225 |
| A3 | `$stderr` has `tier composition refused` | rc-1 header reworded to `tier composition declined` | red, line 226 |
| A4 | `$stderr` has `the tier manifest lists 'phantom'` | `$compose_result` dropped from `$refusal` — header emitted alone | red, line 227 |
| A5 | `$stderr` has `This commit also stages each tier at the commit its worktree is on now` | that sentence deleted from the agent arm | red, line 230 |

All five discriminate. Each was observed failing on its own line, so every one
of them is proven to execute *and* to be capable of failing — stronger than the
RED report's claim, which could only show A1 running in a mutated world and
inferred the rest from the green run.

Verbatim, in order:

```
not ok 13 … line 224 `[ "$status" -eq 0 ]' failed
not ok 13 … line 225 `[ "$(git -C memory rev-parse HEAD)" != "$head_before" ]' failed
not ok 13 … line 226 `[[ "$stderr" == *"tier composition refused"* ]]' failed
not ok 13 … line 227 `[[ "$stderr" == *"the tier manifest lists 'phantom'"* ]]' failed
not ok 13 … line 230 `[[ "$stderr" == *"This commit also stages each tier at the commit its worktree is on now"* ]]' failed
```

A3/A4/A5 red **only** test 13 (`17 passed, 1 failed` each), which also settles
that the case reaches the rc-1 arm rather than the pin guard: mutating that arm
is what breaks it.

### `a mid-merge tier is reported as a merge, not as a moved pin`

| # | assertion | mutation that reds it | verdict |
|---|---|---|---|
| B1 | `[ "$status" -ne 0 ]` | **triple only**: the per-tier stale-merge loop's `\|\| return 1`, the pin guard's `return 1`, and `gitlore_sync_tiers_to_live`'s own guard all disabled | red, line 267 — weakly discriminating, see below |
| B2 | `$stderr` has `holds a merge gitlore did not prepare` | the `orphaned-merge-head` message reworded to `never prepared` | red, line 268 |
| B3 | `$stderr` lacks `moved off the commit the memory store records for it` | the per-tier loop's `\|\| return 1` → `\|\| true` (guard reports, pin guard then aborts) | red, line 273 |

**B1 is weakly discriminating and I did not strengthen it.** Three independent
abort points answer this fixture, and no single- or double-point mutation gets
past all of them:

- loop guard alone disabled → the pin guard aborts (`status` still non-zero; B3
  reds instead)
- loop guard **and** pin guard disabled → `gitlore_sync_tiers_to_live`'s own
  `gitlore_guard_stale_merge_state "$tierpath" || return 1`
  (`scripts/lib/resolve.sh:812`) aborts (measured — B1 still green, B3 red)
- all three disabled → B1 finally reds

So B1 can fail, which is what keeps it from being vacuous, but it cannot
discriminate *which* guard reported — B2 and B3 carry that entirely. Recorded
rather than fixed: the runbook enumerates exactly these three assertions, and
the honest strengthening (asserting the tier's carrier is unchanged, the way
`a tier holding a merge gitlore did not prepare is not composed into` does at
line 159) is an addition the slice does not list. A comment now says this in the
test body.

**B3's negative is properly paired.**
`moved off the commit the memory store records for it` has exactly one producer
in the tree (`scripts/lib/resolve.sh:928`, the pin header), and the neighbouring
`a tier moved off its pin aborts the commit` asserts that same phrase
*positively* over the same induction minus the `MERGE_HEAD` — the
same-fixture-differing-only-in-the-trigger shape. Measured: rewording the pin
header to `a tier was relocated from …` reds test 12 on its positive assertion
(`17 passed, 1 failed`) and leaves test 14 green, so a wording drift is caught
by the pair rather than silently emptying the negative. A comment now records
the pairing.

## The stale-merge state class — settled, not assumed

**State class: `orphaned-merge-head`.** Established by running
`gitlore_detect_stale_merge_state` on the fixture itself, in a throwaway bats
probe driving the test's exact setup (probe created, run, deleted;
`git status --short` below shows no untracked test):

```
state file: …/modules/gitlore-memory/modules/ddaanet/gitlore-merge-state
state file exists: no
MERGE_HEAD exists: yes
memory class:      clean
tier class:        orphaned-merge-head
pin :ddaanet=483803c3b8b9…  HEAD=49b9c34e237d…
dirty=1
STATUS=1
--- STDERR ---
gitlore: memory/ddaanet holds a merge gitlore did not prepare (MERGE_HEAD 49b9c34e237d…, no merge state file), so nothing was changed. Finish it or undo it in the store, then re-run the operation:
gitlore:   git -C "memory/ddaanet" status --short
gitlore:   git -C "memory/ddaanet" merge --abort
```

The fixture writes `MERGE_HEAD` with no `gitlore-merge-state` beside it, which
`gitlore_detect_stale_merge_state` (`scripts/lib/resolve.sh:49-70`) classifies
as `orphaned-merge-head` — the refusing branch. `stale-no-merge-head`, the arm
that delegates to `gitlore_recover_stale_no_merge_head` and can return 0, is
reached only when the state file is **present** and `MERGE_HEAD` is gone, which
is the opposite of this fixture. The hazard the dispatch raised does not obtain.

The probe also confirms the tier is genuinely off its pin (`:ddaanet` ≠ tier
`HEAD`), so the fixture really does put both guards in contention — which is
what makes it able to discriminate the ordering at all.

Two further confirmations from the mutation runs, since a probe reads state
rather than the path taken:

- It is the **per-tier loop** at `scripts/lib/resolve.sh:916` that aborts, not
  the memory-level guard at `:875` (memory classifies `clean`) and not
  `gitlore_sync_tiers_to_live`'s guard at `:812` (disabling the loop guard alone
  changes the message, so the loop is what fired first).
- The message is the `orphaned-merge-head` arm's report, **not**
  `gitlore_emit_merge_directive` — that one belongs to the
  `stale-with-merge-head` arm and never runs here.

**`--absolute-git-dir`: correct.** The fixture uses
`gd=$(git -C memory/ddaanet rev-parse --absolute-git-dir)`, matching
`a tier holding a merge gitlore did not prepare is not composed into` at line
149-156, whose fuller comment names the `CDPATH` hazard a `$(cd … && pwd)`
capture has. This suite does not unset `CDPATH`.

## The fragment slice 1 shortened — checked mechanically

`This commit also stages each tier at the commit its worktree is on now` is an
exact substring of what `scripts/lib/resolve.sh` emits, and it is the **whole**
remedy sentence, not a prefix:

```
grep -nF "This commit also stages each tier at the commit its worktree is on now" scripts/lib/resolve.sh
959:gitlore: … composition runs again at the next memory commit. This commit also stages each tier at the commit its worktree is on now." \
```

Only `."` follows the fragment. The dropped clause is gone from every producer —
`grep -rnF "pin figure printed above" scripts/` hits only the rc-1 arm's own
explanatory comment at `:954`, never a string. And the assertion is confirmed
against *emitted* output rather than only the source: mutation A5 deletes the
sentence and the assertion reds.

**Single-producer check on the rest of the asserted phrases**
(`grep -rnF … scripts/`):

| phrase | producers | reachable on this channel |
|---|---|---|
| `This commit also stages each tier` | 1 (`resolve.sh:959`) | yes |
| `the tier manifest lists` | 1 (`index-compose.sh:178`) | yes |
| `holds a merge gitlore did not prepare` | 1 (`resolve.sh:120`) | yes |
| `moved off the commit the memory store records for it` | 1 (`resolve.sh:928`) | yes |
| `tier composition refused` | 5 | 1 |

The last one is the only phrase with siblings — `scripts/resolve.sh:126`,
`scripts/cc-hooks/session-start.sh:333` and
`scripts/lib/index-compose.sh:787,789`. None is on `commit-memory.sh`'s stderr:
the first two are other entry points, and the `index-compose.sh` pair lives in
`gitlore_compose_and_report`, which the commit path does not call
(`grep -rn gitlore_compose_and_report scripts/` → the two hooks and
`add-tier-batch.sh` only). Mutation A3 red'd the assertion by changing this
producer alone, so it is pinned to the right line today; the siblings are only a
note that a future refactor routing one of them onto this channel could satisfy
it for the wrong reason.

## The overlap with `the rc-1 user arm does not tell a user to retry a commit that succeeded`

**Measured, both directions.** The two tests share the manifest fixture and
differ only in `CLAUDECODE`.

| mutation | test 13 (manifest, agent arm) | test 17 (user arm) |
|---|---|---|
| agent remedy sentence deleted (A5) | **red** on line 230 | green |
| user remedy reworded (`repair` → `fix`) | green | **red** on line 362 |
| `return 1` added to the rc-1 arm (A1) | **red** on `status` | **red** on `status` |
| `return 0` added to the rc-1 arm (A2) | **red** on `HEAD` | **red** on `HEAD` |

So the *message* halves are disjoint — each test is the only thing pinning its
own arm, and the RED report's claim holds there. The *control-flow* halves are
genuine duplicates: `[ "$status" -eq 0 ]` and the HEAD-advanced assertion are
verbatim the same two assertions over the same fixture, and no mutation can red
one without the other. Consolidating them (or not) is the orchestrator's call; I
changed neither, per the dispatch.

## `CLAUDECODE` handling — deterministic in all three ambient worlds

`gitlore_say_for_agent_or_user` (`scripts/lib/log.sh:7-15`) branches on
`[ -n "${CLAUDECODE:-}" ]`, so the only distinction is empty/unset versus any
non-empty value. Both new tests prefix the `run` line with `CLAUDECODE=1`, which
exports it into the `bash "$CMD"` child regardless of the invoking shell. This
subagent's shell has `CLAUDECODE=1` ambient, which is exactly the environment
that would hide a broken override, so all three worlds were run:

```
scripts/run-bats.sh --jobs 1 tests/commit_memory.bats tests/git_hook_pre_commit.bats
  (ambient CLAUDECODE=1)   bats: 36 passed, 0 failed
env -u CLAUDECODE …        bats: 36 passed, 0 failed
env CLAUDECODE=0 …         bats: 36 passed, 0 failed
```

The unset run is the load-bearing one: it passes A5, an assertion on a sentence
the **agent** arm alone emits, which is only possible if the inline
`CLAUDECODE=1` reached the child. `CLAUDECODE=0` covers the non-empty-but-falsy
ambient value, which selects the agent arm anyway. Test B's assertion is
arm-independent — the orphaned-merge message is passed as both arguments
(`gitlore_say_for_agent_or_user "$orph_msg" "$orph_msg"`) — so it is insensitive
either way. Deterministic for a human and for CI.

## Errexit and death points

Bats bodies run under errexit, so a failed assertion ends the body. Because
every assertion was red'd by its own mutation, each one is proven to execute in
some world *and* to be able to fail there — nothing in either test is verified
solely by having been written.

- `a manifest refusal …` — A1 stops at assertion 1, A2 at 2, A3 at 3, A4 at 4,
  A5 at 5. In the unmutated world all five run and hold.
- `a mid-merge tier …` — B1's triple stops at assertion 1; B2 stops at 2 (so
  assertion 1 ran and held there); B3 stops at 3 (so 1 and 2 both ran and held).

No negative sits behind a positive that could hide it: B3 is the last assertion
and its own mutation reaches it.

## Fixes applied

Two comment changes, both to
`a mid-merge tier is reported as a merge, not as a moved pin` in
`/Users/david/code/gitlore/tests/commit_memory.bats`. No assertion, fixture or
name changed; suite still `36 passed, 0 failed` and
`shellcheck -s bash tests/commit_memory.bats` clean.

1. **A mechanism claim that names the wrong arm.** The header comment said the
   tier "must be reported by `gitlore_guard_stale_merge_state`'s merge
   directive". `gitlore_emit_merge_directive` is the `stale-with-merge-head` arm
   and never runs on this fixture; what fires is the `orphaned-merge-head`
   report. The comment now names the classification and says which arm is *not*
   involved. Fixed rather than flagged: cheap, verified, removes nothing, and a
   comment that names a function the path does not call is exactly the claim a
   later reader would act on.

2. **The two things a reader cannot recover from the artifact** — that the exit
   code is defended three deep and therefore discriminates almost nothing here,
   and that the negative's protection against wording drift is the positive
   assertion in the test above it. Both are findings of this review, and both go
   stale silently if unrecorded.

## Restoration and cleanup

```
git diff --exit-code scripts/lib/resolve.sh   → clean
git hash-object scripts/lib/resolve.sh
320eca29c44c95bab495b08e19cb36d6f75eafda      # pre-review blob
git status --short
 M tests/commit_memory.bats
?? plans/index-edit-propagation/reports/item-1-2-s2-red.md
```

The throwaway probe (`tests/zz_probe_s2.bats`) is deleted. `just precommit` not
run, per the dispatch. Nothing committed.
