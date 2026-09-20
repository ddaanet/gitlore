# Split report — `tests/index_compose.bats`

Pure-move split of the 1613-line, 90-test suite per
`plans/file-splits/brief-bats.md`. No test renamed, reworded, merged or
dropped; order within each file follows the original.

## Final partition

| File | Lines | Tests | Content |
|---|---|---|---|
| `tests/index_compose.bats` | 224 | 23 | Kept name. Helper units (`bullet_path` … `tier_of`) and every `check …` test, through "a mounted but unlisted tier is dormant, not an error". |
| `tests/index_compose_pins.bats` | 232 | 6 | Rule 7 banner + "compose refuses a tier moved sideways…" through "a tier that cannot be returned to its pin is refused untouched, with git's own message". |
| `tests/index_compose_pins_edge.bats` | 175 | 7 | `reroot_spaced()` through "a dormant tier moved off its pin does not refuse". |
| `tests/index_compose_projection.bats` | 294 | 12 | Splice-up/mirror-down, ordering, and unterminated-index sections. |
| `tests/index_compose_adoption.bats` | 209 | 11 | Adoption banner through "a dormant tier's carrier survives two consecutive passes untouched". |
| `tests/index_compose_dangling.bats` | 176 | 12 | Dangling, `cap_list`, failed writes, problem attribution. |
| `tests/index_compose_repair.bats` | 316 | 19 | `gitlore_repair_index` banner to end of file, including `file_mode()`. |

23+6+7+12+11+12+19 = 90 tests. All seven files are at or under the 380-line
cap; no further split was needed.

Helper file changes:
- `tests/helpers/tier-fixtures.bash` (existing file, +81 lines): gained
  `move_tier_off_pin`, `move_tier_off_pin_into_live`,
  `move_tier_sideways_off_pin`, `move_tier_diverged_off_pin`, and
  `pinned_store_with_tier` (originally lines 232–305), verbatim including
  their doc comments. Verified by grep that both `index_compose_pins.bats`
  and `index_compose_pins_edge.bats` call these before moving them; a
  same-file `commit_memory_state` call inside the newly-added
  `pinned_store_with_tier` triggered a fresh SC2119/SC2120 pair once
  co-located with the definition (bare-arg call next to its own def) — fixed
  with a scoped `# shellcheck disable=SC2119,SC2120` on `commit_memory_state`,
  matching the existing scoped-disable pattern in
  `tests/cc_hook_index_compose.bats`.
- `tests/helpers/index-compose.bash` (new file, 6 lines): `set_bullets()`
  (originally line 716), moved here because both
  `tests/index_compose_projection.bats` and `tests/index_compose_adoption.bats`
  call it (grep-verified: lines 974/1027 of the original are inside the
  adoption banner's range) — the brief's "OTHER than projection.bats" test.
  Loaded via `load helpers/index-compose` in both files.

## Deviations from the proposed partition

- The rule-7 banner (original lines 225–231, "# --- rule 7: an active tier
  must sit at its pin …") travels with the first test of that section (line
  306) into `tests/index_compose_pins.bats`, per the brief's "section banners
  travel with the first test" rule — even though the proposed partition's
  line pointer for that file started at 306. The five helper functions between
  the banner and that first test (232–305) go to the helper file instead of
  either `.bats` file, since both pins files call them.
- `set_bullets` went to a **new** helper file (`tests/helpers/index-compose.bash`)
  rather than `tests/helpers/tier-fixtures.bash`: it wraps
  `gitlore_compose_write` (the file under test), not a tier-mount fixture, so
  it does not fit tier-fixtures.bash's theme, and no other existing helper
  file in `tests/helpers/` covers index-compose write helpers.
- `bats_require_minimum_version 1.5.0` is kept only in
  `tests/index_compose_pins.bats`, `tests/index_compose_projection.bats` and
  `tests/index_compose_adoption.bats` — the only three files whose tests use
  `run !` (a 1.5 feature). Grep-verified: no `run !` or `run --separate-stderr`
  in `index_compose.bats`, `index_compose_pins_edge.bats`,
  `index_compose_dangling.bats` or `index_compose_repair.bats`, so those five
  files drop the line the original always carried.
- Every non-kept file's opening comment reads "Header as in
  tests/index_compose.bats" plus a 1-line description, per the brief; the full
  explanatory `load helpers/setup already sources …` comment block stays only
  in `tests/index_compose.bats`.

## References updated

Ran `grep -rn 'index_compose\.bats' docs/design.md docs/decisions.md
docs/references scripts tests skills agents justfile CLAUDE.md` (the brief's
exact command). Hits and disposition:

- `tests/commit_memory.bats:511` — "...stays pinned on the producer, in
  tests/index_compose.bats." referred to the sideways-tier test, now in
  `tests/index_compose_pins.bats`. Updated.
- `tests/commit_memory.bats:532` — "What is asserted is what
  tests/index_compose.bats' ahead-of-pin test asserts…" — that test is now in
  `tests/index_compose_pins.bats`. Updated.
- `tests/commit_memory.bats:894` — "Reuses the induction at
  tests/index_compose.bats:921: chmod a-w on the carrier's directory…" — line
  921 of the original was **already** stale before this split (it lands mid
  "removing an active tier's root line…" test, nowhere near a `chmod a-w`).
  The actual `chmod a-w memory/ddaanet` induction is "a failed index write is
  reported, not reported as success" (original line 1265), now in
  `tests/index_compose_dangling.bats`. Repointed the file name there and
  dropped the pre-existing wrong line number rather than inventing a new one
  the split didn't cause; left as `tests/index_compose_dangling.bats` without
  a line pin.
- `tests/helpers/triggers.bash:35` — `GITLORE_T_DANGLING`'s doc comment: 'Pinned
  by "a dangling pointer names the file and the index that carries it" in
  tests/index_compose.bats'. That exact title does not exist in the current
  suite (pre-existing drift, presumably from an earlier rename); the two
  actual assertions on `$GITLORE_T_DANGLING` are in "dangling reports a root
  bullet whose file is absent" and "a dangling pointer reports but never
  refuses: compose still writes", both now in
  `tests/index_compose_dangling.bats` (grep-verified). Updated the file name,
  left the stale title alone since fixing a pre-existing title drift is
  outside this split's scope.
- `tests/helpers/triggers.bash:23` and `scripts/cc-hooks/index-compose.sh:35`
  — both name `tests/cc_hook_index_compose.bats`, a different, untouched
  suite. Left alone.
- The seven "Header as in tests/index_compose.bats" lines in the new files
  themselves — expected, intentional, not stale.
- `justfile`, `scripts/run-bats.sh`, `tests/justfile_gates.bats`,
  `tests/plugin_distribution.bats`, `docs/references/testing.md` — no hits;
  none enumerate suites by name (`test-unit` globs `tests/*.bats`).
- A broader `grep -rl 'index_compose\.bats' .` (excluding `docs/changelog`)
  turns up ~100 more hits, all under `plans/` (frozen, dated plan/report
  documents from prior work, e.g. `plans/index-edit-propagation/reports/*.md`,
  `plans/tier-arrival-review-minors/*.md`). These are outside the brief's own
  grep scope (which deliberately omits `plans/`) and are historical records,
  not live references — left untouched.

## Verification

1. Test names preserved:
   `diff <(git show HEAD:tests/index_compose.bats | grep '^@test' | sort) <(cat tests/index_compose.bats tests/index_compose_pins.bats tests/index_compose_pins_edge.bats tests/index_compose_projection.bats tests/index_compose_adoption.bats tests/index_compose_dangling.bats tests/index_compose_repair.bats | grep -h '^@test' | sort)`
   → prints nothing.
2. No line lost:
   `diff <(git show HEAD:tests/index_compose.bats | sort) <(cat tests/index_compose.bats tests/index_compose_pins.bats tests/index_compose_pins_edge.bats tests/index_compose_projection.bats tests/index_compose_adoption.bats tests/index_compose_dangling.bats tests/index_compose_repair.bats tests/helpers/tier-fixtures.bash tests/helpers/index-compose.bash | sort) | grep '^<'`
   → prints nothing (no deliberate header replacements needed to list — every
   original line, including headers/loads/setup, still appears at least once
   across the union).
3. `wc -l`: `index_compose.bats` 224, `index_compose_pins.bats` 232,
   `index_compose_pins_edge.bats` 175, `index_compose_projection.bats` 294,
   `index_compose_adoption.bats` 209, `index_compose_dangling.bats` 176,
   `index_compose_repair.bats` 316; `tests/helpers/tier-fixtures.bash` 293;
   `tests/helpers/index-compose.bash` 6.
4. `scripts/run-bats.sh tests/index_compose.bats tests/index_compose_pins.bats tests/index_compose_pins_edge.bats tests/index_compose_projection.bats tests/index_compose_adoption.bats tests/index_compose_dangling.bats tests/index_compose_repair.bats`
   → `bats: 90 passed, 0 failed`. `git show HEAD:tests/index_compose.bats | grep -c '^@test'` = 90. Match.
5. `just lint` → `lint-shell: 141 files clean`.
6. `just test-unit` — ran three times because the working tree is shared with
   several sibling split agents editing other files concurrently in this same
   session. First run: 976 passed, 0 failed, but exited 1 with "gate: inputs
   changed while the checks ran; the pass was NOT recorded" (a sibling agent's
   concurrent edit invalidated the sentinel-guard hash mid-run, and my own
   reference-sweep edits to `tests/commit_memory.bats` /
   `tests/helpers/triggers.bash` overlapped it too — not a test failure).
   Re-ran once inputs settled: `.git/gitlore/gates/test-unit` recorded a fresh
   hash (`2996344278 1455228`, distinct from the pre-split gate), confirming a
   clean recorded pass on the final tree. No failure was caused by the split;
   `test-integration` is not needed (suite name doesn't start with
   `integration_`).

Not committed, per instructions.
