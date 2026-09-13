# Deliverable review — test partition (Layer 1)

Plan: `plans/index-edit-propagation`. Range `b6dbe92..HEAD`, excluding the hunks
of `3d50a1f`, `c2e7950` and `ae54c1b`. Baseline: `runbook.md` (as-executed and
as-amended notes take precedence) and `outline.md`. I read
`reports/tdd-audit.md` first and do not repeat its process findings (D1–D6). The
one overlap is M7b, a partially written marker. `8523b47` made the write atomic
after the audit ran, and the `.tmp` cases now pin that, so M7b is closed at the
single-writer level. C1 below covers the concurrent-writer form of the same
problem.

I did not run any suite. I read the code and ran one shell probe in
`/tmp/claude/relayprobe/probe.sh`, which sources the real
`scripts/lib/index-sync.sh`.

**Counts:** Critical 1 · Major 1 · Minor 9

## Coverage against the runbook

Every case the runbook names exists and asserts what the runbook says. I checked
each item and slice:

- **Item 1.1:**
  - Slice 1: both entry points.
  - Slice 2: the clean case and the dirty case.
  - Slice 3: the rc-1 case, re-homed by 1.2, and the rc-2 case.
  - Slice 4: four cases.
- **Item 1.2:** slice 1 (both entry points), slice 2 (manifest refusal and
  mid-merge ordering) and slice 3 (pin-abort user arm).
- **Item 1.3:**
  - Slice 1: all seven listed cases, plus the host-project case.
  - Slice 2: all five listed cases, including branch order through both
    mid-merge predicates.
- **Item 2.1:** slices 1–4, including the traversal guard and the `agent_type`
  decoy on every unkeyed payload.
- **Item 3.1:** slices 1, 2, 2.5 and 3–5. Slice 4's
  `an unkeyed run survives a non-file squatting on a marker name` was retired in
  slice 5. Its superset, `an unkeyed run leaves a non-marker alone`, replaced it
  (see m7).

Permission cases:

- All six carry the `id -u` root skip.
- Every restore sits immediately after `run` and is conditional where the fixed
  code removes the target.
- `jq -r` null handling is explicit wherever a negative reads an extracted
  channel.

On the bash side, `unset CDPATH` in `tests/helpers/setup.bash` removes the
ambient `cd` hazard for the whole suite.

CLAUDECODE worlds:

- Every case that reads one arm sets it with a `CLAUDECODE=1 run` prefix or runs
  `unset CLAUDECODE` in the body.
- Cases that read neither arm assert only arm-independent text, such as the
  headers inside `$partial`/`$unknown` and the direct `printf` lines in
  `gitlore_adopt_recovered_merge`.
- So all three worlds (set to 1, unset, empty) give the same verdict.

## Critical

### C1 — The two PostToolBatch hooks run in parallel, and the relay loses, tears or duplicates reports under that

- **Locations:** `scripts/lib/index-sync.sh:166-217` (`gitlore_relay_write`) and
  `:236` (`gitlore_relay_drain`). The test is
  `tests/cc_hook_index_compose.bats:357-411`.
- **Axis:** functional correctness and invocation path.

**The premise is false.** Slice 2.5 and its test say `hooks.json` runs
`index-sync-post.sh` and `index-compose.sh` "on the SAME PostToolBatch event, in
that order". The comment at `tests/cc_hook_index_compose.bats:357` states it
too. Claude Code does not order them. The hooks reference
(code.claude.com/docs/en/hooks, fetched 2026-09-12) says: "All matching hooks
run in parallel."

**Why the design breaks.** `gitlore_relay_write` is read → merge → write, and
the write goes to a temp path, `$marker.tmp`, that is the same for every writer
with the same agent id. `gitlore_relay_drain` is find → awk → rm with no lock.
Both hooks write to one keyed marker in a subagent batch. Both drain the same
markers in a parent batch.

**Probe.** Two concurrent calls, 200 iterations each, against the real library:

- Two parallel `gitlore_relay_write m a1 …` calls:
  - 92 kept both reports.
  - **106 lost one report.** 108 calls returned non-zero, because the second
    writer's `mv` finds the temp already renamed.
  - **2 left a torn marker**, where both writers interleaved into the shared
    temp. One drained body was `COMPO------ gitlore-relay-ctx -SYNCOMPCTX`.
- Two parallel `gitlore_relay_drain m` calls over one marker:
  - **199 framed the same block twice.** Both `find`s ran before either `rm`.
  - **13 framed an empty block.** One `rm` landed between the other drain's
    `find` and its `awk`.

The not-staged line tells the subagent about some of the lost writes. The torn
marker and the duplicated or empty drain reach the parent with nothing said.

**Failure scenario.** A subagent edits `MEMORY.md` with a tier mounted, which is
the ordinary case slice 2.5 was written to fix. About half the time the parent
never receives the frontmatter-sync report. On the next parent batch that
touches the index, both hooks drain and the user sees each relayed block twice.

**Why the suite is green.** The one case that exercises the slice 2.5 defect,
`both PostToolBatch hooks in one keyed batch reach the parent`, drives the hooks
one after the other in a fixed order. Every drain case drives a single hook.
FR-D ("reports produced inside a subagent reach the parent session") does not
hold under the harness's real scheduling.

This is a SUT defect, found through the test partition's invocation-path check.
The fix needs a design call, for example:

- a per-writer temp name plus a lock around the merge, or
- one marker per (agent, hook) with the drain recovering the agent id, which
  slice 2.5 rejected for the parsing cost it adds.

## Major

### M1 — No case drives the PostToolBatch hooks concurrently, and the slice 2.5 case asserts an order the harness does not give

- **Location:** `tests/cc_hook_index_compose.bats:368`, plus the four
  unkeyed-drain cases (`:257`, `:297`, `:334`; `tests/index_sync.bats:751`,
  `:796`).
- **Axis:** completeness and invocation path.

The runbook's must-check asks whether the C and D races are actually exercised:

- **Race C is.** The parent/subagent interleavings in `tests/index_sync.bats`
  (`a parent post-hook leaves a subagent's pre-image intact` and its
  continuation) and in `tests/cc_hook_index_compose.bats:183,208` are the
  correct deterministic form, because the two agents' files are disjoint.
- **Race D is not.** It is a race between two hooks writing one file. A fixed
  sequential order can only exercise the merge logic, never the concurrency.

**Mutation that ships green.** Replace the `mv` install with `cat tmp > marker`,
or drop the merge's read-before-open ordering. Every case still passes, because
no case has two writers or two drainers alive at the same moment.

**Fix shape.**

- Run `sync_feed a1 & feed a1 & wait` in a loop, for example 20 iterations, and
  assert that the parent's report carries both lines every time.
- Do the same for two concurrent unkeyed drains, asserting exactly one framing
  line.
- The probe above reds in the first few iterations.

## Minor

### m1 — Mid-test `[[ … ]]` assertions do not fail on bash < 4.1

- **Scope:** cross-cutting; 102 added `[[` lines across the reviewed files.
- **Axis:** macOS robustness.

bats-core documents that a failing `[[ ]]` does not trigger errexit on bash
before 4.1 unless it is the last command in the test. If macOS runs the suite
under `/bin/bash` 3.2, every non-final `[[` in these files goes silent. That
includes the discriminating negatives in `tests/commit_memory.bats:228,524` and
all the relay channel checks.

This is house style: the baseline already has 574 such lines. It is also
unobservable on the Linux box. It is recorded because the dispatch lists it as a
must-check. The per-assertion fix is `[[ … ]] || false`. The alternative is to
state that bats requires bash ≥ 4.1.

### m2 — Comments still describe the pre-atomic write

- **Locations:** `tests/index_sync.bats:1118`,
  `tests/cc_hook_index_compose.bats:416,427-428,454-455`.
- **Axis:** specificity (the comments misstate the mechanism).

The comments say the directory squat makes "the write's redirect fail with 'Is a
directory'" and that the redirect prints that line on stderr. Since `8523b47`,
the redirect targets `$marker.tmp` and succeeds. The explicit `[ -d "$marker" ]`
check is what refuses, and it prints nothing. The assertions still discriminate:

- A trailing `return 0` reds `relay_write refuses a squatted marker path`.
- Dropping the `-d` check makes `mv` move the temp into the directory and return
  0, which reds the not-staged case.

The next reader is told the wrong reason, though, and the `--separate-stderr`
justification at `:427` and `:454` no longer applies.

### m3 — The sideways test names the wrong red line for its own mutation

- **Location:** `tests/commit_memory.bats:180-186`.
- **Axis:** specificity.

The comment says that under the "ahead branch without the ancestry test"
mutation, `"is checked out at"` goes red. The ahead message also contains
`is checked out at` (`scripts/lib/index-compose.sh:349`), so that assertion
stays green. The red actually comes from `[[ "$stderr" != *"ahead"* ]]` at
`:228`. Under m1 on bash 3.2, that negative is silent.

### m4 — The born-green comment on the memory-root case describes a predicate the code does not have

- **Location:** `tests/resolve_recovery.bats:390-400`.
- **Axis:** specificity.

The comment says staging is scoped by "the recovered store's own path … is one
of `gitlore_tier_paths "$superproject"`". `gitlore_adopt_recovered_merge`
deliberately has no such test (`scripts/lib/resolve.sh`, the header of that
function). The comment at `:474-480` in the same file says so, and names the
own-path exclusion clause instead. The two comments contradict each other.
`:402-411` already downgrades the case to a characterization; the predicate text
above it should follow.

### m5 — Comments wrongly say bats clears CLAUDECODE

- **Locations:** `tests/commit_memory.bats:456,481,505`, and the `:444` phrase
  "the state a bats run leaves it in anyway".
- **Axis:** specificity.

Each comment opens with "A bats run leaves CLAUDECODE unset". The runbook (Item
1.1 note), `tests/push_memory.bats` and `tests/tier_lockstep.bats` all state the
opposite: bats inherits it. The `unset` that follows is correct. The comment
teaches the misconception it guards against.

### m6 — The hook-entry off-pin case does not assert why it aborted

- **Location:** `tests/git_hook_pre_commit.bats:225`.
- **Axis:** specificity.

The case asserts non-zero exit, unchanged HEAD, unchanged `:ddaanet` and an
unchanged carrier. An abort for any other reason satisfies all four: a freshness
refusal, the stale-merge loop, or a hook that dies early on its environment.

It does discriminate the specified mutation: removing the pin guard lets the
commit land. What stays unpinned is that the second entry point's abort is the
pin guard. One `--separate-stderr` assertion on
`moved off the commit the memory store records for it` would pin it. The runbook
specified only the four state assertions, so this is Minor.

### m7 — The runbook still lists a retired case and a superseded remedy sentence

- **Location:** `runbook.md` Item 3.1 slice 4 (`:1212`) and Item 1.2 (`:428`,
  `:474`, `:571`).
- **Axis:** conformance.

Two points in the runbook no longer match the suite:

- **Retired case.** Slice 5's green removed
  `an unkeyed run survives a non-file squatting on a marker name`
  (`reports/item-3-1-s5-green.md:39-46`), and its assertions live on in
  `an unkeyed run leaves a non-marker alone`. The runbook's slice 4 list still
  names the case, with no as-executed note.
- **Remedy sentence.** Item 1.2 fixes the agent remedy as
  `Return the tier to its pin with the command above`. The code and tests now
  pin `Follow the remedy on each line above`
  (`tests/commit_memory.bats:225,524`), and no amendment records the change.

The tests are right. The design baseline is stale.

### m8 — The non-fatal `agent_id` read in two hooks has no test

- **Locations:** `scripts/cc-hooks/index-compose.sh:44`,
  `scripts/cc-hooks/add-tier-batch.sh:66`.
- **Axis:** coverage.

Both hooks justify `|| agent_id=""` at length. In index-compose, an aborting jq
would leave the stamp unconsumed and hand this agent's next batch an ancient
baseline. In add-tier, no payload shape may abort a mount. No case feeds a
non-JSON payload, so deleting `|| agent_id=""` ships green.

`index-sync-pre.sh:40` and `index-sync-post.sh:23` read the same field fatally.
The asymmetry is unargued in tests and code alike.

The `index-sync-post.sh` not-staged branch that falls back to `$sysmsg` is also
unpinned, but the runbook records that one as an accepted residual (Item 3.1
slice 5).

### m9 — No spaced-path case for the recovery's adoption, and its printed remedy is not runnable with a space

- **Location:** `scripts/lib/resolve.sh:341`, `tests/resolve_recovery.bats`.
- **Axis:** whitespace safety.

`gitlore_adopt_recovered_merge` derives `rel` by prefix-stripping `$super` from
`$abs` and passes paths to `compose_up` and `git add`. All of it is quoted, but
no case runs it under a spaced root. The relay cases are the only new
spaced-path coverage.

Its staging-failure message prints ``Run `git -C %s add -- MEMORY.md %s` `` with
both paths unquoted. With a space in the project path, the command a user copies
does not run. This breaks the verbatim-runnable rule that
`gitlore_compose_check_pins` follows by quoting `\"$abs\"`.
`recovery: a staging failure … is reported` asserts only the phrase
`could not be staged`, so a spaced fixture plus an assertion on the quoted
command would pin both.

Smaller robustness point: in `tests/git_hook_pre_commit.bats:388-392`,
`head_before=$(git … rev-parse HEAD)` sits between `chmod a-w memory/beta` and
`run`. That is the "nothing failable between the chmod and the restore" shape
the comment at `tests/index_sync.bats` warns about. If it failed, `memory/beta`
would stay at mode 555 and teardown could not remove the fixture. Capture it
above the chmod.

## Checked and clean

- **Must-have state assertions.**
  - Off-pin fixtures move the index gitlink `:ddaanet` against the tier's HEAD,
    never `HEAD:ddaanet`.
  - The ahead, orphan and diverged shapes are each asserted with `merge-base` /
    `--is-ancestor` rather than assumed.
  - The two-tier rc-2 case asserts its composition order from the output.
- **Negatives.** Each is backed by a positive over the same literal elsewhere:
  - `!= *checkout --detach*`, `!= */gitlore:merge*`, `!= *ahead*`;
  - the agent remedy refuted in the user arm;
  - the relay framing refuted in `session-start with no marker`;
  - `!= *SCRATCH.md*` against an `add -A` mutation.
- **`jq -r` null trap.**
  - `cc_hook_session_start.bats` and `cc_hook_index_compose.bats:448` guard
    against the literal `null`.
  - Elsewhere, every negative on an extracted channel is followed by a positive
    on the same capture, so a missing key reds it.
- **Invocation path.**
  - Hooks are driven with real stdin JSON: `agent_id` present and absent, and
    always with an `agent_type` decoy.
  - Executable-bit tests exist for index-compose, add-tier-batch and both
    index-sync hooks.
  - The pre-commit hook runs as `bash "$HOOK"` with `CLAUDE_PLUGIN_ROOT`
    exported.
- **macOS portability.** The added lines use no GNU-only `sed -i`, `stat -c` or
  `find -printf`. `mktemp` templates end in `X`s, and `sed '$d'`, `tr -c` and
  `find -print0` are BSD-safe.
