# Split report — `tests/cc_hook_session_start.bats`

## Partition

- `tests/cc_hook_session_start.bats` — 337 lines, 20 tests. No-op/config/
  wiring/commit-protocol/detach/ff-merge/divergence/dangling-pointer/sentinel
  tests, plus the linked-worktree case (original lines 43–355, dropping the
  trailing blank separator line). `assert_session_start_did_nothing` stayed
  here — its only callers are in this file (line 493's mention of it in the
  removed-case comment is prose, not a call).
- `tests/cc_hook_session_start_relay.bats` — 174 lines, 5 tests. The relay
  drain group per the hint: own-session drain vs. peer marker, 7-day sweep,
  no-marker-no-framing, and the unreadable-marker residual case (original
  lines 357–506). `RELAY_FRAMING` and `run_session_start_with_session()`
  moved here — both are used only by this group — positioned above their
  first use, same as they sat in the original file relative to the whole
  suite.
- `tests/helpers/cc-hook-session-start.bash` — new, 11 lines: `SESSION_START=`
  (`shellcheck disable=SC2034`, used only by callers now), `setup()`,
  `teardown()`. Both moved here because both resulting files use the hook
  path and share the worktree-aware teardown.

No deviation from the hint: the relay/marker-drain group was already a clean
boundary and left both files well under 380 lines without pulling in an
adjacent topic.

## References

`grep -rn 'cc_hook_session_start\.bats' docs/design.md docs/decisions.md docs/references scripts tests skills agents justfile CLAUDE.md`
→ no hits. Nothing referenced the suite by name or by a moved test's title
outside the suite itself.

## Verification

1. Test names preserved:
   `diff <(grep '^@test' "$TMPDIR/cc_hook_session_start.orig.bats" | sort) <(cat tests/cc_hook_session_start.bats tests/cc_hook_session_start_relay.bats | grep -h '^@test' | sort)`
   → prints nothing.
2. No line lost:
   `diff <(sort "$TMPDIR/cc_hook_session_start.orig.bats") <(cat tests/cc_hook_session_start.bats tests/cc_hook_session_start_relay.bats tests/helpers/cc-hook-session-start.bash | sort) | grep '^<'`
   → prints nothing. The one line deliberately not reproduced verbatim
   anywhere is the blank separator that sat between the last kept test and
   the relay-group's opening comment (original line 356) — dropped as a
   redundant trailing blank at the end of the kept file, not lost content.
3. `wc -l`:
   - `tests/cc_hook_session_start.bats`: 337
   - `tests/cc_hook_session_start_relay.bats`: 174
   - `tests/helpers/cc-hook-session-start.bash`: 12
4. `scripts/run-bats.sh tests/cc_hook_session_start.bats tests/cc_hook_session_start_relay.bats`
   → `bats: 25 passed, 0 failed`. Original `@test` count:
   `grep -c '^@test' "$TMPDIR/cc_hook_session_start.orig.bats"` = 25. Match.
5. `just lint` — deferred to the end of the batch (all three suites), per the
   dispatch.

Step 6 (whole-suite `just test-unit`) intentionally not run — left to the
main session per the brief.
