# Item 1.1 / slice 2 — GREEN

**Test:** `a repair whose commit build fails walks back and points upstream`
(`tests/merge_memory.bats:594-623`). Passes.

## Change

`scripts/lib/resolve.sh`:

- `gitlore_adopt_report_refusal_and_walk_back` gains an optional sixth
  argument, `<remedy>`, passed through to `gitlore_adopt_walk_back_tier`
  (empty keeps that helper's default). Comment updated.
- In `gitlore_adopt_repair_arrival`, the `[ -z "$repair" ]` block after the
  scratch cleanup now branches on `$remedy`: non-empty (the unrepairable
  arm already computed one) still calls `gitlore_adopt_walk_back_tier`
  directly; empty (arrival read, pin read, rewrite, or commit build failed)
  calls `gitlore_adopt_report_refusal_and_walk_back` with `$composed` and
  `Run /gitlore:merge again.` instead — printing the refusal header and
  walking back with that remedy.
- The `live`-advance arm (the `push -q . "$repair:refs/heads/live"` failure)
  is rewired the same way: it now calls
  `gitlore_adopt_report_refusal_and_walk_back` with `$composed` and
  `Run /gitlore:merge again.` instead of the bare `gitlore_adopt_walk_back_tier`.
- The checkout-follow arm is untouched (Item 1.1/4).

A caught regression during GREEN: passing no sixth argument at the two
unaffected call sites (`gitlore_adopt_tier_into_root`'s own refusal, and
the retry-refusal call) tripped `set -u` on `$6` inside
`gitlore_adopt_report_refusal_and_walk_back`. Fixed with `remedy="${6:-}"`.

## Tests run

- `scripts/run-bats.sh tests/merge_memory.bats --filter "commit build fails walks back and points upstream"` — 1 passed.
- `scripts/run-bats.sh tests/merge_memory.bats` (whole file) — 37 passed, 0 failed.
- `grep -rl "Fix the store\|could not be repaired\|keeps what arrived\|Run /gitlore:merge again" tests/` — only `tests/merge_memory.bats`; already covered by the whole-file run above.
- `shellcheck scripts/lib/resolve.sh tests/merge_memory.bats` — clean.

## Left for later slices

- `<live_holds>` and the retry-refusal call's wording (1.1/3).
- The checkout-follow arm (1.1/4).
- Item 1.2 (scratch dir under `$TMPDIR`).
