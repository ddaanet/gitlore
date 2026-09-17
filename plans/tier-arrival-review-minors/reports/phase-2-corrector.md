# Phase 2 corrector: push publication

Diff reviewed: `e333de6..HEAD` over `scripts/lib/resolve.sh` and
`tests/push_behind_vs_diverged.bats`. There are no critical or major findings.
Three minor findings are fixed, all of them in the test file. One size item is
flagged and not acted on.

## Code: `gitlore_push_stores` and `gitlore_report_tier_push_failure`

No findings. Checked:

- **Behind-arm retry push.** It is back and goes through the reporter. Its
  comment matches the ahead-of-HEAD comment and the pass comment. A repair to a
  finished tier goes to the pass. A repair to a later tier goes out with that
  tier's own push. No comment still describes the slice 2.1/1 shape, where the
  retry was removed.
- **Post-loop pass.** It sits before the memory remote check. Its skip guards
  match the loop's. Pushing when `origin/live` is missing is defensive, and by
  construction nothing reaches it: any tier with a local `live` that gets
  through the loop either pushed successfully, which sets its tracking ref, or
  went through the behind arm, where `origin/live` exists. A tier the loop
  already pushed is not pushed again. `git push` updates the tracking ref on
  both `OK` and `UPTODATE`, so at worst the pass repeats a push that changes
  nothing.
- **The four reporter callers.** The outer `*)` arm can only get the
  non-divergence wording, and the inner `*)` arm can only get the divergence
  wording, so both keep their old text. The retry and the pass pick a wording
  from git's error. The helper comment says a divergence-shaped refusal comes
  "only once ancestry has left nothing to merge". For the retry and the pass,
  that is guaranteed by the take (the tier's `live` contains the `origin/live`
  it fetched) rather than by `gitlore_classify_refusal`. The claim holds as
  written.
- **Whitespace and bash 3.2.** Every path is quoted and no word splitting was
  added. `shellcheck` is clean.

**Mutation (run once, then restored).** I replaced the pass's condition with
`false`. All four pass-dependent tests failed (the two mid-loop variants and the
two wording tests), so the pass is what they exercise. `git diff scripts` is
clean after the restore.

## Tests: cross-slice consistency

### MINOR, fixed: two helper names differed by one word but did opposite things

`install_tier_live_snap_hook` (added this phase) and
`install_tier_live_snapshot_hook` (already in the file, and cited by name in
`decline_tier_pushes_recording`'s doc) have nearly the same name. The first
moves a tier remote's `live`. The second records a tier's `live` from memory's
remote. I renamed the first to `move_tier_remote_live_on_next_push`, which names
what it does and follows the `decline_tier_pushes_*` pattern. Both call sites
are updated.

### MINOR, fixed: one comment still described the defect

The mid-loop behind test said "The defect: `aa`'s own remote never received the
repair memory records." above an assertion that the remote *does* hold it. This
is the same problem slice 2.1/2's test review fixed in its own test. It now
reads "`aa`'s own remote holds the repair memory records."

### MINOR, fixed: the repair-shape assertion was repeated in four places

Four places checked the same thing: `aa_live=$(…rev-parse live)`, its only
parent, and the duplicate bullet counted once. Those places were
`assert_aa_repaired_mid_loop`, the behind-arm-survives test and both wording
tests. The two wording tests skipped the bullet count. All four now call a new
helper, `assert_aa_live_repairs <parent>`, which sets `$aa_live`. As a result:

- the wording tests now also check the bullet count;
- the behind-arm-survives test drops `[ "$aa_live" != "$aa_fact" ]`, which the
  parent check already implies.

### Checked, no finding

- **Hooks.** The move hook removes itself. The two `pre-receive` decline hooks
  and the stub live under `$TMP_REPO` (bare remotes) or `$BATS_TEST_TMPDIR`, and
  `teardown_tmp_repo` removes `$TMP_REPO`. Scratch clones from
  `push_side_ref_child` go under `$BATS_TEST_TMPDIR`. Nothing from this phase is
  left outside the test's own directories. `push_tier_fact`, which predates this
  phase and lives in `tests/helpers/tier-fixtures.bash`, still uses
  `${TMPDIR:-/tmp}` but removes its clone. It is out of scope.
- **The two decline helpers**, `decline_tier_pushes_recording` and
  `decline_tier_pushes_after_first`. Both are `pre-receive` hooks that log and
  then decline. They log different things (the watched tier's `live`, and the
  sha offered), and they decline under different conditions. A shared helper
  would need three parameters to cover both, so they stay separate.
- **Shared setup.** The four tests built on the race use
  `setup_repair_race_on_aa`. The behind-arm-survives test builds its setup
  inline, the same way the existing test "a repair taken by the behind arm is
  published before memory records it" does. A helper for that setup would have
  one user.
- **Stub.** It follows the runbook's idiom: `case " $* "`, `exec` the real git,
  count calls in a log under `$BATS_TEST_TMPDIR`, and put it on `PATH` only for
  the command under test.

## Size (flagged, not split)

`tests/push_behind_vs_diverged.bats` is 749 lines after the fixes. It was 452
lines at `e333de6`, already over the 400-line guideline, and this phase added
about 297. The Phase 2 part is its own unit: the two `---` sections from "a
repair the mid-loop take makes to a DIFFERENT tier" to the end of the file, with
their helpers. It could move to its own file, such as
`tests/push_tier_publication.bats`, with `publish_memory` and
`mount_tier_at_live` moved into `tests/helpers/` or copied. That split is left
for a decision.

## Bats after fixes

`scripts/run-bats.sh tests/push_behind_vs_diverged.bats`:
**20 passed, 0 failed**. The file has 20 `@test`s, and all five Phase 2 tests
appear as `ok` (16–20).
`shellcheck tests/push_behind_vs_diverged.bats scripts/lib/resolve.sh` is clean.

## Files changed

- `tests/push_behind_vs_diverged.bats`

## UNFIXABLE

None.

## Design decisions (not fixed)

- Whether to split `tests/push_behind_vs_diverged.bats`, as described under
  Size.
