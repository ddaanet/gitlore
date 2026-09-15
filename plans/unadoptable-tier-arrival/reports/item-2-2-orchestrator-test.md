# Item 2.2 — orchestrator-added test

Author: the orchestrator, after `item-2-2-code-review.md` reported a surviving
mutant (a nonexistent pin path passed to `gitlore_repair_index` left all seven
repair tests green). Committed in `94687cb` with the code-review fixes.

Test: `tests/merge_memory.bats` "a take's repair keeps the duplicate its pin
lacks". A first take adopts `- [A](a.md) — old`; the arrival then appends
`- [A](a.md) — new`, so a repair blind to the pin keeps the older, first line.

Red evidence: in `scripts/lib/resolve.sh`, the call
`gitlore_repair_index "$scratch/arrival" "$scratch/pin" "$tierpath"` was mutated
to pass `"$scratch/nopin"`:

    not ok 1 a take's repair keeps the duplicate its pin lacks
    # (in test file tests/merge_memory.bats, line 614)
    #   `[ "$(grep -cxF -- '- [A](a.md) — new' "$BATS_TEST_TMPDIR/repaired.md")" -eq 1 ]' failed

Restored (no `nopin` left in the file, confirmed by grep), then green:
`bats: 1 passed, 0 failed`. `shellcheck tests/merge_memory.bats` clean.
