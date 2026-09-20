# Split report — `tests/check_docs_links.bats`

## Partition

| File | Lines | Tests |
| --- | --- | --- |
| `tests/check_docs_links.bats` | 209 | 22 |
| `tests/check_docs_links_decisions.bats` | 240 | 21 |
| `tests/helpers/check-docs-links.bash` | 37 | (helper, no tests) |

Total: 43 tests, matching `git show HEAD:tests/check_docs_links.bats | grep -c '^@test'`.

Followed the proposed partition exactly: `tests/check_docs_links_decisions.bats`
takes both decisions sections — "decisions: stubs and bodies" (banner at the
original's line 83) and "decisions: a node's own enumeration" (banner at 272)
— straight through to the blank line before the "orphans" banner. The
original keeps "broken links" (44), "orphans" (311), "scope, suppression,
reporting" (355) and "the line cap" (372), in original order.

## Helper file

`tests/helpers/check-docs-links.bash` — `setup()`, `teardown()`, the
`CHECKER` variable, `plant_decisions()` and `plant_ref()`, all used by both
resulting `.bats` files. `CHECKER` is exported (the original left it
unexported, safe only because every user lived in the same file); exporting
follows `helpers/setup.bash`'s `PLUGIN_ROOT` precedent and is what satisfies
shellcheck's "appears unused" (SC2034) once the variable's readers move to a
different file than its writer.

The original file's two `# shellcheck disable=` header comments split by what
each disabled line actually needs where it now lives:

- `check-docs-links.bash` keeps `disable=SC2016` (the backtick-heavy fixture
  bodies in `plant_decisions`/`plant_ref` calls survive there too, e.g.
  `` 'The fixture writes `D77` into the manifest.' `` moved into the
  decisions file, and `plant_ref` itself takes no such literal — the
  directive travels with the helper file for its own body's `printf` sake
  regardless).
- Both `.bats` files keep `disable=SC2154` ($status/$output from `run`).
- Both `.bats` files also keep `disable=SC2016`: each still plants at least
  one literal-backtick fixture line (e.g. `` `- [A](a.md) — hook` `` in the
  original, `` `D77` `` in the decisions file).

## Deviations

None from the proposed partition.

## References

`grep -rn 'check_docs_links\.bats' docs/design.md docs/decisions.md docs/references scripts tests skills agents justfile CLAUDE.md`:
no hits.

Broader `grep -rln 'check_docs_links'` (excluding `docs/changelog/` and
`.claude/`) hit only files under `plans/*/reports/` and
`plans/index-edit-propagation/runbook-review.md` — historical run reports,
none naming a specific test or section that moved. Left unchanged as out of
scope for a code/doc reference sweep.

## Verification

1. Test names preserved:
   ```
   diff <(grep '^@test' "$TMPDIR/check_docs_links.orig.bats" | sort) <(cat tests/check_docs_links.bats tests/check_docs_links_decisions.bats | grep -h '^@test' | sort)
   ```
   Result: no output.

2. No line lost:
   ```
   diff <(sort "$TMPDIR/check_docs_links.orig.bats") <(cat tests/check_docs_links.bats tests/check_docs_links_decisions.bats tests/helpers/check-docs-links.bash | sort) | grep '^<'
   ```
   Result: no output.

3. `wc -l`:
   ```
   209 tests/check_docs_links.bats
   240 tests/check_docs_links_decisions.bats
    37 tests/helpers/check-docs-links.bash
   ```
   All under 380.

4. `scripts/run-bats.sh tests/check_docs_links.bats tests/check_docs_links_decisions.bats`:
   ```
   bats: 43 passed, 0 failed
   ```
   `git show HEAD:tests/check_docs_links.bats | grep -c '^@test'` = 43 — matches.

5. `just lint` — deferred to the end of this batch, run once after all three
   suites are split.
