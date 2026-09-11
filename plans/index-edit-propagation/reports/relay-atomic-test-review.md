# Test review: atomic relay write (RED)

Reviewed `tests/index_sync.bats` (uncommitted) against
`plans/index-edit-propagation/reports/relay-atomic-red.md`.
`scripts/lib/index-sync.sh` was mutated twice for proof and restored both times;
`git diff --exit-code scripts/lib/index-sync.sh` is clean and
`git status --porcelain` shows only `tests/index_sync.bats` modified.

## Mechanical check — the report is accurate

`scripts/run-bats.sh tests/index_sync.bats`, tree exactly as handed over:

```
not ok 64 relay_drain does not fold a stranded .tmp marker
# (in test file tests/index_sync.bats, line 1290)
#   `[ -z "$GITLORE_RELAY_SYSMSG" ]' failed
not ok 65 relay_write does not destroy a staged report when the install fails
# (in test file tests/index_sync.bats, line 1328)
#   `[ "$status" -ne 0 ]' failed

bats: 85 passed, 2 failed
```

and from the TAP log,
`ok 66 relay_drain removes a .tmp stranded alongside the marker it drains`.

Both reds are failed assertions, not ERROR and not a missing symbol — bats
reports the assertion line and its source text, which it does only for a
`[ … ]`/`[[ … ]]` that evaluated false. Case 3 is born green. No discrepancy
with the report.

## Case 3's mutation proof reproduces

Applied fix item 2 alone, in place, at `scripts/lib/index-sync.sh:221`:

```
done < <(find "$gitdir" -maxdepth 1 -type f -name 'gitlore-relay-*' '!' -name '*.tmp' -print0)
```

with no `rm -f "$marker.tmp"`.
`scripts/run-bats.sh tests/index_sync.bats -f "relay"`:

```
not ok 13 relay_drain removes a .tmp stranded alongside the marker it drains
# (in test file tests/index_sync.bats, line 1351)
#   `[ ! -e "$marker.tmp" ]' failed

bats: 11 passed, 2 failed
```

Case 1 went green under the same mutation, as the report says. Restored with
`git checkout --`, verified clean. The proof reproduced verbatim, and again
against the revised case after the fixes below.

Case 3 is therefore a real pin of fix item 3, and stays born green.

## Findings

### Major — the selective half of case 1 had never executed (fixed)

Case 1 died on `[ -z "$GITLORE_RELAY_SYSMSG" ]`, so everything after it — the
pairing with a real `a1` marker and the four `!=` cross-checks — was unproven.
Those assertions *are* red today, but nothing observed it, and their first real
execution would have been at GREEN. This suite already names that shape as
disqualifying: the `relay_write refuses an empty agent id` case was split from
the squatted-path case for exactly this reason.

Split into two tests. The selective half now reds on its own:

```
not ok 65 relay_drain still folds a real marker standing beside a stranded .tmp
# (in test file tests/index_sync.bats, line 1338)
#   `[[ "$GITLORE_RELAY_SYSMSG" != *"TORN-BODY"* ]]' failed
```

The three positive assertions ahead of it (`S1`, `agent a1`, `C1`) execute and
pass, so the case proves the fold still happens rather than the drain bailing
out at the first name it refuses.

### Major — no spaced-gitdir coverage of the new `.tmp` expansions (fixed)

The GREEN fix adds two new expansions of the unsanitized gitdir prefix:
`mv "$marker.tmp" "$marker"` and `rm -f "$marker.tmp"`. The `mv` is already
covered — the pre-existing
`relay_drain folds two markers in filename order, over a gitdir path holding a space`
case writes and drains on a spaced fixture, and an unquoted rename there fails
the write's own status assertion. The `rm -f` was not: no case in the suite put
a `.tmp` on a spaced path, so an unquoted `rm -f $marker.tmp` would remove the
wrong paths, leave the temp standing, exit 0 through `-f`, and pass all three
new cases.

Case 3 now builds its fixture with
`_gitlore_build_parent_with_memory "$TMP_REPO/has space" memory`, mirroring that
neighbour, and asserts its own fixture's shape (`case "$marker" in *\ *)`)
rather than trusting the helper's name. Still born green, and the mutation proof
still reds it on `[ ! -e "$marker.tmp" ]` (re-run after the edit, line 1416).

### Major — case 3 was vacuous about the drain actually draining (fixed)

`rc -eq 0`, `[ ! -e "$marker" ]`, `[ ! -e "$marker.tmp" ]` are all satisfied by
a drain that unlinked every `gitlore-relay-*` name and folded nothing. Added
`[[ "$GITLORE_RELAY_SYSMSG" == *"S1"* ]]` ahead of the existence assertions. It
is green today and green under the partial mutation, so it does not displace the
case's red.

### Major — the destroyed-evidence half of the defect was unpinned (fixed)

The defect is that the drain folds the torn text *and* `rm -f`s the evidence.
Only the folding was asserted. A drain that excluded `.tmp` from the fold but
swept every `.tmp` in the gitdir satisfies both `[ -z … ]` assertions while
destroying the one thing the temp exists to preserve.

Added `[ -e "$tmp" ]` to the lone-`.tmp` case. It sits behind the two `[ -z ]`
assertions, so it does not execute in the default RED run; proved red today by a
one-off reorder, reverted immediately:

```
not ok 1 relay_drain does not fold a stranded .tmp marker
# (in file tests/index_sync.bats, line 1298)
#   `[ -e "$tmp" ]' failed
```

Under the three named GREEN changes the orphan temp survives (it is excluded
from enumeration, and `rm -f "$marker.tmp"` fires only for markers actually
drained), so the assertion holds. **Flag for GREEN:** this is the one assertion
that constrains the fix beyond the three stated changes — an implementation that
swept all `.tmp` files would fail it. That is the intended contract as the
problem statement words it, but it is worth confirming rather than silently
widening the spec.

### Minor — case 1's temp path was hand-built (fixed)

`tmp="$gitdir/gitlore-relay-orphan.tmp"` duplicated the marker naming convention
instead of deriving it. Now
`tmp="$(gitlore_relay_marker_file memory orphan).tmp"`, which is what a killed
writer's temp actually is; the local `gitdir` variable became unused and is
gone.

### Minor — case 2's trailing `rmdir` (fixed)

The trailing `rmdir "$marker.tmp"` contradicted the documented rationale of the
neighbouring squat case: `teardown_tmp_repo`'s `rm -rf` removes the fixture tree
either way, and a cleanup line after the assertions does not run on a mid-body
failure. Removed, with the reason recorded in the comment.

### Minor — case 2's name and comment misdescribed the failure point (fixed)

The squat blocks the write *to the temp*, not the `mv` install. Renamed to
`relay_write does not destroy a staged report when its temp cannot be written`
and the comment reworded. Also recorded why it carries no
`[ "$(id -u)" -eq 0 ] && skip` guard, matching the slice-4 squat case: a
redirect onto a directory is EISDIR, not a permission bit, so it fails for root
too.

## Checked and found sound, no change needed

- **Torn byte shape.** Case 1's fixture is an exact prefix of the write's four
  printfs cut after the second — sysmsg delimiter, body, nothing — which is what
  a writer killed between printfs leaves, and the shape that makes
  `_gitlore_relay_sysblock` run to EOF. Case 3's temp now carries the same shape
  rather than a bare `STRANDED` line. Both are written directly because no
  completed call to `gitlore_relay_write` produces a torn file.
- **Negative assertions.** `!= *"TORN-BODY"*` and `!= *"orphan"*` both go red
  under the mutation that makes the string appear (today's unfixed drain), not
  merely under one that removes it — observed, not reasoned.
- **No JSON.** No case reads `jq`, so the `null`-for-absent-key trap does not
  apply.
- **Case 2's byte comparison.** `before=$(cat …)` and `$(cat …)` strip trailing
  newlines identically, so the comparison is well-formed.

## Result

`scripts/run-bats.sh tests/index_sync.bats`, after the fixes:

```
not ok 64 relay_drain does not fold a stranded .tmp marker
#   `[ -z "$GITLORE_RELAY_SYSMSG" ]' failed
not ok 65 relay_drain still folds a real marker standing beside a stranded .tmp
#   `[[ "$GITLORE_RELAY_SYSMSG" != *"TORN-BODY"* ]]' failed
not ok 66 relay_write does not destroy a staged report when its temp cannot be written
#   `[ "$status" -ne 0 ]' failed

bats: 85 passed, 3 failed
```

Three observed reds, each on its named assertion;
`ok 67 relay_drain removes a .tmp stranded alongside the marker it drains` stays
born green with its mutation proof re-verified. The same 85 pre-existing cases
pass as before the review — the count is unchanged because the split added one
test and the spaced fixture change kept its case green.

`scripts/lint-shell.sh`: 137 files clean.

Not run, per the dispatch: `just precommit`. Nothing staged, nothing committed.

## Out of scope

Nothing required an implementation change. No UNFIXABLE-IN-SCOPE findings.
`scripts/lib/index-sync.sh` was mutated only as a proof and is byte-identical to
HEAD.
