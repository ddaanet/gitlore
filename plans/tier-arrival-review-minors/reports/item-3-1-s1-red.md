# Item 3.1 / Slice 1 — RED

**Test added:** `tests/index_compose.bats:1349`
(`@test "a duplicate dropped from the end terminates the new last line"`), in
the repair section right after "welds are split before duplicates are resolved".

## Fixture

Unterminated index, empty pin, last line a duplicate of an earlier bullet:

```
- [K](kept.md) — kept
- [A](a.md) — hook
- [A](a.md) — hook      <- last line, unterminated, duplicate of line 2
```

Preconditions asserted before the repair runs:
- `tail -c 1 file.md | wc -l` = 0 (unterminated)
- `grep -c -F -- '- [A](a.md) — hook' file.md` = 2 (the duplicate is present)

## Result

```
$ scripts/run-bats.sh tests/index_compose.bats --filter "duplicate dropped from the end"
not ok 1 a duplicate dropped from the end terminates the new last line
# (in test file tests/index_compose.bats, line 1361)
#   `cmp -s file.md expected.md' failed
bats: 0 passed, 1 failed
```

Repair's own status assertion (`[ "$status" -eq 0 ]`) and the report-line
assertion both pass; the test fails only on the `cmp -s` byte-equality check,
confirming the fixture and the repair's mechanics work as expected and the red
is specifically the termination bug.

Actual vs. expected bytes (`od -c`), isolating the difference to the missing
trailing newline:

```
--- actual (44 bytes) ---
... m   d   )     342 200 224       h   o   o   k
--- expected (45 bytes) ---
... m   d   )     342 200 224       h   o   o   k  \n
```

Full-file run: `scripts/run-bats.sh tests/index_compose.bats` → 81 passed, 1
failed (only the new test; no regressions).

`shellcheck tests/index_compose.bats` → exit 0.

No commit made; `scripts/lib/index-compose.sh` untouched.
