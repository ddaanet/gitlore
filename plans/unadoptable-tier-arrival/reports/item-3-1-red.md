# Item 3.1 — RED report

File: `tests/resolve_compose.bats`. Ran each new/changed test individually with
`scripts/run-bats.sh tests/resolve_compose.bats --filter '<name>'`, then the
whole file once. `shellcheck tests/resolve_compose.bats` — clean.

## Slice 1 — external contract (2 tests)

### "a tier merge whose merged carrier has a duplicate pointer is not committed"
`tests/resolve_compose.bats:169` (uses new helpers `duplicate_tier_carrier` and
existing `prepare_tier_merge_with_new_lines`, added at
`tests/resolve_compose.bats:137-163`).

- Fail. Failing assertion: `[ "$status" -eq 1 ]` (line 169).
- Actual: `status=0`, stderr is today's "the root index could not take tier
  'ddaanet''s lines — the merge is being committed in the tier, and the memory
  store will record none of it: … duplicate pointer path t.md …" — the
  `tier_unadopted` arm lands the merge instead of refusing.
- This is the premise: slice 1 is the behavior change itself, not a guard, so
  the failure is the expected/correct red for K4 not yet implemented.

### "a head-vs-live tier merge whose merged carrier has a duplicate pointer is not committed"
`tests/resolve_compose.bats:187` (uses new helper
`prepare_tier_merge_head_vs_live`, modeled on `tests/tier_divergence.bats:143`'s
local-`live`-sideways prep, with `set_tier_manifest ddaanet` and
`gitlore.hooksDir` added since this test needs composition to actually run).

- Fail. Failing assertion: `[ "$status" -eq 1 ]` (line 187).
- Actual: `status=0`, same `tier_unadopted` message as above; flavor confirmed
  `head-vs-live` in the prepare-merge directive text captured in the log.
- Same premise as the first test.

## Slice 2 — guard: "a kept refused merge re-emits the continuation directive"
`tests/resolve_compose.bats:204`.

- Fail. Failing assertion: `[[ "$stderr" == *"continue-after-merge"* ]]` (line
  204).
- Actual: because slice 1's refusal doesn't happen yet, the first
  `continue-after-merge` call lands and clears the merge; the default-mode
  `bash "$RESOLVE"` run then finds nothing prepared and its `$stderr` never
  mentions `continue-after-merge`. This is the premise (slice 1's refusal), not
  the guard's own behavior.

## Slice 3 — guard: "a fixed merged carrier lands"
`tests/resolve_compose.bats:217`.

- Fail. Failing assertion: `[ "$status" -eq 0 ]` (line 217) — on the *second*
  `continue-after-merge` call.
- Actual: the first `continue-after-merge` already landed the merge (slice 1 not
  implemented), clearing merge state; the second call then fails differently
  (`load_continuation_state`: "no merge state file in memory or any tier")
  rather than landing the fix. This is the premise.

## Slice 4 — 2 tests (one new, one rewritten)

### "a duplicate in the merged root index keeps the merge unlanded"
`tests/resolve_compose.bats:339` — rewrite of the former "a compose refusal is
reported but never strands the merge" (former `tests/resolve_compose.bats:241`;
same `diverge_memory_with_index` fixture with two `p.md` bullets).

- Fail. Failing assertion: `[ "$status" -eq 1 ]` (line 339).
- Actual: `status=0` — today's code commits uncomposed on a root rule-1 refusal,
  per the old (now superseded) test's own assertions. This is the behavior
  change itself, so this is the expected red, not a premise issue.

### "a memory-root merge whose merged index welds a line is not committed"
`tests/resolve_compose.bats:357` — new test, root-only weld fixture
(`- [A](a.md) — a- [B](b.md) — b`, no tier involved).

- Fail. Failing assertion: `[ "$status" -eq 1 ]` (line 357).
- Actual: `status=0`, same "committed uncomposed" path as the duplicate case
  above (rule 6 instead of rule 1). Expected red.

## Slice 5 — guard: "a memory-root merge with only a leftover root prefix commits uncomposed"
`tests/resolve_compose.bats:365`.

- Pass on unmodified code, as the runbook states it should.
- Non-vacuousness check: backed up `scripts/resolve.sh` to a checked
  `$TMPDIR/probe.XXXXXX/resolve.sh.orig`, edited the final `else` branch of
  `compose_merged_indexes` (the memory-root, rc==1 arm) to `exit 1`
  unconditionally instead of committing uncomposed, reran the filtered test: it
  went red —
  ```
  not ok 1 a memory-root merge with only a leftover root prefix commits uncomposed
  # (in test file tests/resolve_compose.bats, line 374)
  #   `[ "$status" -eq 0 ]' failed
  ```
  Restored `scripts/resolve.sh` from the backup, `cmp` confirmed byte-identical,
  and `git diff --stat -- scripts/resolve.sh` /
  `git status --porcelain -- scripts/` show no residual change. Reran the
  filtered test: passes again. This proves the guard actually distinguishes
  "blocks only on a problem attributed to the merged index file" from "blocks on
  any root refusal" — the naive over-broad implementation Item 3.1 must not
  produce.

## Whole-file run

`scripts/run-bats.sh tests/resolve_compose.bats`: 9 passed, 6 failed — the 6
failures are exactly the tests above (slice 1 ×2, slice 2, slice 3, slice 4 ×2);
all other tests in the file, including slice 5's guard, are green.
