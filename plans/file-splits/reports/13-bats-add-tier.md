# Split report — `tests/add_tier.bats`

## Partition

Followed the proposed partition exactly — no deviation.

- `tests/add_tier.bats` — 287 lines, 21 tests. Invocation path (banner at
  original line 14), mount (line 20), create (line 208), and the composed
  whole (line 275).
- `tests/add_tier_intent.bats` — 204 lines, 17 tests. Intent parsing (banner
  at original line 14 of this file), validation, and url transport bounds
  (original lines 225–415).
- `tests/helpers/add-tier.bash` — new, 23 lines: `ADD_TIER=` (`shellcheck
  disable=SC2034`, used only by callers now), `setup()` (tmp repo +
  `CLAUDE_PLUGIN_ROOT` + the `GIT_CONFIG_*` local-submodule allowance),
  `teardown()`, and `write_intent()`. All four are used by both resulting
  files.

Order inside each file follows the original; each file repeats the shebang,
the `SC2030,SC2031` disable (both files still have per-test exports consumed
in the same test), `bats_require_minimum_version`, and the three original
`load` lines plus the new `load helpers/add-tier`.

## References

`grep -rn '\badd_tier\.bats\b' docs/design.md docs/decisions.md docs/references scripts tests skills agents justfile CLAUDE.md`
found one raw hit — `scripts/cc-hooks/add-tier-batch.sh:59`, naming
`tests/cc_hook_add_tier.bats` — but that's a different suite entirely; the
substring `add_tier.bats` inside `cc_hook_add_tier.bats` matched the plain
grep, not a real reference to this file. No genuine reference to
`tests/add_tier.bats` or to a moved test's title was found anywhere in scope.

## Verification

1. Test names preserved:
   `diff <(grep '^@test' "$TMPDIR/add_tier.orig.bats" | sort) <(cat tests/add_tier.bats tests/add_tier_intent.bats | grep -h '^@test' | sort)`
   → prints nothing.
2. No line lost:
   `diff <(sort "$TMPDIR/add_tier.orig.bats") <(cat tests/add_tier.bats tests/add_tier_intent.bats tests/helpers/add-tier.bash | sort) | grep '^<'`
   → prints nothing.
3. `wc -l`:
   - `tests/add_tier.bats`: 287
   - `tests/add_tier_intent.bats`: 204
   - `tests/helpers/add-tier.bash`: 24
4. `scripts/run-bats.sh tests/add_tier.bats tests/add_tier_intent.bats`
   → `bats: 38 passed, 0 failed`. Original `@test` count:
   `grep -c '^@test' "$TMPDIR/add_tier.orig.bats"` = 38. Match. (The run also
   printed two `<sandbox_violations>` denials for `127.0.0.1:1` and
   `127.0.0.1:22` — expected noise from the url-transport-bounds tests that
   deliberately probe unreachable/refused transports, not a test failure.)
5. `just lint` — deferred to the end of the batch (all three suites), per the
   dispatch.

Step 6 (whole-suite `just test-unit`) intentionally not run — left to the
main session per the brief.
