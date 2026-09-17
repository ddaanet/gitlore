# Item 2.1 / Slice 2 — test review

Scope: the uncommitted test "a behind arm's repair survives a later tier's
failure" in `tests/push_behind_vs_diverged.bats`, and its helper.

## Verdict

One MAJOR finding and three minor ones, all fixed in the test. The test is red
on the intended assertion. It goes green for the in-arm push and for no
lookalike fix that was tried.

## Findings

### MAJOR — fixed: the test went green for a fix that only reruns the pass on failure

**Reproduced.** The scratch copy used `git archive HEAD` plus the working-tree
test file. `gitlore_push_stores` was mutated so the loop's tier-push failure
`break`s instead of returning, the post-loop pass runs, and the function then
returns 1. Result with the test as submitted: `1 passed, 0 failed`. The pass
pushes `aa` (first in order) before it fails again on `bb`, so `aa`'s remote
ends on the repair. The final-state assertion cannot tell that fix from the
in-arm push. The spec's behaviour is narrower: the repair "is out before a later
tier's failure returns 1 from the loop".

**Fix.** `decline_pushes_to` is replaced by
`decline_tier_pushes_recording bb aa <file>`. It installs `bb`'s declining
`pre-receive` hook, which first appends `aa`'s remote `live` to
`$BATS_TEST_TMPDIR/aa-remote-at-bb-push`. It unsets the quarantine variables, as
`install_tier_live_snapshot_hook` does. The test then asserts:

- the hook ran (`[ -s "$snapfile" ]`), as a precondition;
- `aa`'s remote `live` equals the repair (unchanged, still the red on the
  current code);
- after that, the first snapshot line equals the repair, so the repair was
  published by the time `bb`'s loop push was tried.

The rewrite also removes the duplication: the old helper was a verbatim copy of
`tests/resolve_compose.bats:520-524`. The new helper does a different job, so
nothing is left to share.

### Minor — fixed: `bb`'s refusal was not proven to come from the hook

The "failed, and not because of divergence" line comes from the `*)` arm, which
catches any error that is not a divergence. The test now also asserts
`declined by policy` (the hook's stderr, relayed in `git said:`) and the
non-empty snapshot. Together these show the refusal came from the `pre-receive`
hook and was not a non-fast-forward. The push error has neither `(fetch first)`
nor `(non-fast-forward)`, so it takes the outer `*)` arm and returns 1 from the
loop.

### Minor — fixed: the precondition mutated the fixture

`git -C memory/aa fetch -q origin live` ran before the command under test, which
moved `aa`'s `origin/live` ahead of the push's own fetch. The behind check now
reads the bare remote directly: its `live` is the fact, and `aa_live_before` is
an ancestor of it. The command starts from the state `mount_tier_at_live`
leaves.

### Minor — fixed: comments cited a line number and described a defect

- The header cited `:376`. It now names the test "a repair taken by the behind
  arm is published before memory records it".
- The closing comment said "The defect: … stuck …". That goes stale at green, so
  it now states in the present tense what the assertions pin.

### Note — out of scope, not edited

`setup_repair_race_on_aa`'s comment (slice 1, committed) also cites `:376`.

## Checks

1. **Mechanical.** `scripts/run-bats.sh tests/push_behind_vs_diverged.bats` in
   the working tree gives `17 passed, 1 failed`. It fails on the assertion at
   `tests/push_behind_vs_diverged.bats` line 642:
   `[ "$(git --git-dir="$TMP_REPO/.bare-aa.git" rev-parse live)" = "$aa_live" ]`.
   That is an assertion failure, not an error.
2. **Right reason.** Every precondition runs before :642 and passes:
   - `aa` is behind (local `live` ≠ the fact, the remote's `live` is the fact,
     and ancestry holds);
   - exit 1;
   - `bb`'s non-divergence line, `declined by policy`, and a non-empty snapshot;
   - the in-push repair message for `aa`;
   - the repair ≠ the fact, its sole parent is the fact, and the bullet appears
     once.

   The snapshot assertion (:643) comes after the red and is not needed for it.
   It exists only to reject the lookalike fix.
3. **Right failure.** `bb`'s refusal is the hook's policy decline (see above).
   Only `aa`'s behind arm sets `GITLORE_TAKE_IN_PUSH` here: `aa` starts with
   `live` = HEAD, and `bb`'s `live` = HEAD. So the repair message proves the
   repair came from `aa`'s own take, and nothing else pushes `aa` before `bb`.
4. **Green only for the intended fix.** Scratch copy under
   `/tmp/claude-1000/probe.*`, removed afterwards. Afterwards
   `git status --short scripts tests` shows only this test file.
   - The in-arm push was restored after the behind arm's
     `GITLORE_TAKE_IN_PUSH=1 gitlore_merge_stores`, using
     `merge-base --is-ancestor live origin/live` and then the push with its
     failure message. The whole file gave `18 passed, 0 failed`, with no test
     edit.
   - The pass-rerun mutant gave `0 passed, 1 failed`, at :643
     `[ "$(sed -n 1p "$snapfile")" = "$aa_live" ]`.
5. **Hygiene.**
   - `shellcheck -x` is clean.
   - The helper follows the style of `install_tier_live_snapshot_hook`: an
     unquoted heredoc expanded at install time, quoted paths inside the hook,
     and `|| return 1` on the write.
   - The snapshot file lives under `$BATS_TEST_TMPDIR`.
   - No `set -e` reliance inside command substitutions.
     `aa_fact=$(push_tier_fact …)` is checked by the ancestry and equality
     assertions that follow.
   - The code uses no bash 4 constructs and no GNU-only flags (`sed -n 1p`).
