# Phase 1 checkpoint — corrector report

Item 1.1 as a whole, across `4dd02bc`, `0cce041`, `16abc35`, `6790195`. Four
findings fixed in place, four flagged. Nothing committed.

Files changed by this pass:

- `scripts/commit-memory.sh`
- `scripts/cc-hooks/memory-commit-batch.sh`
- `tests/commit_memory.bats`
- `tests/cc_hook_memory_commit_batch.bats`
- `tests/commit_memory_approval.bats` (new — see finding 4)

## Findings fixed

### 1. MAJOR — a blank approval file is a per-batch refusal loop

`-s` on both sides screens a zero-byte file and admits a whitespace-only one.
`git commit -F` then rejects it as an empty message on an arm that restamps
`$msgfile` (`resolve-sync-memory.sh:243`), so freshness reads `yes` and the hook
emits the deferred pair — *every* batch, verbatim, under "otherwise no action is
needed from you". This is the exact loop the slice-1 review closed for zero
bytes, surviving one byte later.

Verified against the code as committed, not read:

```
--- BATCH 1: gitlore: memory commit deferred, will retry automatically. Aborting commit due to empty commit message.
    ctx: … it retries by itself on a later tool batch, with the approved summary preserved … otherwise no action is needed from you. Reason: Aborting commit due to empty commit message.
    HEAD moved: no   msgfile size: 1   trigger: present
--- BATCH 2: gitlore: memory commit deferred, will retry automatically. Aborting commit due to empty commit message.
```

Reachable from the D16 arg path too: `-m ""` and `-F -` over empty stdin both go
through `printf '%s\n' "$summary"`, which writes a one-byte file. Probed
directly: `status=1`, `ERR: Aborting commit due to empty commit message.`,
`msgfile size: 1` — git's raw text, no `gitlore:` prefix, no remedy.

Fixed with one predicate, carried identically in both scripts — which is also
what the scope's "the two notions of *no summary* agreeing" asks for:

```sh
if [ ! -s "$msgfile" ] || ! grep -q '[^[:space:]]' "$msgfile"; then
```

`-s` short-circuits so `grep` is never handed a missing file (no `2>/dev/null`).
In `commit-memory.sh` the screen moved *after* the `-m`/`-F` write rather than
staying an `elif`, so the arg path is screened too and a blank summary meets the
entry point's own directive instead of git's abort. `grep -q` with a POSIX class
is BSD-clean.

### 2. MAJOR — the deferred message was false on the consumed-approval path

The slice-2 review routed `absent` to the deferred arm to recover `$out`, and
flagged the residual wording. Three of that message's four claims are false
there, not one: the commit **did** run, the approved summary is **not**
preserved, and no later batch repeats the step — `$msgfile` is removed at
`resolve-sync-memory.sh:245`, before the `HEAD:live` fast-forward whose three
`return 1` arms are the only way to reach it. The user channel says "memory
commit deferred, will retry automatically" after a commit that landed.

Taken as an in-scope wording fix, as the dispatch allowed, by splitting a third
arm rather than softening the shared text. The branch now tests the fact
directly — the summary was present and non-blank before the run, so its absence
now *is* "the commit landed and a step after it failed" — and the freshness call
that follows can only answer `yes`/`no`, which removes the `absent` reasoning
from the code entirely:

```sh
if [ ! -s "$msgfile" ]; then                                        # consumed
elif [ "$(gitlore_commit_msg_freshness "$mempath")" = "no" ]; then  # stale
else                                                                # still covers
```

New arm, acts only, trigger unnamed:

```
gitlore: memory committed, but the step after it did not finish. $out
gitlore: the memory commit landed, and its approved summary has been consumed — nothing is waiting on approval and the commit will not be made again. Act on the reason below. Reason: $out
```

`$out` still carries the prepared-merge directive on the divergence arm, which
was the whole point of the slice-2 fix.

**The `yes` arm and the re-approval arm keep their exact text** — byte-compared
against `HEAD`, the only difference is that the deferred arm moved from first to
last in reading order. The locked-repo and fix-needed tests are untouched, as is
the `systemMessage` pinned byte-for-byte against `design.md:65`.

`fresh=$(…) || fresh=absent` is gone with the arm it served. The substitution now
sits inside the test, which is *safer* than the assignment it replaces: an
assignment whose last command returns non-zero aborts the hook under `set -e` and
emits nothing, while a test's own status governs. Probed both ways; the comment
records it so nobody hardens it back into an assignment.

### 3. MINOR — the two new arms were unguarded

Both fixes above would have passed the suite as committed. Added:

- `tests/commit_memory_approval.bats` — a blank file on the bare path, and `-m`
  with a blank summary, each asserting the entry point's own wording and *not*
  `empty commit message`.
- `tests/cc_hook_memory_commit_batch.bats` — a blank approval through the hook
  (asserts the pending-summary directive, and not `no action is needed from
  you`); and on the existing landed-then-failed test, three assertions that
  discriminate the new arm from the other two: `the memory commit landed`, not
  `retries by itself`, not `approved summary preserved`.

### 4. MINOR — `tests/commit_memory.bats` was parked one line under the cap

At 399/400 before this pass, so any addition blocks `check-docs-links.py`
(`oversized-file`, D55). Split rather than crammed, per the convention: the
approval-screen group — the no-summary refusal, the three bare-mode tests and
the two new blank ones — moved whole into `tests/commit_memory_approval.bats`
(128 lines), leaving `commit_memory.bats` at 320 with a pointer in its header.
The new suite is picked up by `just test-unit`'s `tests/*.bats` glob (verified by
running the glob), and its mode matches its four `commit_memory_*` siblings.

## Mutation checks

Each fix reverted in place, suite re-run, edit inverted and `git diff` confirmed
empty. Every mutation reds on exactly the intended assertion and nothing else.

| Mutation | Result |
|---|---|
| hook screen back to `[ ! -s "$msgfile" ]` | `not ok 8 a blank approval file …` on `no approved summary exists yet` — 13 passed, 1 failed |
| landed-then-failed arm made unreachable (`if false`), reproducing the `!= "no"` routing | `not ok 7 a commit that landed but could not advance live …` on `the memory commit landed` — 13 passed, 1 failed |
| `commit-memory.sh` screen back to `-s` | `not ok 9 … refuses a blank approval file` and `not ok 10 -m with a blank summary …` — 19 passed, 2 failed |

## Checked, sound

- **D16 for `-m` / `-F -`.** Both write `$msgfile` exactly as before; only a
  blank summary behaves differently, and it now refuses with the entry point's
  own directive instead of git's abort. `gitlore.commitCommand` is the script
  path with no operand baked in (`session-start.sh:105`,
  `install/write-settings.sh:38`), so the handoff plugin's `-F -` path is
  untouched. The heredoc test passes unchanged.
- **The hook's bare invocation.** `out=$(bash …/commit-memory.sh 2>&1)` sits in a
  tested context, so `set -e` cannot abort on it; the script clears the git
  local-env-var set itself and inherits the hook's `gitlore_cd_project_root`
  cwd and `CLAUDE_PLUGIN_ROOT`.
- **IPC recovery, path by path.** Success removes both. Every pre-commit failure
  leaves both, and freshness decides the message. A consumed approval leaves the
  trigger, which the next batch clears once memory is clean. The screened
  blank/absent branch keeps the trigger so the commit completes when the summary
  lands. No path now leaves a state the next batch cannot move off, given the two
  flagged below.
- **Comments.** Rewrote the block above the run: the twelve-line `absent`
  rationale is replaced by three one-line arm headers stating what each state
  *is*, plus the `set -e` constraint a maintainer needs in order not to re-break
  arm selection. The `-s`-vs-blank reason is stated once per script because the
  two predicates must move together and `scripts/lib/` is out of scope. Dropped
  "refusing up front only when there is none to judge" from
  `commit-memory.sh`'s header block — false once the screen covers `-m`.
- **Slice-1 residual, still true.** No mutation of `commit-memory.sh` isolates
  the stale test's `[ ! "$msgfile" -nt … ]` restamp guard; any restamp on that
  path also flips the status. Belt-and-braces, left as is.
- **Both slice reviews' "unfixable here" items are closed** by `0cce041` and
  `6790195` — the empty-file test and the landed-then-failed test both exist and
  both discriminate (mutation table above).
- **`tests/bsd_portability.bats`** needs no new lock-in: `grep -q` with
  `[[:space:]]` is POSIX, and `touch -t` was already in use.

## Flagged, not fixed

1. **Design change to record (Phase 2).** The hook now emits **three** failure
   messages, not the two in `design.md` §Design point 3, and the third is
   selected by the IPC file rather than by freshness. Point 3's "`no` means …
   and the hook emits its own message" still holds; what it lacks is the
   consumed-approval state. `docs/references/commit-gate.md`'s "Both IPC files
   are removed only on a complete commit" paragraph is the place this lands.
2. **DEFECT, pre-existing, out of scope — a prepared merge is met with a request
   for approval.** After the landed-then-failed merge arm, the next batch finds
   memory dirty and `$msgfile` absent, so the hook's screen fires *ahead of* the
   run and `gitlore_sync_memory_to_live`'s stale-merge guard is never reached.
   Probed: batch 2 emits "no approved summary exists yet … Summarize the pending
   memory changes … get their approval" in front of a merge `/gitlore:resolve`
   owns. Unchanged by this item — the screen preceded the run before it too.
3. **MINOR, pre-existing — the clean-memory branch overstates itself.** It
   removes only the trigger, then says "Both IPC files are gone. Do not check for
   them." A `$msgfile` surviving a discarded memory edit is left on disk against
   that claim. Harmless (the freshness gate refuses it later), but the sentence
   is false.
4. **The blank-approval predicate is duplicated across the two scripts.** A
   `gitlore_approval_present` in `scripts/lib/util.sh` is its right home;
   `scripts/lib/*` is scoped out here, so both copies carry a comment naming the
   other.

## Runs

- `bash scripts/run-bats.sh tests/commit_memory.bats
  tests/commit_memory_approval.bats tests/cc_hook_memory_commit_batch.bats
  tests/commit_memory_retry.bats` — 43 passed, 0 failed.
- `bash scripts/run-bats.sh tests/plugin_distribution.bats` — 15 passed, 0
  failed.
- `just lint` — `lint-shell: 211 files clean`.
- `python3 scripts/check-docs-links.py` — 0 in every category, `oversized-file`
  back to 0.
- `just test-unit` — `0 suites cached, 95 run — 1024 passed, 0 failed`. The
  suite count moving 94 → 95 is the discovery check: `just test-unit` reaches
  `commit_memory_approval.bats`, not just `run-bats.sh` pointed at it by hand.

`just precommit` was not run, per the dispatch. `test-integration`,
`check-memory-hygiene.py` and `check-version` were not exercised; nothing in
this pass touches their inputs beyond the two scripts, which `test-integration`
does read.
