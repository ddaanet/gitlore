# Split report — `tests/resolve_compose.bats`

## Final partition

| File | Lines | `@test` count |
| --- | --- | --- |
| `tests/resolve_compose.bats` | 298 | 11 |
| `tests/resolve_compose_continuation.bats` | 266 | 7 |
| `tests/resolve_compose_root_index.bats` | 145 | 6 |
| `tests/resolve_compose_refusals.bats` | 151 | 5 |
| `tests/helpers/resolve-compose.bash` (new) | 59 | — |

Total moved tests: 29 (11 + 7 + 6 + 5), matching
`grep -c '^@test' <original>` = 29. Original was 864 lines; every resulting
file is well under the 380-line cap, so no further split was needed.

## Helper file — `tests/helpers/resolve-compose.bash`

Contents, one line each:

- `PRE_COMMIT="$PLUGIN_ROOT/scripts/git-hooks/pre-commit"` — file-level var, used by all four resulting files.
- `PRE_PUSH="$PLUGIN_ROOT/scripts/git-hooks/pre-push"` — file-level var, used by all four resulting files.
- `RESOLVE="$PLUGIN_ROOT/scripts/resolve.sh"` (with `# shellcheck disable=SC2034` — used only by callers' `@test` bodies) — file-level var, used by all four resulting files.
- `setup()` — calls `setup_tmp_repo` and exports `CLAUDE_PLUGIN_ROOT`; identical in every original test run.
- `teardown()` — calls `teardown_tmp_repo`.
- `approve()` — writes an approved commit-message file; used in `resolve_compose.bats`, `resolve_compose_root_index.bats` and `resolve_compose_refusals.bats`.
- `mount_tier_at_live()` — mounts a tier detached on `live`; used in `resolve_compose.bats` and `resolve_compose_root_index.bats`, and internally by `prepare_tier_merge_with_new_lines`.
- `diverge_memory_with_index()` — commits a root index then moves `live` sideways; used in `resolve_compose.bats` and `resolve_compose_root_index.bats`.
- `prepare_tier_merge_with_new_lines()` — prepares and synthesizes a tier merge; used in all three of `resolve_compose.bats`, `resolve_compose_continuation.bats` and `resolve_compose_refusals.bats`.

## Deviations from the proposed partition

None in file membership or boundaries — the four-way split matches the brief
exactly at the given line numbers. Two helpers proposed for possible sharing
turned out, on grep, to be used by only one resulting file each and were kept
local rather than moved to the helper file:

- `duplicate_tier_carrier()` — every call site (lines 170, 189, 204, 219, 256,
  279, 301 of the original) falls inside the 57–353 range that became
  `tests/resolve_compose.bats`. Kept local, in its original position (above
  the first test that calls it — the head-vs-live duplicate test).
- `prepare_tier_merge_head_vs_live()` — its only call site (line 184) is also
  inside that same range. Kept local, in its original position.
- `decline_pushes_to()` — both call sites (747, 848) fall inside the
  735–864 range that became `tests/resolve_compose_refusals.bats`. Kept
  local there, as the proposed partition already placed it.

## Reference sweep

Ran the brief's exact command:

```
grep -rn 'resolve_compose\.bats' docs/design.md docs/decisions.md docs/references scripts tests skills agents justfile CLAUDE.md
```

No hits. A broader sweep (`grep -rln 'resolve_compose' .` excluding `.git`)
found only mentions under `plans/**/reports` and `plans/**/runbook.md` /
`outline.md` / `dispatch-constraints.md` — historical planning artifacts
outside the brief's reference-sweep scope (not `docs/`, `scripts/`, `tests/`,
`skills/`, `agents/`, `justfile`, or `CLAUDE.md`). None updated.

`justfile`, `scripts/run-bats.sh`, `tests/justfile_gates.bats`,
`tests/plugin_distribution.bats`, `docs/references/testing.md` — none
enumerate bats suites by name that would need repointing.

## Verification

1. Test names preserved:
   ```
   diff <(grep '^@test' "$TMPDIR/resolve_compose.orig.bats" | sort) \
        <(cat tests/resolve_compose.bats tests/resolve_compose_continuation.bats \
              tests/resolve_compose_root_index.bats tests/resolve_compose_refusals.bats \
          | grep -h '^@test' | sort)
   ```
   Result: no output (exit 0).

2. No line lost:
   ```
   diff <(sort "$TMPDIR/resolve_compose.orig.bats") \
        <(cat tests/resolve_compose.bats tests/resolve_compose_continuation.bats \
              tests/resolve_compose_root_index.bats tests/resolve_compose_refusals.bats \
              tests/helpers/resolve-compose.bash | sort) | grep '^<'
   ```
   Result: no output — every line of the original is accounted for in some
   resulting file or the helper.

3. `wc -l` of every resulting file:
   ```
   298 tests/resolve_compose.bats
   266 tests/resolve_compose_continuation.bats
   145 tests/resolve_compose_root_index.bats
   151 tests/resolve_compose_refusals.bats
    59 tests/helpers/resolve-compose.bash
   ```

4. `scripts/run-bats.sh tests/resolve_compose.bats tests/resolve_compose_continuation.bats tests/resolve_compose_root_index.bats tests/resolve_compose_refusals.bats`:
   ```
   bats: 29 passed, 0 failed — full log: /tmp/claude-1000/gitlore-bats.uM8mV0
   ```
   29 passed matches `grep -c '^@test' "$TMPDIR/resolve_compose.orig.bats"` = 29, zero failed.

5. `just lint`:
   ```
   lint-shell: 141 files clean
   ```

6. `just test-unit` not run, per the brief — the main session runs it.
