# Split report — `tests/justfile_gates.bats`

## Partition

| File | Lines | Tests |
| --- | --- | --- |
| `tests/justfile_gates.bats` | 287 | 13 |
| `tests/justfile_format_docs.bats` | 107 | 3 |
| `tests/justfile_gate_sentinel.bats` | 161 | 9 |
| `tests/helpers/justfile-gates.bash` | 72 | (helper, no tests) |

Total: 25 tests, matching `git show HEAD:tests/justfile_gates.bats | grep -c '^@test'`.

Followed the proposed partition exactly:

- `tests/justfile_gates.bats` keeps everything from the first test through
  "every top-level entry is either a gate input or a deliberate exclusion".
- `tests/justfile_format_docs.bats` takes the three format-docs / wrap-set
  tests.
- `tests/justfile_gate_sentinel.bats` takes the banner
  "# --- the gate sentinel itself ---" through the end, with the banner
  placed directly above its first test ("an unchanged input set skips; a
  changed one re-runs"), matching the rule that a section banner travels with
  the first test of its section — not above the `gate_verdict` helper that
  precedes it.

## Helper file

`tests/helpers/justfile-gates.bash` — functions used by more than one
resulting file:

- `setup()` / `teardown()` — stub-dir and gate-repo cleanup, used by all three
  suites (the format-docs suite needs `STUB_DIR` too).
- `just_here()` — used directly by `justfile_gates.bats` tests and internally
  by `setup_gate_repo`, which `justfile_gate_sentinel.bats` also calls.
- `setup_gate_repo()` — used by one test in `justfile_gates.bats`
  ("sentinel-guard skips only when...") and by five tests in
  `justfile_gate_sentinel.bats`.
- `in_gate_repo()` — used directly in both of the above suites and internally
  by `gate_record`/`gate_verdict`.
- `gate_record()` — used by one test in `justfile_gates.bats` and by six
  tests in `justfile_gate_sentinel.bats`.

Not moved (single-file, left above their first user as before):

- `guard_line()`, `guard_input_files()`, `all_suites()`, `discovered_suites()`
  — used only within `tests/justfile_gates.bats`.
- `gate_verdict()` — used only within `tests/justfile_gate_sentinel.bats`,
  where it stays, positioned above its first user (before the banner, per the
  original file's order: `gate_verdict` was defined at the top of the
  original file, ahead of the banner it now sits directly above).

## Deviations

None from the proposed partition. The `gate_verdict` placement (helper
function ahead of the banner, banner ahead of the first `@test`) is a direct
application of "banner travels with the first test of its section", not a
deviation.

## References

`grep -rn 'justfile_gates\.bats' docs/design.md docs/decisions.md docs/references scripts tests skills agents justfile CLAUDE.md`:

- `tests/justfile_gates.bats:235` — the literal
  `[[ "$output" == *"tests/justfile_gates.bats"* ]]` inside "the unit gate's
  inputs leave the integration suites out...". Left alone per CAUTION (2):
  this test stays in the original file and the literal must stay unchanged.
- `justfile:26` — comment: "The `justfile_gates` suite guards both: every
  declared path must exist, and every top-level entry must be declared here
  or in that suite's exclusion list." Both tests it names ("every declared
  gate input exists in the repo" and "every top-level entry is either a gate
  input or a deliberate exclusion") remain in `tests/justfile_gates.bats`, so
  the reference still points correctly — left unchanged.

Broader `grep -rln 'justfile_gates'` (excluding `docs/changelog/` and
`.claude/`) also hit several files under `plans/*/reports/` and
`plans/file-splits/brief-bats.md` — historical run reports and the brief
itself, none of which name a specific test or section that moved; left
unchanged as out of scope for a code/doc reference sweep.

No hits in `docs/references/testing.md` or `tests/plugin_distribution.bats`.

## Verification

1. Test names preserved:
   ```
   diff <(grep '^@test' "$TMPDIR/justfile_gates.orig.bats" | sort) <(cat tests/justfile_gates.bats tests/justfile_format_docs.bats tests/justfile_gate_sentinel.bats | grep -h '^@test' | sort)
   ```
   Result: no output.

2. No line lost:
   ```
   diff <(sort "$TMPDIR/justfile_gates.orig.bats") <(cat tests/justfile_gates.bats tests/justfile_format_docs.bats tests/justfile_gate_sentinel.bats tests/helpers/justfile-gates.bash | sort) | grep '^<'
   ```
   Result: no output (the only `<`-only line on a first pass, the
   "# --- the gate sentinel itself ---" banner, was fixed by adding it to
   `justfile_gate_sentinel.bats`; the rerun above is clean).

3. `wc -l`:
   ```
   287 tests/justfile_gates.bats
   107 tests/justfile_format_docs.bats
   161 tests/justfile_gate_sentinel.bats
    72 tests/helpers/justfile-gates.bash
   ```
   All at or under 380.

4. `scripts/run-bats.sh tests/justfile_gates.bats tests/justfile_format_docs.bats tests/justfile_gate_sentinel.bats`:
   ```
   bats: 25 passed, 0 failed
   ```
   `git show HEAD:tests/justfile_gates.bats | grep -c '^@test'` = 25 — matches.

5. `just lint` — deferred to the end of this batch (step 5 in the brief),
   run once after all three suites are split.
