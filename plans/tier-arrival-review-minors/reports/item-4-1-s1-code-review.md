# Item 4.1 / Slice 1 — code review

Verdict: **pass, with one defect found and fixed** — the new `echo` sat ahead of
the `rm -f` inside a brace group where `errexit` is still armed, so a failing
write to stderr skipped the cleanup and leaked the message file. Wording,
ordering, exit state and idiom are otherwise correct.

## Fix applied: cleanup before the emission

`scripts/resolve.sh`, the `continue-after-merge` commit arm:

```bash
      GITLORE_MEMORY_COMMIT=1 gitlore_git -C "$mempath" commit -q -F "$merge_msgfile" \
        || {
          # Removal first: this group is the right-hand side of `||`, where
          # errexit stays armed, so a failing write to stderr here would skip
          # whatever follows it and leave the scratch file behind.
          rm -f "$merge_msgfile"
          echo "gitlore: the merge commit was refused, so the merge was not committed; the merge stays prepared." >&2
          exit 1
        }
```

**The defect.** `set -e` is *not* suspended inside a `{ … }` group used as the
right-hand side of `||` — only inside a *function* invoked there. Measured on
`GNU bash 5.2.37`:

```
$ cat q.sh
set -euo pipefail
g() { echo "in-fn" >&2; echo "FN-AFTER"; return 9; }
false || g || echo "fn-rc=$?"
false || { echo "in-grp" >&2; echo "GRP-AFTER"; }
echo "END"
$ bash q.sh 2>&-
FN-AFTER
fn-rc=9
$ echo $?
1
```

`FN-AFTER` prints — errexit is ignored inside the function body — while
`GRP-AFTER` and `END` never run: the failing `echo … >&2` inside the brace group
terminates the script. A closed or unwritable fd 2 is a *non-fatal* redirection
error (under `set +e` the same group runs to completion and exits 7), so it is
errexit, not the redirection, that skips the rest of the group.

Reproduced on the arm's own shape: with the pre-fix order and fd 2 closed, the
script exits 1 with `MERGE_HEAD`, the merge-state file and the staged content
intact — the exit status happens to be the intended 1, because a failing `echo`
returns 1 too — but `$TMPDIR/gitlore-merge-msg.*` survives, which is exactly the
invariant `tests/resolve_compose.bats:410` pins. With the fix, the same probe
exits 1 with the file removed.

**Reachability, stated as the bound it is:** narrow. Every earlier `gitlore:`
emission on this path is either a bare `echo` under `set -e` or, at
`scripts/resolve.sh:282`, a `printf | sed >&2` pipeline under `pipefail` — so an
fd 2 that is already unwritable when the continuation starts kills it long
before the commit. The live case is stderr becoming unwritable *during* the run
(a filling disk behind a redirected stderr), and the consequence is a leaked
scratch file rather than lost merge state.

**Why reordering rather than `echo … >&2 || true`.** Both work (the `||`
fallback was probed and also reaches the `exit`), but nothing observes whether
the removal preceded the message — the file is this run's scratch and no
consumer reads it — while `|| true` on an `echo` is an idiom the script does not
otherwise use. The reorder also matches the sibling arm one line above,
`… || { rm -f "$merge_msgfile"; exit 1; }`, which already removes first. The fix
is correct under either errexit semantics, so the bash 3.2 target needs no
separate claim: with the removal first, a failing `echo` can only cost the
message, never the cleanup.

## Checks that passed

1. **Wording, byte-exact.** The four copies — `scripts/resolve.sh:319`,
   `plans/tier-arrival-review-minors/runbook.md:322`, `outline.md:190`,
   `tests/resolve_compose.bats:405` — were extracted and `cmp`-ed pairwise:
   identical, trailing `; the merge stays prepared.` and the final period
   included, no trailing whitespace (`cat -A`).
2. **Shared phrase.** `the merge was not committed` matches the merged-index
   gate at `scripts/resolve.sh:136` verbatim, which is what
   `agents/memory-merger.md:38` and `skills/resolve/SKILL.md:68` key on. The two
   lines diverge only after the shared phrase, as the outline specifies
   (`the merge stays prepared.` vs `… prepared for a new synthesis:`).
3. **Directive-free.** Two clauses of state (`was refused`, `was not committed`)
   and one of standing state (`stays prepared`). No imperative, no next command,
   no path or identifier the reader could act on — and no mechanism: it says the
   merge is unlanded without explaining what keeps it prepared. The merger's own
   prose (Phase 6) supplies the act.
4. **Ordering: git's reason always first.** Structural, not incidental.
   `gitlore_git` (`scripts/lib/util.sh:338-356`) captures each attempt's stderr
   into `$errfile` with `2>"$errfile"`, and emits it with `cat "$errfile" >&2`
   *after* the retry loop and *before* `return "$rc"` — so the whole reason is
   on stderr before the `||` handler is entered. Verified live: the slice test's
   ordering glob at `:409` passes, and a mutation that emits the gitlore line
   ahead of the `commit` call fails on that exact line (see Mutation below).
5. **Ordering under retry.** A hook refusal is not a lock error
   (`gitlore_git_is_lock_error` matches none of `commit refused by hook`), so
   `commit` fails on the first attempt with no retry. Were it a lock error, each
   attempt's `2>"$errfile"` *truncates* the file, so intermediate reasons are
   discarded and only the final attempt's text prints, once, after the loop —
   the gitlore line cannot interleave between attempts, and no reason is printed
   twice.
6. **Ordering when the hook writes to stdout.** `gitlore_git` leaves stdout
   untouched, so a hook printing its reason to fd 1 keeps it out of `$stderr`
   entirely (the test's `run --separate-stderr` would see it in `$output`). On a
   terminal where both fds share the tty, the hook's write still happens while
   `git commit` is running, i.e. before the handler — so the gitlore line never
   precedes the reason on either fd.
7. **State on exit, unchanged.** The arm performs only `rm -f`, `echo` and
   `exit 1`. `MERGE_HEAD`, `gitlore-merge-state` and the staged merge content
   are untouched — the test asserts all three, plus the rerun landing the merge
   once the hook is removed. The 3 added comment lines and the reorder are the
   only deltas; no new way for `rm`/`exit` to be skipped remains (that was the
   defect, now inverted).
8. **Idiom.** The GREEN report's "the script has no say-helper" is wrong:
   `scripts/lib/log.sh` is sourced at `scripts/resolve.sh:19` and
   `gitlore_say_for_agent_or_user` is used six times in the file. Its conclusion
   still holds — the helper exists to branch agent-targeted from user-targeted
   text, and every message on *this* path uses plain `echo "gitlore: …" >&2`:
   the merged-index gate (`:136`), the store-outside-root line (`:265`) and the
   unstaged-gitlink warning (`:338`). A helper call with two identical arguments
   here would add a branch with nothing to branch on. Not a finding; noted
   because the report's stated reason is inaccurate and it is committed in
   `08d4d01`.
9. **bash 3.2 / BSD.** No arrays, no `[[ ]]`, no GNU-only utility; the quoted
   `"$merge_msgfile"` is whitespace-safe and nothing splits on whitespace. The
   added comment carries no path, plan reference or line number, and matches the
   file's explanatory-comment density.
10. **shellcheck.** `shellcheck -x scripts/resolve.sh` clean.

## Mutation run

One mutation, applied in place and restored from a copy (`git diff scripts`
afterwards shows only the fix above):

| Mutation | Expected | Result |
|---|---|---|
| The emission moved ahead of the `gitlore_git … commit` call (presence kept, order reversed) | ordering assertion fails | `not ok … (line 409)` on `[[ "$stderr" == *"commit refused by hook"*"gitlore: the merge commit was refused"* ]]`, `0 passed, 1 failed` |

This re-proves the ordering assertion against the *fixed* code shape; the
test-review's own probes were against the pre-fix shape.

## Not covered by a test

The leak path is not assertable from the suite: reaching the refused commit with
fd 2 unwritable is impossible, because `scripts/resolve.sh:282`'s
`printf | sed >&2` under `pipefail` aborts the continuation first whenever
composition has anything to say. The fix is therefore a guard with a comment
stating why the order matters, not a tested behaviour. Recorded here rather than
left implicit.

## For slice 4.1/2 (not applied — out of scope)

The runbook specifies the build arm as "prints …
**to stderr before removing the message file** and exiting 1", and the
refused-commit line "the same way". That stated order is the shape this review
found defective. The build arm at `scripts/resolve.sh:312-313` currently removes
first and is safe; slice 4.1/2 should keep the removal first and put its new
`echo` after it, matching what landed here. The runbook's ordering prose
describes something no consumer observes, so it can stand as written or be
reworded — an orchestrator call, not an executor's.

## Files changed

- `scripts/resolve.sh` — the commit-arm handler: `rm -f` moved ahead of the
  emission, with a 3-line comment stating the errexit reason.

Nothing committed, nothing staged.

## Bats counts after the fix

| File | Result |
|---|---|
| tests/resolve_compose.bats | 23 passed, 0 failed |
| tests/resolve_recovery.bats | 23 passed, 0 failed |
| tests/resolve_both_flavors.bats | 4 passed, 0 failed |

All runs `GITLORE_GIT_RETRY_SCHEDULE=0 scripts/run-bats.sh <file>`, one file at
a time, in the foreground, output unpiped. `just precommit` not run (the
orchestrator owns it).

No UNFIXABLE items. No design call required for the fix itself; the one item
left to the orchestrator is the runbook ordering prose above.
