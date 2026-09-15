# Item 4.1 — test review

Scope: the four new tests at the end of `tests/resolve_compose.bats`. `scripts/`
read only; left byte-identical (`cmp` against the saved copy,
`git diff --quiet -- scripts/`).

## Verdict

Red/green pattern holds after fixes. One lint blocker fixed; several
wrong-reason gaps tightened. Nothing unfixable.

## Findings and fixes

1. **Lint blocker (major).** `shellcheck -x tests/resolve_compose.bats` exited
   1: SC2030/SC2031 infos on the three `export GITLORE_GIT_RETRY_SCHEDULE=0`.
   `scripts/lint-shell.sh` runs `shellcheck -x` at default severity, where infos
   fail the run. HEAD passed only because its single export triggered neither
   code. Fixed with the file-level `# shellcheck disable=SC2030,SC2031` plus the
   rationale comment that `lib_util.bats`, `resolve_recovery.bats` and five
   other suites carry. shellcheck is now clean.
2. **Slice 1: merge identity.** It checked only that tier `live` was *a* merge.
   It now captures `HEAD` (ours) and `MERGE_HEAD` (theirs) before the run and
   asserts `live^1`/`live^2` equal them. That identifies the commit the
   continuation built. It also asserts the bare remote's `live` is unchanged, so
   the decline really happened.
3. **Slice 2: HEAD and the refused push.** HEAD was checked only as "is a
   merge". It now asserts `HEAD^1`/`HEAD^2` = ours/theirs, stderr contains
   `live.lock`, and tier `live` equals its pre-run value, which proves the local
   push is what the lock refused.
4. **Slice 2: remedy text.** The substring checks accepted a truncated sha
   followed by anything, and didn't pin line order or the header. The test now
   matches one glob of four consecutive lines, exactly as in the Interfaces
   text. That takes in the header naming `ddaanet`, both commands with the
   quoted `$abs`, and the full `$pin` terminated by a newline.
5. **Slice 3: no check that the remedy did anything.** The test could pass as
   long as the take succeeded afterwards. It now captures `merged` (tier HEAD
   after the continuation) and asserts, after the two commands, that `live` =
   `merged` and HEAD = `$pin`. The final `HEAD:ddaanet` check is against that
   independently captured `merged`, not a re-read of `live`.
6. **Slice 3: line attribution.** The commands ran inside `( cd … && … )`, and
   on failure bats pointed at the previous line (`${#remedy[@]}`). They are now
   plain statements: `cd "$BATS_TEST_TMPDIR"`, the two `bash -c`, then
   `cd "$TMP_REPO"`. A failure now names the `bash -c` line. The redundant
   `|| [ -n "$line" ]` is gone, since `printf '%s\n'` always terminates.
7. **Slice 4: fixture and hook.** It now asserts that the memory-remote hook ran
   (`declined by policy`) and that the setup really leaves local `live` strictly
   ahead of `origin/live` (`merge-base --is-ancestor` plus inequality), which is
   the precondition for reaching the `*)` arm.
8. The pre-receive heredoc used in slices 1 and 4 moved into a
   `decline_pushes_to <bare>` helper, defined above slice 1 like the file's
   other helpers.

Checked and fine: the lock sits in the tier's own gitdir
(`rev-parse --absolute-git-dir`) and is removed right after `run`, before any
assertion. `GITLORE_GIT_RETRY_SCHEDULE=0` is exported wherever the lock is held.
All stderr assertions use `run --separate-stderr`. There is no bare `! cmd`.
Extraction reads NUL-free line by line with `IFS= read -r`. The `sed -i.bak`
form is BSD-safe. No plan, item or slice citations in the test source.

## Evidence

All runs used `TMPDIR="/tmp/claude/sp ace"`, so `TMP_REPO` contained a space.
The sandbox's `$TMPDIR` was empty, so a spaced dir under the writable
`/tmp/claude` was set explicitly.

**Original code, whole file:** `18 passed, 3 failed`.
- Slice 1 fails at line 523, HEAD = `$pin`.
- Slice 2 fails at line 549, the remedy glob. Its `live.lock`, `live`-unchanged
  and parent assertions already pass.
- Slice 3 fails at line 569, `${#remedy[@]} -eq 2` (cascade).
- Slice 4 passes, including its new live-ahead precondition.

**Green sketch** (applied in place, then restored):
- `push_or_report` returns 2.
- The continuation's two callers use `rc=0; … || rc=$?`; on 2 they run
  `rest_unadopted_tier` if `tier_unadopted` is set, then exit 1.
- `check_store_gates` exits 1 on 2 at both pushes.
- The rest guard (`rev-parse -q --verify live` and
  `merge-base --is-ancestor HEAD live`) prints the four exact lines.

Results: four tests `4 passed, 0 failed`; whole file `21 passed, 0 failed`.

**Mutations of the sketch** (each red, for the stated reason):

| Mutation | Test | Red at |
|---|---|---|
| remedy checks out `$merged` instead of `$pin` | slice 3 | line 573 HEAD = `$pin` |
| remedy `git -C $abs` unquoted | slice 3 | line 572 `bash -c` status 128, `cannot change to '/tmp/claude/sp'` |
| remedy uses relative `$tierpath` | slice 3 | `bash -c` status 128, `cannot change to 'memory/ddaanet'` (from `$BATS_TEST_TMPDIR`) |
| rest guard dropped (checkout at pin although `live` lacks HEAD) | slice 2 | line 543 `HEAD^1` = ours; slice 3 cascades |
| `check_store_gates` origin push treats 2 like 1 | slice 4 | line 601 `!= *"refused as a non-fast-forward"*` |
| continuation origin-push 2 exits without resting | slice 1 | line 523 HEAD = `$pin` |

The relative-path mutation ran before finding 6's restructure, so bats pointed
it at line 569. The fatal message confirms the cause.

`shellcheck -x tests/resolve_compose.bats`: clean (exit 0).
