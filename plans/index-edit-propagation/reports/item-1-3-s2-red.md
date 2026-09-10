# Item 1.3 slice 2 — RED report

SUT untouched throughout: `scripts/lib/index-compose.sh` carries no diff against
HEAD at the end of this dispatch (`git diff --stat` shows only the two test
files). The one mutation used to prove the born-green cases' sensitivity was
applied and reverted within this run; confirmed by a post-revert `git diff`
showing the file clean.

## Fixtures

`tests/index_compose.bats:236` (`move_tier_off_pin`) commits a fast-forward
descendant of the current tier HEAD — this is the AHEAD shape, not sideways,
despite its name. No sideways fixture existed. Added
`move_tier_sideways_off_pin` right beside it
(`tests/index_compose.bats:243-256`): `git checkout --orphan` onto a fresh
branch, then a commit — an orphan's first commit shares no history with anything
already in the tier, including the pin, so
`merge-base --is-ancestor "$pinned" "$head"` reads false in both directions.
Verified this empirically (see "Mutation proof" below, and the repointed tests
passing against unchanged code).

`tests/commit_memory.bats` doesn't load `index_compose.bats`'s local functions,
so its own repointed test (`:162`) reproduces the same shape inline:
`git checkout -q --orphan gitlore-sideways-test` then `commit -q --allow-empty`,
rather than calling the helper.

## Tests repointed (both were ahead fixtures asserting wording; per dispatch,
neither is deleted)

1. **`tests/index_compose.bats:254`** — "compose refuses a moved tier and names
   the commands that return it". Before: asserted the existing wording +
   `checkout --detach` remedy against `move_tier_off_pin` (ahead). After: same
   assertions, same fixture call site, now against `move_tier_sideways_off_pin`.
   Nothing else in the body changed — this test already only ever asserted the
   message the sideways case keeps.

2. **`tests/commit_memory.bats:162`** — "a tier moved off its pin aborts the
   commit". Before:
   `git -C memory/ddaanet commit -q --allow-empty -m "moved outside /gitlore:merge"`
   (a fast-forward, i.e. ahead). After:
   `checkout -q --orphan gitlore-sideways-test` then the same `--allow-empty`
   commit, landing a root commit unrelated to the pin. Assertions unchanged
   (`"moved off the commit the memory store records for it"`,
   `"is checked out at"`, `"Return the tier to its pin with the command above"`)
   — all three are either resolve.sh's generic wrapper text (unaffected by
   ahead/sideways) or the sideways-preserved index-compose.sh wording.

Verified `tests/index_compose.bats:275` ("a moved tier holding MERGE_HEAD is
sent to /gitlore:resolve instead") and `:290` ("a moved tier with a merge state
file and no MERGE_HEAD is mid-merge too") both still build on
`move_tier_off_pin` (ahead) **and** keep passing — `ok 26`/`ok 27` in every run
below. Both are, incidentally, already "mid-merge and ahead" fixtures; neither
needed a change since the mid-merge branch in `gitlore_compose_check_pins` runs
before the (not-yet-added) ancestry test and their assertions (`"is mid-merge"`,
absence of `checkout --detach`) don't touch the off-pin wording at all.

Also checked `tests/index_compose.bats:303` ("staging the moved gitlink lets the
same store compose again") and `tests/commit_memory.bats`'s mid-merge test
(`"a mid-merge tier is reported as a merge, not as a moved pin"`) — both use
`move_tier_off_pin`/an ahead commit but assert nothing about the off-pin
wording, so they're untouched and unaffected either way.

## New tests (genuinely red)

1. **`tests/index_compose.bats:279`** — "a tier ahead of its pin is refused with
   ahead-of-the-pin wording, not the return-to-pin remedy". Fixture:
   `pinned_store_with_tier` + `move_tier_off_pin` (ahead). Asserts
   `status -eq 1`, `"tier 'ddaanet'"` present, then three stable substrings —
   `"ahead of"`, `"discard"`, `"no automatic adoption"` — plus the explicit
   negative `"checkout --detach"` absent.

   Chosen substrings and why each is stable: `"ahead of"` is the runbook's own
   name for this branch ("worded as ahead-of-the-pin"); `"discard"` is the
   runbook's own verb for what returning to the pin costs ("discard the commits
   it carries"); `"no automatic adoption"` is the runbook's own phrase for the
   missing remedy ("no automatic adoption exists"). None of the three presuppose
   a full sentence, and none currently appear anywhere in the unchanged off-pin
   message (which only ever names `checkout --detach`), so the test is red for
   the right reason rather than an accident of phrasing.

2. **`tests/commit_memory.bats:207`** — "the pin-abort's ahead wording reaches
   both the agent arm and the user arm". Fixture: same manifest/tier setup as
   the repointed test above, but with the AHEAD commit
   (`commit -q --allow-empty`, no orphan). Runs the commit twice against the
   same fixture — once `CLAUDECODE=1`, once with `CLAUDECODE` unset — asserting
   the same three substrings both times. This works because
   `gitlore_sync_memory_to_live`'s abort wrapper
   (`scripts/lib/resolve.sh:1000-1009`) embeds `$pin_problems` — which is
   exactly `gitlore_compose_check_pins`'s output — verbatim into *both* branches
   of `gitlore_say_for_agent_or_user`; no resolve.sh change is needed for the
   wording to reach either arm once index-compose.sh says it. The abort writes
   nothing, so re-running against the same fixture with a different `CLAUDECODE`
   is safe (confirmed: both runs report the same `status -ne 0`).

## RED confirmation, all three ambient worlds

Ambient in this dispatch is `CLAUDECODE=1` (subagent). Ran
`scripts/run-bats.sh --jobs 1 tests/index_compose.bats tests/commit_memory.bats`
under `CLAUDECODE=1`, `env -u CLAUDECODE`, and `env CLAUDECODE=0` — identical
result every time:

```
not ok 25 a tier ahead of its pin is refused with ahead-of-the-pin wording, not the return-to-pin remedy
# (in test file tests/index_compose.bats, line 324)
#   `[[ "$output" == *"ahead of"* ]]' failed
not ok 77 the pin-abort's ahead wording reaches both the agent arm and the user arm
# (in test file tests/commit_memory.bats, line 244)
#   `[[ "$stderr" == *"ahead of"* ]]' failed

bats: 82 passed, 2 failed
```

Both fail on their first *new* assertion — the `status -eq`/`-ne` check and, for
the index_compose test, the `"tier 'ddaanet'"` substring, both pass first
(confirmed by the `not ok` block naming only the `"ahead of"` line as failed;
bats reports the first failing assertion, so everything above it in the test
body already ran clean against unchanged code). No `ERROR`, no test aborted
early on a missing fixture or helper — both fixtures (`move_tier_off_pin` ahead
commit) already exist and work.

## Born-green cases

- **"compose refuses a moved tier and names the commands that return it"**
  (`tests/index_compose.bats:254`) and
  **"a tier moved off its pin aborts the commit"**
  (`tests/commit_memory.bats:162`): both hold against unchanged code (today
  ahead and sideways get identical wording), so neither can be forced red by
  writing it. Proof owed to the test review's mutation, applied and reverted in
  this dispatch: in `gitlore_compose_check_pins`
  (`scripts/lib/index-compose.sh`, right after the mid-merge branch and before
  the `abs=$(...)` line), inserted an unconditional
  `problems="${problems}tier '$tier' is ahead of the pin; ...` + `continue` —
  i.e. the ahead branch with the `merge-base --is-ancestor` test itself omitted,
  so it fires for every off-pin tier regardless of direction. Result: both tests
  went red — `tests/index_compose.bats:293`
  (`"tier 'ddaanet' is checked out at ${moved:0:12}"` failed) and
  `tests/commit_memory.bats:216` (`"is checked out at"` failed) — proving both
  are sensitive to the ancestry test rather than vacuously true. Reverted
  immediately after (`git diff --stat scripts/lib/index-compose.sh` empty
  since).

- **"a tier that is both mid-merge and ahead takes the mid-merge branch"**:
  already covered, and already born-green, by the pre-existing
  `tests/index_compose.bats:275` and `:290` (both combine `move_tier_off_pin`
  with a MERGE_HEAD or merge-state-file). No new test added for this bullet —
  the existing pair already is the "mid-merge and ahead" fixture and already
  asserts the mid-merge branch fires (via `"is mid-merge"` and the absence of
  `checkout --detach`). Not forced red, per instruction; confirmed passing
  (`ok 26`, `ok 27`) in every ambient-world run above.

## shellcheck

Clean on every file touched:
`shellcheck tests/index_compose.bats tests/commit_memory.bats scripts/lib/index-compose.sh`
— no output, all three.

## Tree state

```
$ git status --porcelain
 M tests/commit_memory.bats
 M tests/index_compose.bats
$ git diff --stat
 tests/commit_memory.bats | 65 ++++++++++++++++++++++++++++++++++++++++++------
 tests/index_compose.bats | 60 +++++++++++++++++++++++++++++++++++++++++++-
 2 files changed, 117 insertions(+), 8 deletions(-)
```

Nothing staged, nothing committed, no untracked files.
`scripts/lib/index-compose.sh` carries no diff.
