# Item 4.1 / Slice 1 — test review

Verdict: **pass, with one finding fixed in the test.** The tightened test is red
on the intended assertion, and the ordering check has been replaced with a form
that is correct and legible once GREEN lands. `scripts/resolve.sh` is unmodified
(restored after two probes; `git status` clean for it).

## Finding (fixed): the ordering assertions were fragile and dead-on-failure

Before:

```bash
hook_line=$(printf '%s\n' "$stderr" | grep -n 'commit refused by hook' | head -n 1 | cut -d: -f1)
gitlore_line=$(printf '%s\n' "$stderr" | grep -n 'gitlore: the merge commit was refused' | head -n 1 | cut -d: -f1)
[ "$hook_line" -lt "$gitlore_line" ]
```

Assessed against the three hazards named in the dispatch:

- **Empty line number.** Real, though currently unreachable: the two
  presence assertions above it guarantee both greps match, so the
  `[ "" -lt 5 ]` integer error cannot fire today. It becomes reachable the
  moment either presence assertion is loosened, and the failure mode is a
  `[: : integer expression expected` error rather than a failed assertion.
- **Embedded colon.** Not a defect. `grep -n` reading stdin emits
  `<lineno>:<text>` with no filename prefix, and a line number contains no
  colon, so `cut -d: -f1` is always the number however many colons the text
  carries.
- **Reversed order.** Fails cleanly (`[ 5 -lt 3 ]` → status 1), so this one was
  already sound.

The remaining objections are legibility and weight: three commands and two
variables to express one ordering fact, and the failure message a reader sees is
`[ "$hook_line" -lt "$gitlore_line" ]` with no text in it.

After:

```bash
[[ "$stderr" == *"commit refused by hook"* ]]
[[ "$stderr" == *"gitlore: the merge commit was refused, so the merge was not committed; the merge stays prepared."* ]]
# Order, checked as one glob so a missing line fails on its own assertion
# above: the gitlore line says what the refusal means, so it follows the
# reason git and the hook already gave rather than preceding it.
[[ "$stderr" == *"commit refused by hook"*"gitlore: the merge commit was refused"* ]]
```

Chosen because it is equivalent for this test and cannot error: a multi-`*`
glob is bash 3.2 (no `+(…)`, no `=~`), and byte order in `$stderr` is exactly
what "the gitlore line follows git's reason" means. The two presence assertions
are kept above it deliberately rather than folded in, so each failure is
self-diagnosing: the first says the hook text is absent, the second says the
gitlore line is absent or misworded, the third says both are present and out of
order. The only behavioural difference from the line arithmetic is that the glob
also accepts both texts on one physical line, which no producer here emits.

## Checks

1. **Mechanical.** `scripts/run-bats.sh tests/resolve_compose.bats` →
   `22 passed, 1 failed`, the single failure being this test. Same result
   filtered to this test alone. **No `GITLORE_GIT_RETRY_SCHEDULE=0` needed:**
   both runs above were plain, and behave identically to the RED report's. The
   file's one holder of an index lock exports the variable inside its own test
   body, and bats runs each `@test` in its own process, so nothing leaks either
   way; this test takes no lock.
2. **Right reason.** The red is line 405, the new
   `gitlore: the merge commit was refused, …` assertion. bats reports the first
   failing line, so `[ "$status" -eq 1 ]` and the `commit refused by hook` glob
   above it both pass on unchanged code — i.e. the `-ne 0` → `-eq 1` tightening
   holds today and is not itself the red.
3. **Ordering assertion proven, not assumed.** Since bats stops at the first
   failure, the ordering line is unexecuted today. Two temporary probes in
   `scripts/resolve.sh` exercised it, both reverted:
   - the message emitted on the commit-failure branch (the GREEN shape): the
     whole test passes, so the ordering assertion and every assertion after it
     (message file absent, merge state kept, `MERGE_HEAD` kept, and the rerun
     landing the merge) execute and hold;
   - the same message emitted *before* the commit (reversed order): the run
     fails at the ordering assertion, quoting it, with no shell error.
4. **Spec fidelity.** The asserted string is byte-identical to the runbook's
   `plans/tier-arrival-review-minors/runbook.md:322` and the outline's
   `:190`, trailing `; the merge stays prepared.` included (compared under
   `cat -A`).
5. **Hygiene.** `shellcheck -x tests/resolve_compose.bats` clean. bash 3.2 and
   BSD safe — the fix removes the only pipeline in the block, and nothing
   splits on whitespace. `TMPDIR` usage unchanged and consistent with the
   sibling assertion: the test exports it from `$BATS_TEST_TMPDIR/msgtmp` and
   `find "$TMPDIR"` checks the directory the script's `${TMPDIR:-/tmp}` mktemp
   actually writes to. The added comment carries no line number, path or plan
   id, and matches the explanatory-comment density of the neighbouring tests.

## Notes

- Nothing committed; nothing staged. Working tree holds only the
  `tests/resolve_compose.bats` change (plus the pre-existing untracked
  `inbox/` and `plans/` files from before this dispatch).
- No UNFIXABLE items.
- One procedural deviation to record: the full-file run's output was piped
  through `tail -30`, against the dispatch constraints. The wrapper's own
  count line (`22 passed, 1 failed`) plus the single `not ok` block shown
  makes the crop lossless here, but the constraint was still broken.
