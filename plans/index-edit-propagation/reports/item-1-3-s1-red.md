# Item 1.3, slice 1 — RED

Target: `gitlore_recover_landed_merge` (`scripts/lib/resolve.sh:234`),
unchanged. Tests added to `tests/resolve_recovery.bats` (also added
`load helpers/tier-fixtures`, and a shared fixture helper
`tier_prepare_head_vs_live`). Nothing under `scripts/` touched. Nothing
committed or staged.

## Case-3 resolution

The dispatch's case 3 ("the same recovery run for the memory root stages nothing
in the parent repo, and returns 0") could not be made to red under the standard
fixture: `make_parent_with_memory` registers `memory` as a real git submodule of
`$TMP_REPO` (confirmed via `scripts/install/init-submodule.sh` and a direct
probe, including inside the pre-commit hook's own env after its blanket
`local-env-vars` unset, and in the exact landed-merge-then-HEAD-moved state the
existing `:292` test builds) — so
`git -C memory rev-parse --show-superproject-working-tree` returns `$TMP_REPO`,
non-empty, exactly like a tier's superproject is `memory`. I flagged this to
main before writing the case; main resolved it as option (b): staging is scoped
by an explicit tier predicate (superproject carries `MEMORY.md` at its root AND
the recovered store's relative path is in `gitlore_tier_paths "$superproject"`),
not by `--show-superproject-working-tree` alone. Main also directed that this
case is **born-green** and must not be forced red — its discriminating proof is
a mutation-red run owed to test review (naive version: stage whenever the
superproject check is non-empty, no tier predicate), not to this RED dispatch.
The test carries that instruction in a comment naming the exact mutation.

## Per-test results (from `bats --jobs 1 tests/resolve_recovery.bats`)

All twelve pre-existing tests in the file still pass unmodified (`ok 1`–`ok 12`,
`ok 18`, `ok 19`). The five new tests:

**1. "a landed tier merge stages the moved gitlink in the memory store's
index"** (`:348`) — RED. Assertion failed:
`[ "$(git -C memory rev-parse ":ddaanet")" = "$landed" ]` (`:365`).
```
not ok 13 recovery: a landed tier merge stages the moved gitlink in the memory store's index
# (in test file tests/resolve_recovery.bats, line 365)
#   `[ "$(git -C memory rev-parse ":ddaanet")" = "$landed" ]' failed
```

**2. "the branch where HEAD already carries the landed merge stages it too"**
(`:368`) — RED. Assertion failed:
`[ "$(git -C memory rev-parse ":ddaanet")" = "$landed" ]` (`:379`).
```
not ok 14 recovery: the branch where HEAD already carries the landed merge stages it too
# (in test file tests/resolve_recovery.bats, line 379)
#   `[ "$(git -C memory rev-parse ":ddaanet")" = "$landed" ]' failed
```

**3. "the same recovery for the memory root stages nothing in the parent repo"**
(`:409`, after main's resolution) — **born-green**, not counted toward the red
contract.
```
ok 15 recovery: the same recovery for the memory root stages nothing in the parent repo
```

**4. "after the recovery, a memory commit runs to completion instead of aborting
on the pin guard"** (`:426`, end to end through the real `pre-commit` hook,
`set_tier_manifest ddaanet` activating the tier so the pin guard actually looks
at it) — RED. Assertion failed: `[ "$status" -eq 0 ]` (`:432`) — i.e. the second
`pre-commit` run aborts on Item 1.2's pin guard against unfixed code, exactly
the defect this item exists to close.
```
not ok 16 recovery: after the recovery, a memory commit runs to completion instead of aborting on the pin guard
# (in test file tests/resolve_recovery.bats, line 432)
#   `[ "$status" -eq 0 ]' failed
```

**5. "a staging failure for a landed tier merge is reported, and the recovery
still returns 0"** (`:445`, induced with a stray `index.lock` in memory's
gitdir, `GITLORE_GIT_RETRY_SCHEDULE="0 0"` to keep it fast) — RED. Assertion
failed: `[[ "$stderr" == *"could not be staged"* ]]` (`:451`) — exit code and
the moved-HEAD outcome already hold against unfixed code (no staging is
attempted, so nothing can fail to stage), only the report is missing.
```
not ok 17 recovery: a staging failure for a landed tier merge is reported, and the recovery still returns 0
# (in test file tests/resolve_recovery.bats, line 451)
#   `[[ "$stderr" == *"could not be staged"* ]]' failed
```

## Verifying each reds on its intended assertion

For cases 1, 2, 4 and 5, `bats` reports the exact line and command that failed,
and each matches the assertion I intended as the case's point (the pin equality
for 1/2, the end-to-end exit code for 4, the stderr text for 5) — since `bats`
aborts a test body at its first failing command, this by construction rules out
an earlier, unintended assertion having failed instead: had
`tier_prepare_head_vs_live`'s own internal assertions, or any earlier line in
the test body, failed, the reported line number would point there, not at the
line I've cited. I additionally traced through the code manually for each case
(documented in-session) to confirm the failing line is reached only after every
earlier assertion in the body already passed against the current implementation
— e.g. case 4's first `pre-commit` run (preparing the tier merge) already passes
today, unrelated to this fix, and only the *second* run (the one this fix is
about) fails. Case 3 was separately confirmed to run clean with no fixture or
missing-helper error (`ok 15`), per main's instruction that it is a
characterization case rather than a red one.

## Three `CLAUDECODE` worlds

Ran the five new tests under `CLAUDECODE=1`, `env -u CLAUDECODE`, and
`env CLAUDECODE=0`. Identical results in all three: cases 1, 2, 4, 5 red on the
same line/assertion in every world; case 3 green in every world. (The staging
report asserted in case 5, `"could not be staged"`, follows the plain
`printf`-to-stderr precedent `gitlore_adopt_tier_into_root` already uses for its
own best-effort staging failure — not `gitlore_say_for_agent_or_user` — so there
is no agent/user arm to diverge across `CLAUDECODE` values there either.)

## Fixture note

`tier_prepare_head_vs_live` (new shared helper, top of the Item-1.3 block in the
file) mirrors `tests/tier_divergence.bats`'s "pre-commit prepares a merge when a
tier commit diverged from its own live": mount a tier, diverge its `live`
sideways, add a tier fact, approve, run the real `pre-commit` hook once to let
`gitlore_sync_tiers_to_live` discover the divergence and call
`gitlore_yield_merge` for real (rather than hand-writing merge-state files).
Cases 1/2/5 then land the merge directly with a bare
`GITLORE_MEMORY_COMMIT=1 git -C memory/ddaanet commit -q --no-edit` — bypassing
`/gitlore:merge`'s own continuation — which is exactly what leaves the moved
gitlink unstaged in memory's index (D43's staging-as-last-act only covers the
normal advancing path). `set_tier_manifest ddaanet` activates the tier so Item
1.2's pin guard actually inspects it in case 4's end-to-end run — without it the
guard skips an unlisted tier entirely (the second residual noted under Item 1.2
in the runbook) and case 4 passed for the wrong reason on a first attempt before
I added the manifest call.

`shellcheck tests/resolve_recovery.bats` is clean (added a file-level
`# shellcheck disable=SC2030,SC2031` matching the precedent in
`tests/tier_discovery.bats`, `tests/add_tier.bats`, etc., since
`tier_prepare_head_vs_live` sets `$status` via `run` inside a helper function
consumed by the calling `@test`'s own subshell).
