# Split report — `tests/tier_divergence.bats`

## Partition

| File | Lines | Tests |
| --- | --- | --- |
| `tests/tier_divergence.bats` | 239 | 12 |
| `tests/tier_divergence_continuation.bats` | 163 | 8 |
| `tests/helpers/tier-divergence.bash` | 37 | (helper, no tests) |

Total: 20 tests, matching `git show HEAD:tests/tier_divergence.bats | grep -c '^@test'`.

Followed the proposed partition exactly: `tests/tier_divergence_continuation.bats`
takes everything from the "the continuation follows the merge to its store"
banner (original line 273) through the end, which also carries the
"/gitlore:resolve finds a tier divergence on its own" banner (382) along with
it. The original keeps "store enumeration" (54), "the state file carries its
store" (83), "both gates yield, at both levels" (123) and "a prepared merge
must survive the next session start" (201).

The long header comment (D17 policy note, lines 1–14 including
`bats_require_minimum_version`) stays in the original, per the dispatch;
`tests/tier_divergence_continuation.bats` gets its own short opener plus a
repeated `bats_require_minimum_version 1.5.0` (needed there too — several
moved tests use `run --separate-stderr`) and the same `# shellcheck
disable=SC2154` for `$stderr`.

## Helper file

`tests/helpers/tier-divergence.bash` — everything used by both resulting
files: `setup()`, `teardown()`, the file-level constants `PRE_COMMIT`,
`PRE_PUSH`, `RESOLVE`, `SESSION_START`, and `approve()`, `mount_tier_at_live()`,
`diverge_tier_from_remote()`, `tier_state_file()`. `PRE_PUSH`, `RESOLVE` and
`SESSION_START` are exported (the original left them unexported, safe only
because every user lived in the same file); exporting follows
`helpers/setup.bash`'s `PLUGIN_ROOT` precedent and is what satisfies
shellcheck's "appears unused" (SC2034) once their readers move to a different
file than their writer. `PRE_COMMIT` needed no such fix — it is also read
inside the helper file itself, by `diverge_tier_from_remote`.

**Note on cross-suite duplication, per the dispatch's caution:** `approve()`
and `mount_tier_at_live()` already exist byte-identically in
`tests/helpers/resolve-compose.bash`, and `approve()` also in
`tests/helpers/push-fixtures.bash`. Not deduped across suites — the dispatch
is explicit that a helper used by only one of *this* split's resulting files
does not license reaching into another suite's helper file, and doing so
would create a cross-suite coupling this task was not scoped to introduce.

## Deviations

None from the proposed partition.

## References

`grep -rn 'tier_divergence\.bats' docs/design.md docs/decisions.md docs/references scripts tests skills agents justfile CLAUDE.md`:

- `tests/resolve_compose.bats:95` — "the tier diverges from its own local
  `live`, as tier_divergence.bats's pre-commit preparation does". Names the
  test "pre-commit prepares a merge when a tier commit diverged from its own
  live", which stays in the original `tests/tier_divergence.bats` (section
  "both gates yield, at both levels", untouched by this split). Left
  unchanged — still correct.
- `tests/helpers/resolve-recovery.bash:26` — same test by full title,
  `tests/tier_divergence.bats "pre-commit prepares a merge when a tier commit
  diverged from its own live"`. Same test, same file, unchanged.
- `tests/tier_lockstep.bats:164` — "Resolution itself is tier_divergence.bats'
  subject" — a reference to the suite as a whole (still true: the suite is
  still named `tier_divergence.bats` and still covers resolution), not to a
  specific moved test. Left unchanged.

Broader `grep -rln 'tier_divergence'` (excluding `docs/changelog/` and
`.claude/`) hit a large number of files under `plans/*/reports/` and
`plans/*/runbook*.md` — historical run reports and runbooks, none naming a
specific test or section that moved. Left unchanged as out of scope for a
code/doc reference sweep.

## Verification

1. Test names preserved:
   ```
   diff <(grep '^@test' "$TMPDIR/tier_divergence.orig.bats" | sort) <(cat tests/tier_divergence.bats tests/tier_divergence_continuation.bats | grep -h '^@test' | sort)
   ```
   Result: no output.

2. No line lost:
   ```
   diff <(sort "$TMPDIR/tier_divergence.orig.bats") <(cat tests/tier_divergence.bats tests/tier_divergence_continuation.bats tests/helpers/tier-divergence.bash | sort) | grep '^<'
   ```
   Result: no output.

3. `wc -l`:
   ```
   239 tests/tier_divergence.bats
   163 tests/tier_divergence_continuation.bats
    37 tests/helpers/tier-divergence.bash
   ```
   All under 380.

4. `scripts/run-bats.sh tests/tier_divergence.bats tests/tier_divergence_continuation.bats`:
   ```
   bats: 20 passed, 0 failed
   ```
   `git show HEAD:tests/tier_divergence.bats | grep -c '^@test'` = 20 — matches.

5. `just lint` — deferred to the end of this batch, run once after all three
   suites are split.
