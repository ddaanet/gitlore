# Item 4.1 — RED report

All 4 slices added to `tests/resolve_compose.bats` (lines 496-591), built on the
fixture `prepare_tier_merge_with_new_lines` + `seed_root_bullet "gone/x.md" ...`
— the same shape as the existing test "a tier merge the root index cannot adopt
lands, records nothing in the root, and is adopted by the next take"
(`tests/resolve_compose.bats:287`), which sets `tier_unadopted` so
`rest_unadopted_tier` is reachable. `scripts/` is untouched
(`git diff --stat scripts/` empty).

## Slice 1 — `tests/resolve_compose.bats:497` "an origin push declined for
policy rests the unadopted tier and exits 1"

FAIL (red). Command:
`scripts/run-bats.sh tests/resolve_compose.bats --filter 'an origin push declined for policy rests the unadopted tier and exits 1'`.

Failing assertion: `tests/resolve_compose.bats:514` —
`[ "$(git -C memory/ddaanet rev-parse HEAD)" = "$pin" ]`.

```
not ok 1 an origin push declined for policy rests the unadopted tier and exits 1
# (in test file tests/resolve_compose.bats, line 514)
#   `[ "$(git -C memory/ddaanet rev-parse HEAD)" = "$pin" ]' failed
```

Reason: today `push_or_report`'s origin push (the second call, after the local
`. HEAD:live` push already succeeded) hits its own `exit 1` on the pre-receive
decline before returning to the caller, so `rest_unadopted_tier` never runs and
the tier stays on the merge commit instead of being walked back to its pin. The
earlier assertions (`status -eq 1`, stderr contains "declined by policy", tier
`live` is a merge commit) already pass today — only the per-arm exit (status 2
routed through `rest_unadopted_tier`) is missing.

## Slice 2 — `tests/resolve_compose.bats:517` "a refused local live update
leaves the unadopted tier on the merge with a runnable remedy"

FAIL (red). Command:
`scripts/run-bats.sh tests/resolve_compose.bats --filter 'a refused local live update leaves the unadopted tier on the merge with a runnable remedy'`.

Failing assertion: `tests/resolve_compose.bats:532` —
`[[ "$stderr" == *"gitlore:   git -C \"$abs\" push . HEAD:live"* ]]`.

```
not ok 1 a refused local live update leaves the unadopted tier on the merge with a runnable remedy
# (in test file tests/resolve_compose.bats, line 532)
#   `[[ "$stderr" == *"gitlore:   git -C \"$abs\" push . HEAD:live"* ]]' failed
```

Reason: this is the *first* `push_or_report` call (`. HEAD:live`, blocked by the
held `refs/heads/live.lock`); today it exits directly from inside
`push_or_report` with git's own lock-error message ("pushing '...' failed, and
not because of divergence..."), never reaching the new `rest_unadopted_tier`
remedy text (`gitlore:   git -C "<abs>" push . HEAD:live` /
`checkout --detach <pin>`), which does not exist yet. `status -eq 1` and "HEAD
is a merge commit" (`rev-list --count --merges HEAD -1` = 1) already pass — the
commit lands before either push is attempted, so that part is unaffected by the
lock.

## Slice 3 — `tests/resolve_compose.bats:536` "following the remedy adopts
the merge"

FAIL (red). Command:
`scripts/run-bats.sh tests/resolve_compose.bats --filter 'following the remedy adopts the merge'`.

Failing assertion: `tests/resolve_compose.bats:553` —
`[ "${#remedy_cmds[@]}" -eq 2 ]`.

```
not ok 1 following the remedy adopts the merge
# (in test file tests/resolve_compose.bats, line 553)
#   `[ "${#remedy_cmds[@]}" -eq 2 ]' failed
```

Reason: downstream of slice 2 — since the remedy lines are never printed today,
extracting `gitlore:   git -C ...` lines from stderr yields zero commands
instead of two, so the test fails cleanly before it can attempt to run them.
This is the expected cascade: slice 3 cannot exercise "run the remedy, then
adopt" until slice 2's remedy text exists.

## Slice 4 — `tests/resolve_compose.bats:571` "default-mode gates exit 1 on a
policy refusal"

PASS on unmodified code (born green — guard). Command:
`scripts/run-bats.sh tests/resolve_compose.bats --filter 'default-mode gates exit 1 on a policy refusal'`
→ `bats: 1 passed, 0 failed`.

Reason: today `check_store_gates`'s origin push also routes through
`push_or_report`'s own `exit 1` for a non-divergence refusal, emitting "...
failed, and not because of divergence ..." directly — which already satisfies
both assertions (contains "not because of divergence", does not contain "refused
as a non-fast-forward", since `check_store_gates`'s own
`gitlore_classify_refusal`-based `case` is never reached). The m4 refactor must
preserve this by giving `check_store_gates` an explicit `rc == 2 → exit 1`
branch rather than falling through to the generic
`case "$(gitlore_classify_refusal ...)"` used for `rc == 1`.

**Non-vacuousness mutation** (proves the test is not tautological): in a checked
copy of `scripts/resolve.sh` (`$TMPDIR/item-4-1-mutation/resolve.sh.orig`),
replaced `push_or_report`'s final `gitlore_say_for_agent_or_user ... ; exit 1`
block with a bare `return 1` — simulating the defect the runbook guards against:
a caller that lets a non-divergence refusal (future status 2) fall through the
same
`if ! push_or_report; then case "$(gitlore_classify_refusal "$store" live origin/live)" in ... esac; fi`
used for divergence (status 1). With the tier's local `live` strictly ahead of
`origin/live` (a fast-forwardable, policy-only refusal),
`gitlore_classify_refusal` returns `ahead`, landing in the `*)` arm and printing
"... refused as a non-fast-forward, but its local 'live' already contains the
remote's...".

Ran the mutated file:

```
not ok 1 default-mode gates exit 1 on a policy refusal
# (in test file tests/resolve_compose.bats, line 585)
#   `[[ "$stderr" == *"not because of divergence"* ]]' failed
```

— both assertions flip (loses "not because of divergence", the "does not contain
refused as a non-fast-forward" assertion would also fail were the first one not
reached first), confirming the test is sensitive to exactly the regression it
exists to catch. Restored the original file afterward; `cmp` against the saved
copy confirmed byte-identical, and `git diff --stat scripts/` is empty.

## Full-file run

`scripts/run-bats.sh tests/resolve_compose.bats` → `18 passed, 3 failed` (slices
1, 2, 3 fail as above; slice 4 and all 18 pre-existing tests pass — no
regressions).

## shellcheck

`shellcheck tests/resolve_compose.bats` reports only pre-existing informational
notes (SC2030/SC2031 on `export GITLORE_GIT_RETRY_SCHEDULE=0` inside a `@test`
body — the same pattern already present at `tests/resolve_compose.bats:371`
before this dispatch, inherent to bats' subshell-per-test model). No warnings or
errors.
