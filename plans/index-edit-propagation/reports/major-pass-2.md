# Major pass 2 — deliverable review Major findings 2–5

Applies the four agreed fixes from
`plans/index-edit-propagation/reports/deliverable-review.md` §Major Findings 2–5
on top of the uncommitted Minor pass (`minor-pass-2.md`), which is left intact.
Major 1 is out of scope. Nothing is committed.

## Fix A — broken step reference (Major 5)

**Files changed:** `docs/references/git-hooks.md`.

Confirmed against the numbered `pre-commit` list first: step 3 is
**Sync memory** (it ends in `push . HEAD:live`), step 4 is
**Stage the gitlink**. The sentence in §"The gitlink and `live`" now reads "step
4 stages the commit step 3 just advanced `live` to."

**Red evidence:** none applies — a prose reference, checked by reading the list.

**Green:** `just format-docs` leaves the paragraph as edited.

## Fix B — the drain side of empty session → nosession (Major 4)

**Files changed:** `tests/index_sync.bats`, case
`relay_write: empty agent id refused; empty session and "nosession" reach each other`.

A reverse half follows the existing drain assertions: a write under the literal
session `nosession` (agent `a2`, tag `sync`, bodies `LITERAL-BODY` /
`LITERAL-CTX`), drained bare with an empty session
(`gitlore_relay_drain memory "" || rc=$?`), asserting rc 0 and both bodies in
`GITLORE_RELAY_SYSMSG` / `GITLORE_RELAY_CTX`. A comment says the two halves pin
the mapping in both directions and why the drain is not under `run`.

**Red evidence (mutation; the case is born green).** `scripts/lib/index-sync.sh`
`gitlore_relay_drain`, line 211, `else s=nosession` changed to `else s=""`:

```text
not ok 1 relay_write: empty agent id refused; empty session and "nosession" reach each other
# (in test file tests/index_sync.bats, line 1188)
#   `[[ "$GITLORE_RELAY_SYSMSG" == *"LITERAL-BODY"* ]]' failed

bats: 0 passed, 1 failed
```

Restored from `$TMPDIR/index-sync.sh.bak`; `cmp` against the backup reports
identical.

**Green:** the case passes on the restored code (1 passed, 0 failed), and
`tests/index_sync.bats` passes whole (below).

## Fix C — the marker-in-place tests stage under the wrong session (Major 3)

**Files changed:** `tests/index_sync.bats`
(`an unkeyed index-sync run leaves a marker in place`),
`tests/cc_hook_index_compose.bats`
(`an unkeyed compose run leaves a marker in place`).

Confirmed the session each hook runs in: `batch_payload` in `index_sync.bats`
sends `session_id` `${TEST_SESSION_ID:-test-session}` (the case sets no
override), and `feed()` in `cc_hook_index_compose.bats` sends `test-session`.
Both cases now stage with `gitlore_relay_write memory test-session a1 …`. The
RED-phase rationale in each header comment (why `nosession` was chosen) is
replaced with: the marker is staged under the session the hook runs in, so any
drain returning to the hook would consume it, whether scoped to that session
(the D51 shape) or unscoped; a marker under another session survives both and
asserts nothing.

**Red evidence (mutation; both cases are born green).** Each hook got a drain of
the D51 shape before its final emission,
`gitlore_relay_drain "$mempath" "$session"`, folding `GITLORE_RELAY_SYSMSG` /
`GITLORE_RELAY_CTX` into what it emits (`sysmsg`/`ctx` in
`scripts/cc-hooks/index-sync-post.sh`, `GITLORE_COMPOSE_SYSMSG` /
`GITLORE_COMPOSE_CTX` in `scripts/cc-hooks/index-compose.sh`), as
`scripts/cc-hooks/relay-drain.sh` does:

```text
not ok 1 an unkeyed index-sync run leaves a marker in place
# (in test file tests/index_sync.bats, line 789)
#   `[[ "$output" != *"gitlore-relay agent a1"* ]]' failed

bats: 0 passed, 1 failed
```

```text
not ok 1 an unkeyed compose run leaves a marker in place
# (in test file tests/cc_hook_index_compose.bats, line 305)
#   `[[ "$output" != *"gitlore-relay agent a1"* ]]' failed

bats: 0 passed, 1 failed
```

Both hooks restored from `$TMPDIR/index-sync-post.sh.bak` and
`$TMPDIR/index-compose.sh.bak`; `cmp` against each backup reports identical.

**Green:** each case passes on the restored hooks (1 passed, 0 failed), and both
files pass whole (below).

## Fix D — `|| tier_unadopted=1` suspends errexit (Major 2)

**Files changed:** `tests/resolve_compose.bats` (new case),
`scripts/resolve.sh`.

**RED.** New case after the unadopted-tier cases,
`a staging failure in the continuation aborts before the commit, and a rerun lands the merge`:
it prepares the merge with `prepare_tier_merge_with_new_lines`, records the tier
HEAD, creates `index.lock` in memory's gitdir, exports
`GITLORE_GIT_RETRY_SCHEDULE=0`, runs `continue-after-merge`, removes the lock,
and asserts status non-zero, `index.lock` in stderr, no "could not take tier" in
stderr, the tier HEAD unchanged, and the tier's `gitlore-merge-state` still
present. It then reruns the continuation and asserts status 0, `HEAD:ddaanet`
equal to the tier HEAD, and the `ddaanet/t.md` line in `memory/MEMORY.md`.

HEAD is the no-merge-commit assertion, not `MERGE_HEAD`. The abort comes before
`commit`, so the tier still sits on the commit the preparation left it on. "No
merge commit" is a statement about HEAD. The code leaves `MERGE_HEAD` in place
too.

On unchanged code:

```text
not ok 1 a staging failure in the continuation aborts before the commit, and a rerun lands the merge
# (in test file tests/resolve_compose.bats, line 225)
#   `[ "$status" -ne 0 ]' failed
# gitlore: memory merge prepared (flavor=head-vs-remote) in store:
# gitlore:   /tmp/claude-1000/gitlore-test.rSYiao/memory/ddaanet
# gitlore: dispatch sub-agent gitlore:memory-merger with state file:
# gitlore:   /tmp/claude-1000/gitlore-test.rSYiao/.git/modules/gitlore-memory/modules/ddaanet/gitlore-merge-state
# gitlore: that dispatch is a required step of the git operation that triggered
# gitlore: this merge, not an option: the request for that operation is the
# gitlore: request for this dispatch, so make it now without asking first. Review
# gitlore: the synthesis it returns yourself — both sides of this merge already
# gitlore: passed an approval gate, so do not prompt the user (D49).
# gitlore: on approval of its synthesis, the sub-agent must run:
# gitlore:   cd "/tmp/claude-1000/gitlore-test.rSYiao" && bash "/Users/david/code/gitlore/tests/../scripts/resolve.sh" continue-after-merge

bats: 0 passed, 1 failed
```

It fails on the status assertion, the first one after the run. The `gitlore:`
lines are the fixture's preparation output (`pre-push` refusing), not the
continuation's.

**GREEN.** In `scripts/resolve.sh`:

- `compose_merged_indexes "$memroot" "$mempath"` is called bare, and the call
  site's `tier_unadopted=""` is gone.
- `compose_merged_indexes` initialises `tier_unadopted=""` next to
  `merged_tier=""`. Its unadopted arm sets `tier_unadopted=1` after its `add -A`
  and returns 0.
- The header comment says the function sets `merged_tier` and `tier_unadopted`
  for the caller and returns 0. It says a failed staging command aborts the
  continuation under errexit before the merge commit, keeping the merge state
  for a rerun. It says the caller calls it bare, because an `||` would suspend
  errexit across the whole body.

The new case passes (1 passed, 0 failed), rerun half included:
`gitlore_compose_up` over a root it already wrote in the aborted run lands the
merge and adopts it, so no idempotence stop was needed.

**Docs.** `docs/references/tier-stores.md`,
`docs/references/merge-state-recovery.md`, `docs/references/git-hooks.md` and
`docs/changelog/2026-09-13-a-tier-merge-the-root-index-cannot-adopt-records-nothing.md`
hold no sentence about how the continuation handles a staging failure in this
step. Their continuation passages cover an up projection the root cannot adopt,
a yield, and an off-ancestor pin, and all of them stay true. No doc change.

Untouched as instructed: `gitlore_adopt_tier_into_root`'s walk-back arm,
`rest_unadopted_tier`, `push_or_report`, `gitlore_push_stores`.

## Checks that passed

Each through `scripts/run-bats.sh`, one at a time, in the foreground:

- `tests/index_sync.bats` — 89 passed, 0 failed
- `tests/cc_hook_index_compose.bats` — 25 passed, 0 failed
- `tests/resolve_compose.bats` — 9 passed, 0 failed
- `tests/resolve.bats` — 8 passed, 0 failed
- `tests/resolve_merge_local.bats` — 4 passed, 0 failed
- `tests/resolve_merge_remote.bats` — 3 passed, 0 failed
- `tests/resolve_merge_briefing.bats` — 8 passed, 0 failed
- `tests/resolve_recovery.bats` — 23 passed, 0 failed
- `tests/tier_divergence.bats` — 19 passed, 0 failed
- `tests/git_hook_pre_commit.bats` — 19 passed, 0 failed
- `tests/pre_push_hook.bats` — 9 passed, 0 failed
- `tests/merge_memory.bats` — 23 passed, 0 failed
- `just lint` — `lint-shell: 138 files clean`
- `just format-docs` — rc 0. The first run fixed 9 issues in 2 files: this
  report, and `plans/unadoptable-tier-arrival/recall-artifact.md`, an untracked
  file from a concurrent session that this pass did not author (rewrap only).
  The second run fixes nothing, leaving only the standing unwrappable MD013
  residue.
