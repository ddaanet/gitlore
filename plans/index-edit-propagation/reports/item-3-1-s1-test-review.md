# Item 3.1 slice 1 — test review (RED phase)

Verdict: the RED state is genuine but the tests as landed were weaker than the
file's own precedent and than the runbook's interface. Four fixes applied, all
in `tests/index_sync.bats`. The stubs in `scripts/lib/index-sync.sh` are
complete — no case errored on a missing symbol, in the original run or in any of
the isolation runs below — and were left untouched.

## 1. Mechanical check — did every case fail on an assertion?

Before the fixes: two cases red on their own assertions, case 3 green. After:

```
not ok 51 relay_marker_file suffixes the agent id
#   `[ "$output" = "$base-a1" ]' failed
not ok 52 relay_write then relay_drain splits the two channels and removes the marker
#   `[ -f "$marker" ]' failed
not ok 53 relay_drain folds two markers in filename order, over a gitdir path holding a space
#   `[[ "$GITLORE_RELAY_SYSMSG" == *"S-one"*"S-two"* ]]' failed
bats: 72 passed, 3 failed
```

Three assertion failures, no ERROR, no missing symbol. The empty-store case (now
#54) is still green.

### The empty-store case's green — adjudicated

The RED report's argument holds, and I could not break it. The dispatch's three
suggestions each fail for the same reason: the stub is specified to do the
*correct* thing on the degenerate input, so anything the correct implementation
must produce there, the stub already produces.

- *Stale value from a previous drain*: I added the sentinel pre-seed anyway
  (below) — the stub assigns `""` unconditionally, so it clears the sentinels.
- *Non-zero on an empty store*: the stub returns 0.
- *A non-relay file in the gitdir*: I added the decoy anyway — the stub touches
  no file, so the decoy survives.

The only way to red this case against the specified stub is to assert something
the stub is specified not to do, which means changing the stub contract the
runbook fixes. It genuinely cannot red here.

What a wrong GREEN implementation would have to do to slip past it, now that the
fixes are in — it must, on an empty store: return 0; assign both variables (not
merely leave them); and not remove `gitlore-compose-stamp`. Before the fixes it
only had to *not assign garbage*, which every implementation that leaves the
variables untouched also satisfies, since bats starts each test with them unset.
That was the real defect: the case was satisfied by birth state
(`green-is-not-evidence`, "satisfied by birth state"), not merely by the stub.

## 2. The cross-check negatives and `[ ! -f "$marker" ]` in case 2

Confirmed: vacuous in RED, discriminating in GREEN. Concretely —

- `[[ "$GITLORE_RELAY_SYSMSG" != *"C1"* ]]` and
  `[[ "$GITLORE_RELAY_CTX" != *"S1"* ]]` catch a drain that reads the marker
  whole and assigns the same text to both variables — i.e. one that never splits
  on the `--- gitlore-relay-ctx ---` line. That implementation passes every
  positive in the case (both bodies are present in both variables) and is
  exactly the shape the runbook names.
- `[ ! -f "$marker" ]` catches a drain that folds without unlinking, which
  re-emits every block on every later parent-side batch — an unbounded repeat,
  not a one-off.

Neither is vacuous-in-both-phases: each names an observable the GREEN write path
actually produces (a populated marker, a file on disk), which is the third
staleness `green-is-not-evidence` warns about.

They do sit behind positives under errexit, so in a run where an earlier
positive fails they never execute. That is inherent to the runbook's one-case
shape (the marker must be checked before the drain removes it), and the
isolation run below covers what the ordering costs.

## 3. Case 1's shape — rewritten

Three faults, all fixed:

- **Trailing glob instead of equality.** `[[ "$output" == *-a1 ]]` passes for
  any path anywhere ending in `-a1`. The comment block 70 lines above these
  cases states the precedent and its reason verbatim: equality against the
  `rev-parse --git-path` name "pins the file inside the memory submodule's
  gitdir, rejects a `-` appended for an empty id, and rejects a doubled or
  partial suffix". The bare-call half was worse — `[[ "$output" != *-a1 ]]` is
  satisfied by the empty string, by an error message, by any path at all.
- **The baseline came from the SUT.** `base=$(gitlore_relay_marker_file memory)`
  computed the expected value with the function under test, then never used it
  (dead assignment). Now
  `base=$(git -C memory rev-parse --git-path gitlore-relay)`, matching the
  preimage and compose-stamp cases.
- **The empty-string input was not covered at all.**
  `gitlore_relay_marker_file memory ""` is the distinct third input and the one
  at risk in `_gitlore_agent_suffix`: an implementation that suffixes on an
  empty id yields `gitlore-relay-`, which the old `!= *-a1` assertion happily
  accepts. Both precedent cases (`preimage_file is unsuffixed with no agent id`,
  `compose_stamp_file …`) assert it; this one now does too.

Ordering also changed: the two unsuffixed halves run **first**, so in this RED
run all three assertions execute (the two that hold against the stub pass, the
keyed one reds) rather than the keyed failure hiding them. The RED report had to
manufacture that with a scratch reorder; the order now gives it for free.

Kept, not dropped: the bare-call assertion is worth keeping now that it is an
equality — it catches an implementation that suffixes unconditionally, which
would migrate the main thread's files. As a trailing-glob negative it was worth
nothing.

## 4. Wrong-reason hunt

**Errexit turning failures into aborts (fixed, both cases).**
`gitlore_relay_write memory a1 "S1" "C1"` and `gitlore_relay_drain memory` were
bare calls in a bats body, which runs under errexit. A non-zero return aborts
the test at that line instead of failing a named assertion — the contract's
"returns 0 after writing" and "returns 0 always" halves were pinned by nothing.
Worse, case 3 read `status=$?` on the line *after* the call, which errexit makes
unreachable on exactly the input it exists to check, and it shadows bats' own
`$status`. Now: `run gitlore_relay_write …; [ "$status" -eq 0 ]` for the write
(a subshell is fine — its whole output is a file), and
`rc=0; gitlore_relay_drain … || rc=$?; [ "$rc" -eq 0 ]` for the drain (`run`
would discard the two variables that *are* its output).

**Whitespace safety had zero coverage — new case added.** The runbook's own
interface line requires the enumeration to be whitespace-safe "since the gitdir
path may contain spaces", and requires the fold to be in filename order "so a
two-marker assertion cannot flake on directory order". No case in slice 1 — or
in slices 2, 3 or 4 — exercises either. The fixture's gitdir path (`mktemp -d`
under `$TMPDIR`) has no space and every other case writes a single marker, so
`ls "$dir" | …`, an unquoted `$dir/gitlore-relay-*` glob, and a fold in reverse
order all pass the whole item. Agent ids cannot supply the space —
`_gitlore_agent_suffix` collapses everything outside `[A-Za-z0-9-]` to `_`, so
the containing path is the only whitespace surface there is.

Added
`relay_drain folds two markers in filename order, over a gitdir path holding a space`:
builds the parent out of line at `$TMP_REPO/has space` via
`_gitlore_build_parent_with_memory` (the same helper `make_parent_with_memory`
uses for a non-default subpath; the cached template cannot carry a spaced root),
guards that the resulting marker path really contains a space before asserting
anything on it, writes two markers, and pins order with `*"S-one"*"S-two"*`
rather than two presence checks. It reds on its own assertion against the stub.
This is the one addition beyond the three cases the runbook names — flagged here
rather than folded in silently, since the orchestrator may prefer it as a slice
of its own.

**Attribution was pinned on one channel only (fixed).** The interface says each
block carries a framing line naming its agent id, and both variables hold
blocks; the case asserted `a1` in `GITLORE_RELAY_SYSMSG` and nothing in
`GITLORE_RELAY_CTX`. A drain that framed only the user-facing channel passed.
Both are asserted now, and both red independently against the stub. GREEN must
frame both channels — this is a reading of the interface line, not an addition
to it.

**Checked and clean:**

- *Quoting*: every path expansion in the new cases is quoted, including the
  spaced-root ones (`"$TMP_REPO/has space"`, `"$mem"`,
  `"$(gitlore_relay_marker_file "$mem" a1)"`).
- *bash 3.2 / BSD*: the additions use `[[ … == … ]]`, `case … in *\ *)`, `run`,
  `:` and `git` only. No `mapfile`, no `${var^^}`, no GNU-only flag, no
  `stat`/`sed`/`find`/`mktemp` invocation, so nothing
  `tests/helpers/bsd-stubs.bash` shadows is reached.
- *Fixture leakage*: `_gitlore_build_parent_with_memory` builds under
  `$TMP_REPO`, which `teardown_tmp_repo` removes; the decoy in the empty-store
  case is written inside the memory gitdir under the same `$TMP_REPO`. The
  sentinel assignments are test-local shell variables, and bats runs each case
  in its own process, so they cannot reach another case.
- *Substring collisions*: `S1`, `C1`, `S-one`, `C-two` and `a1` appear nowhere
  in the delimiters (`--- gitlore-relay-sysmsg ---`,
  `--- gitlore-relay-ctx ---`), so no cross-check can be satisfied by framing
  text rather than by a body.

**Not fixed, out of scope, for GREEN's attention:** the unsuffixed
`gitlore-relay` name is never written by `gitlore_relay_write` in production
(the hooks call it only when `agent_id` is present) and no case pins that the
drain ignores an unsuffixed marker if one existed. Slice 1's three named cases
do not reach it and I did not invent a fourth for it; the decoy in the
empty-store case covers the adjacent and more damaging fault (a `gitlore-*` glob
eating the compose baseline).

## Isolation run — every assertion's red is its own

Built a scratch bats file putting each post-drain assertion of cases 2 and 3 and
each assertion of case 4 in its own test body over a shared `prep`, ran it
against the stub, and deleted it (`git status` verified clean afterwards).
Independently red — each fails on its own, not behind an earlier failure:

- case 2: `GITLORE_RELAY_SYSMSG == *S1*`, `GITLORE_RELAY_CTX == *C1*`,
  `GITLORE_RELAY_SYSMSG == *a1*`, `GITLORE_RELAY_CTX == *a1*`
- case 3: both order assertions

Green against the stub, i.e. discriminating only in GREEN — recorded, not
hidden: the `rc` checks, both cross-check negatives, all four marker-is-gone
checks, the space guard, and all four empty-store assertions. Section 2 above
states what each of these catches once the marker is populated.

## Checks that passed, by name

- `./scripts/run-bats.sh tests/index_sync.bats` — 72 passed, 3 failed; the three
  failures are the intended reds, each on a named assertion, and the 70
  pre-existing cases plus the empty-store case are green.
- Per-assertion isolation run over cases 2, 3 and 4 against the stub — 11
  passed, 6 failed, with the six reds as enumerated above.
- `shellcheck -s bash tests/index_sync.bats` — clean, exit 0.
- `./scripts/lint-shell.sh` — 137 files clean.
- `git status --short` — only `scripts/lib/index-sync.sh` and
  `tests/index_sync.bats` modified, plus the two report files; no scratch bats
  file and no stray fixture left behind. Nothing committed, nothing staged.
