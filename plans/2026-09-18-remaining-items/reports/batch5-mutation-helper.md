# Batch 5 — the mutation helper, and the F2 review-fix pins

Both items landed. Everything is uncommitted; the two new files are staged (`git add`, no commit) because `scripts/lint-shell.sh` and the distribution suite discover by `git ls-files`, and an untracked file is invisible to both.

## Item 1 — `scripts/mutate-and-run.sh`

### Files

- `/Users/david/code/gitlore/scripts/mutate-and-run.sh` (new, 0755, staged)
- `/Users/david/code/gitlore/tests/mutate_and_run.bats` (new, staged)
- `/Users/david/code/gitlore/docs/references/testing.md` — new section "Proving a test discriminates"

### Interface, and the one change from the brief

`mutate-and-run.sh <file> <sed-script> <bats-file> [<filter>]`. The mutation is a **sed script**, not a patch file. Reasons: a unified diff pins line numbers and context, so a mutation written against one revision stops applying at the next edit, and hand-writing one is where the errors go; a sed script is the thing a report quotes as the mutation's name (`s/exit 1/exit 0/` reads as a mutation, a diff path does not). The brief's two failure modes both survive the substitution — a script that will not parse is refused ("the sed script failed"), and a script that matches nothing is refused as an empty mutation, which is the brief's own central defect (an unmutated run read as a mutant result). Every mutation this batch needed was expressible, including two-line ones via a `/addr/{n; s/…/…/;}` range.

### Behaviour

Refuses (exit 2): wrong argument count, missing file or suite, a stale backup from a crashed run, an untracked subject, a subject with staged or unstaged changes, an unparseable sed script, an empty mutation, a filter that selected no test, a restore that did not come back byte for byte. Reports **KILLED** (exit 0) when the suite went red, printing the `not ok` lines; **SURVIVED** (exit 1) when it stayed green. Codes documented in the header and in `testing.md`.

Design choices worth naming:

- **Backup under the gitdir**, `git rev-parse --git-path gitlore/mutate`, never `$TMPDIR` (unset when the sandbox is off, so `$TMPDIR/foo` becomes `/foo`) and never beside the subject, where a suite's own discovery would reach it. It is written aside as `subject.bak.part` and `mv`d into place, so a signal mid-copy cannot leave a half backup for the trap to restore from.
- **Restore is `cat "$backup" > "$subject"`**, not `mv`: it rewrites the subject's own bytes, so mode and inode survive. (Which is the same mechanism Item 2's `cp -p` pin is about.)
- **The stale-backup check runs *before* the dirtiness check.** Found by a red: a crashed run leaves the subject holding its mutant, i.e. dirty, so the dirty refusal fired first and told the caller to "commit or revert", which would have discarded the only copy of the original. Reordered so the backup explains the dirtiness and the refusal prints the restoring command.
- **`$here/run-bats.sh`**, resolved beside the script, not `$root/scripts/run-bats.sh`: a subject in another repository still gets gitlore's failure-only output, and the fixture repo needs no copy of the runner.
- **The zero-test guard.** A filter selecting nothing leaves bats green over zero tests, which reads exactly like a survival. The count is parsed back from `run-bats.sh`'s own `bats: N passed, M failed` line.
- **Placement.** `scripts/`, beside `run-bats.sh`, `lint-shell.sh` and the two `check-*.py` — that is where this repo keeps dev-only tooling, and a `.sh` extension on a tracked path is what puts it in `lint-shell.sh`'s discovery set (no change to that script was needed). It is inside `distribution_inputs`' `scripts` pathspec, like its neighbours; `tests/plugin_distribution.bats` enumerates nothing under `scripts/`, so the distribution check neither breaks nor grows — editing the tool re-runs that gate's 2 s, same as editing `run-bats.sh`.

### Red evidence

The suite's own tests were proved by mutation, **by hand rather than with the helper**: the helper cannot be pointed at itself, because the outer run holds the file open while bash is still reading it, and a length-changing mutation would corrupt the running shell. Same protocol otherwise (backup under the gitdir, restore, `git diff --quiet` after each). The driver ran 9 mutations over `tests/mutate_and_run.bats`:

| Mutation | Verdict | Test that died / failing line |
|---|---|---|
| `if [ -e "$backup" ]` → `if false` | KILLED | "a backup left by a crashed run refuses the next one…" — `[[ "$output" == *"previous run left a backup"* ]]` |
| `cmp -s "$mutant" "$subject" && {` → `false && {` | KILLED | "a mutation that changes nothing is refused as empty" — `[ "$status" -eq 2 ]` |
| `[ "$((passed + failed))" -gt 0 ]` → `-ge 0` | KILLED | "a filter narrows the run, and one that selects no test is refused" — `[ "$status" -eq 2 ]` |
| dirty-subject `if` → `if false` | KILLED | "a subject with uncommitted changes is refused, staged or not" — `[ "$status" -eq 2 ]` |
| `git ls-files --error-unmatch` → `true git ls-files …` | KILLED | "an untracked subject is refused…" — `[ "$status" -eq 2 ]` |
| `trap 'restore_subject; exit 2' HUP INT TERM` → `trap -` | KILLED | "a signal during the run restores the subject and exits refused" — `[ "${status:-0}" -eq 2 ]` |
| `if [ "$suite_status" -ne 0 ]` → `-eq 0` | KILLED | KILLED / SURVIVED / filter tests, 3 of 11 |
| `trap 'restore_subject' EXIT` → `trap - EXIT` | **SURVIVED** | see below |
| restore-verification message arm → `:` | **SURVIVED** | see below |

The two survivors are both safety nets with no inducible failure, and I left them in rather than deleting them or writing a test that fakes one:

- **The EXIT trap.** Every ordinary exit after the mutation lands goes through the explicit `restore_subject` call (the verification has to run after the restore and before the verdict), and the signal path restores in its own `HUP INT TERM` trap. The EXIT trap therefore only covers an errexit abort between the two — a class no current line can reach. It is one line and it is what makes a future early `exit` safe.
- **The post-restore `git diff --quiet` verification.** Nothing in the suite can make the restore fail, so only its message arm is mutable, and no test sees it. It is the assertion that the whole tool exists to be trusted on.

### Suites run

`tests/mutate_and_run.bats` — 11 passed, 0 failed.

### Awkward in use (dogfood, Item 2)

- **The subject's index entry is the baseline, not HEAD.** The first self-mutation run aborted with `RESTORE FAILED` because I had `git add`ed the helper before making further edits: the restore was correct and the check compared the restored worktree against a stale index. That is the helper's rule working as designed (it refuses a subject with staged *or* unstaged changes), but the driver I wrote by hand did not, and it is the trap a caller will hit. The refusal message already says "commit or revert them first"; nothing changed.
- **Quoting a sed script through a shell into a report.** The two-line mutations needed `/addr/{n; s/…/…/;}` and the `$` and `|` in them have to survive single quotes. It works, but the verdict line echoes the script back verbatim, which is long. I kept it: the alternative is a verdict that does not say what was mutated.
- Nothing else. Seven of the eight Item 2 mutations ran first try.

## Item 2 — the F2 pins

No production behaviour changed. `git diff` touches only the three suites.

### (a) A failed `git status` in the commit path's rc 1 arm restamps and aborts

- **Site**: `scripts/lib/resolve.sh` — the tier arm of `gitlore_sync_memory_to_live`'s rc-1 case, `index_status=$(git -C "$mempath/$tier" status --porcelain -- MEMORY.md) || { touch "$msgfile"; return 1; }`.
- **Test**: `tests/commit_memory.bats`, "a tier whose index status cannot be read aborts the commit and restamps the approval", placed with the other rc-1 abort cases.
- **The reviewer's suggested induction does not work, and the test says so.** A tier `.git` gitfile pointing nowhere was tried first: compose still returns rc 1 with the right problem line (verified: `composerc=1`, `memory/ddaanet/MEMORY.md: duplicate pointer path shared.md`), but `gitlore_memory_dirty`'s own `git -C memory status --porcelain` fails on the broken submodule long before the arm is reached, and the whole run exits **0** with a bare `fatal: not a git repository` on stderr. Every other way of breaking the tier's gitdir fails that same earlier read. The test therefore stands a `git()` function in through `write_sync_driver`'s existing escape hatch — the suite's own documented mechanism "to stand a function in for a state no fixture reaches", already used by "an unrecognised compose status aborts and keeps the approval" — failing only `git -C memory/ddaanet status …` and forwarding everything else to `command git`.
- **Red evidence**, both halves, via `scripts/mutate-and-run.sh`:

| Mutation | Verdict | Failing line |
|---|---|---|
| tier arm `\|\| { touch "$msgfile"; return 1; }` → `\|\| index_status=""` (fail open) | KILLED | `[ "$status" -eq 1 ]` |
| tier arm `\|\| { touch "$msgfile"; return 1; }` → `\|\| return 1` (abort, no restamp) | KILLED | `[ "$msgfile" -nt "$TMP_REPO/before-run" ]` |

- **Flagged, not fixed**: this arm aborts **silently**. It returns 1 with nothing printed — not the refusal it had already built, not a reason. A user gets a commit that fails with no explanation. The test pins exit 1, no commit, the restamp, and that *neither* rc-1 arm's sentence was printed; it does not assert the silence, so fixing that later costs one assertion. Changing it is a production behaviour change and was out of scope here.

### (b) `gitlore_repair_index` keeps the file mode

- **Site**: `scripts/lib/index-compose.sh`, `cp -p -- "$file" "$scratch"` (mktemp creates 0600; the copy carries the mode across the rename).
- **Test**: `tests/index_compose.bats`, "a repaired index keeps the file's mode", at the end of the repair block beside "a rewrite that cannot be written leaves the file unchanged". A `file_mode` helper reads the bits portably (`stat -c '%a'`, falling back to BSD `stat -f '%Lp'`), defined after its user, as `write_sync_driver` is.
- **Red**: `cp -p -- …` → `cp -- …` ⇒ KILLED, on `[ "$(file_mode file.md)" = 640 ]`.

### (c) `hash-object --no-filters` keeps CRLF bytes

- **Site**: `scripts/lib/resolve.sh`, `gitlore_adopt_commit_repair`'s `git -C "$tierpath" hash-object -w --no-filters -- "$scratch/arrival"`.
- **Test**: `tests/merge_memory.bats`, "a repair keeps the arrival's CRLF bytes", right after "a take repairs a duplicate pointer that arrived and adopts the repair". The tier sets `core.autocrlf=input` — clean filter on the way into the object database, no smudge on checkout, so the hash is the only thing under test and the rest of the take is undisturbed. The arrival carries two CRs (premise asserted against the bare remote), the repair drops one duplicate, and the committed blob must still hold one.
- **Red**: `hash-object -w --no-filters --` → `hash-object -w --` ⇒ KILLED, on the CR count of the repaired blob.

### (d) A refused `push .` mutation for Item 2.2 slice 6

No new test — the behaviour is already covered by `tests/merge_memory.bats` "a repair whose live advance fails walks back and keeps the arrival"; what the audit asked for is the missing red. Two mutations, both against `gitlore_adopt_repair_arrival`:

| Mutation | Verdict | Failing line |
|---|---|---|
| `if ! err=$(gitlore_git … push -q . "$repair:refs/heads/live" 2>&1); then` → capture the status, `\|\| true`, `if false; then` (the audit's "ignore the push status and continue") | KILLED | `[[ "$stderr" == *"shim refuses the third live advance"* ]]` |
| the arm's `gitlore_adopt_report_refusal_and_walk_back …` line → `:` | KILLED | `[[ "$stderr" == *"gitlore: the root index could not take tier 'ddaanet''s lines:"…* ]]` |

The first is the audit's own mutation and reds on the arm's message forwarding; the second was added because bats stops at the first failing assertion, so the first mutation alone says nothing about whether the walk-back is pinned. It is.

## Suites run, in the foreground, one at a time

| Suite | Result |
|---|---|
| `tests/mutate_and_run.bats` | 11 passed, 0 failed |
| `tests/commit_memory.bats` | 37 passed, 0 failed |
| `tests/index_compose.bats` | 85 passed, 0 failed |
| `tests/merge_memory.bats` | 42 passed, 0 failed |
| `tests/plugin_distribution.bats` | 15 passed, 0 failed |
| `tests/lint_shell.bats` | 3 passed, 0 failed |
| `tests/bsd_portability.bats` | 3 passed, 0 failed |
| `tests/justfile_gates.bats` | 25 passed, 0 failed (not asked for; run because the batch adds a suite, and this is what proves `test-unit`'s glob reaches it) |

Also run: `scripts/lint-shell.sh` over the real repo — **140 files clean**. It caught one thing the per-file `shellcheck -x` runs did not, because I had not run one on `commit_memory.bats`: SC2016 on the driver text passed to `write_sync_driver`. Fixed with an inline `# shellcheck disable=SC2016` naming the reason, not a file-level blanket. `just format-docs` (2 fixes in 1 file) and `python3 scripts/check-docs-links.py` (0 of every category, 121 files) both pass.

`just precommit`, `just test-unit` and `just test-integration` were not run, per the dispatch. No gate sentinel was written by this batch.

## Not done

- **No test kills the EXIT trap or the restore verification** in `mutate-and-run.sh`. Both are unreachable-failure guards; detail above.
- **The silent abort in (a)** is reported, not fixed.
- Nothing under `memory/` or `.claude/` was touched. No branch, worktree, commit, push, `checkout --`, `stash` or `restore`.
