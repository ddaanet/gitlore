# Item 3.1 slice 2 — RED report

Seven cases, two per hook as a keyed/unkeyed pair plus the three the test review
added — an empty-own-report case per hook and an end-to-end seam case for the
compose hook. All fail against the current unwired hooks, each on its own named
assertion — no missing symbol, no fixture error.

## `tests/cc_hook_index_compose.bats`

### "a keyed compose run writes a marker and still emits its own json"

```
not ok 11 a keyed compose run writes a marker and still emits its own json
# (in test file tests/cc_hook_index_compose.bats, line 231)
#   `[ -f "$marker" ]' failed
```

Died on the marker-existence check (line 231: `[ -f "$marker" ]`). Everything
before it — `status -eq 0` and the `recomposed tier pointers` text extracted
from `.systemMessage` — passed, because the compose hook's own report is
unaffected by this item ("in addition to, not instead of"); those assertions are
pinning pre-existing behaviour, not the SUT.

Non-vacuity: reordered the last two lines in a scratch copy
(`grep -qF 'recomposed tier pointers' "$marker"` before `[ -f "$marker" ]`). The
grep fired first and failed on its own:
```
`grep -qF 'recomposed tier pointers' "$marker"' failed with status 2
grep: .../gitlore-relay-a1: No such file or directory
```
Both the existence check and the content check discriminate independently —
neither is vacuous. The JSON/systemMessage assertions ahead of them are already
true today and stay that way through GREEN; they are non-vacuous only in the
sense that they'd fail if the wiring accidentally suppressed the subagent's own
report while adding the relay write (a real regression shape the case guards
against), not in the sense of failing at RED.

### "an unkeyed compose run folds in the marker and removes it"

```
not ok 12 an unkeyed compose run folds in the marker and removes it
# (in test file tests/cc_hook_index_compose.bats, line 258)
#   `[[ "$output" == *"gitlore-relay agent a1"* ]]' failed
```

Died on the attribution substring (line 258). The marker was planted directly
via `gitlore_relay_write` (already committed, slice 1) so this case is isolated
from whether the compose hook itself writes markers — it tests only the fold
side. `status -eq 0` and the own `recomposed tier pointers` line passed first
(pre-existing behaviour).

Non-vacuity, two reorderings:
1. Moved `[ ! -f "$marker" ]` and the `keyed relay sysmsg a1` content check
   ahead of the attribution check → `[ ! -f "$marker" ]` fired and failed on its
   own (marker is never drained today, so it's still there).
2. Isolated the content check alone ahead of attribution →
   `[[ "$output" == *"keyed relay sysmsg a1"* ]]` fired and failed on its own.

All three assertions (attribution, content, marker-removed) discriminate
independently. None is vacuous.

## `tests/index_sync.bats`

### "a keyed index-sync run writes its replacement report to a marker"

```
not ok 65 a keyed index-sync run writes its replacement report to a marker
# (in test file tests/index_sync.bats, line 741)
#   `[ -f "$marker" ]' failed
```

Died on the marker-existence check. `status -eq 0` and the
`reset frontmatter to match MEMORY.md` text extracted from `.systemMessage`
passed first — the subagent's own sync report is unaffected by this item.

Non-vacuity: reordered so both `grep` checks
(`reset frontmatter to match MEMORY.md`, `• a.md:`) ran before the `-f` check.
The first grep fired and failed on its own:
```
`grep -qF 'reset frontmatter to match MEMORY.md' "$marker"' failed with status 2
grep: .../gitlore-relay-a1: No such file or directory
```
A second reordering isolated the `• a.md:` grep ahead of both the other grep and
the `-f` check — it also fired and failed on its own (same "No such file or
directory"). Existence and both content checks each discriminate independently.

### "an unkeyed index-sync run folds in the marker"

```
not ok 66 an unkeyed index-sync run folds in the marker
# (in test file tests/index_sync.bats, line 774)
#   `[[ "$output" == *"gitlore-relay agent a1"* ]]' failed
```

Died on the attribution substring. Marker planted directly via
`gitlore_relay_write`, isolating this case from the write side. This case needed
care beyond the compose pair: the sync hook exits upstream of the report path
(and so of the drain) when it has no baseline of its own, so the unkeyed run
needed its own real pre-hook stash and an actual index change to reach the
emission guard at all — a marker planted with no such baseline would never even
be looked at.

Non-vacuity: reordered `[ ! -f "$marker" ]` and the `keyed relay sysmsg a1`
content check ahead of the attribution check.
- `[ ! -f "$marker" ]` fired and failed on its own (marker never drained).
- Isolated further, `[[ "$output" == *"keyed relay sysmsg a1"* ]]` fired and
  failed on its own.

All three assertions (attribution, content, marker-removed) discriminate
independently. None is vacuous.

### "an unkeyed compose run with no report of its own still emits the relay"

```
not ok 13 an unkeyed compose run with no report of its own still emits the relay
# (in test file tests/cc_hook_index_compose.bats, line 297)
#   `[[ "$output" == *"gitlore-relay agent a1"* ]]' failed
```

Added at test review. The case the pair above cannot see: both hooks guard
emission on their own report being non-empty, so a fold placed after that guard
passes every case where the hook has something of its own to say — verified by
mutation, a fold-after-guard implementation ships green on all four original
cases and on all of slice 1. The fixture is the already-composed store of "an
already-composed store reports nothing", so the unkeyed run reaches the emission
point with an empty report; an instrumented copy of the hook confirms it
(`PROBE-REACHED-GUARD sysmsg=[]`) rather than exiting upstream.

Non-vacuity: the negative assertion
`[[ "$output" != *"recomposed tier pointers"* ]]` runs ahead of the attribution
check and passes, which is what makes the attribution check discriminate — the
emission can only be the relay's doing.

### "an unkeyed compose run folds in a marker a keyed run wrote"

```
not ok 14 an unkeyed compose run folds in a marker a keyed run wrote
# (in test file tests/cc_hook_index_compose.bats, line 324)
#   `[ -f "$marker" ]' failed
```

Added at test review, for the seam the isolated write and fold cases leave open:
nothing made them agree on the marker's on-disk format, and a keyed branch
writing the raw body with no `--- gitlore-relay-sysmsg ---` delimiter passed
both while the drain's `awk` yielded an empty body in production. This is the
only case in either suite that reds against that implementation.

Reds on its fixture precondition — the marker a real keyed run must have written
— because the end-to-end shape cannot reach its seam assertion until the write
half exists.

### "an unkeyed index-sync run with no report of its own still emits the relay"

```
not ok 67 an unkeyed index-sync run with no report of its own still emits the relay
# (in test file tests/index_sync.bats, line 817)
#   `[[ "$output" == *"gitlore-relay agent a1"* ]]' failed
```

Added at test review — the sync hook's half of case 13. The index really changes
(`old hook` → `new hook`, so `cmp -s` differs and the loop runs) but `a.md`
already carries that description, so nothing is news. The description goes in
unquoted and the sync normalizes it to `description: "new hook"`, and that
assertion is what proves the loop ran rather than the hook exiting upstream of
the report path — with an empty own-report there is no other observable.

## Non-vacuous-in-both / vacuous-in-both

None found. Every assertion added in this slice — in all seven cases — is either
already true today (the subagent's own report, pinning "in addition to, not
instead of") or independently discriminating at RED once reordered ahead of the
assertion that currently fires first. No assertion was found that could not fail
under any implementation.

## Checks that passed, by name

- `scripts/run-bats.sh tests/cc_hook_index_compose.bats tests/index_sync.bats` —
  92 passed, 7 failed (the 7 new RED cases, each on its own named assertion; no
  other test in either suite regressed).
- `shellcheck -s bash tests/cc_hook_index_compose.bats tests/index_sync.bats` —
  clean.
- `scripts/lint-shell.sh` — 137 files clean.
- Mutation matrix over three candidate GREEN implementations, added at test
  review: a fold placed after the emission guard reds cases 13, 14 and 67 and
  nothing else; a correctly placed fold whose keyed write uses a raw marker
  format reds case 14 and nothing else; the correct implementation is green on
  both suites entire.
- Working tree confirmed to hold only the two intended edits
  (`tests/cc_hook_index_compose.bats`, `tests/index_sync.bats`); all scratch
  copies used for the non-vacuity probes, the reachability probes and the
  mutation matrix were deleted before this report was written.
