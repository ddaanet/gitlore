# Item 1.1 slice 3 — RED report

Mode: RED. `scripts/lib/resolve.sh` untouched —
`git diff --exit-code scripts/lib/resolve.sh` reports no diff.

## Files changed

- `tests/commit_memory.bats` — two new cases, appended after the existing
  mid-merge case:
  `an off-pin compose refusal is reported and does not abort the commit` and
  `a compose write failure aborts the commit`.
- `tests/index_compose.bats` — rewrote the stale two-line comment on the
  existing rc-2 case
  (`a failed index write is reported, not reported as success`, previously lines
  930-931). Verified against `scripts/lib/index-compose.sh:656`
  (`gitlore_compose_write` builds its temp path via
  `git -C "$(dirname -- "$file")" rev-parse --absolute-git-dir`, i.e. inside the
  store's own gitdir) and `:676` (the `mv "$tmp" "$file"`). The old comment
  claimed the chmod stops the temp file being *created there*; it actually fails
  the `mv` that lands the finished file into the carrier's directory — the temp
  file is never written there at all. New wording:

  > No write permission on the carrier's directory: gitlore_compose_write's temp
  > file lands in the store's own gitdir, not here, but the `mv` into this
  > directory still needs write access to create the destination entry, so that
  > `mv` is what fails.

  Only the comment changed; the case's assertions and body are untouched.

`git diff --stat`:
```
tests/commit_memory.bats | 49 ++++++++++++++++++++++++++++++++++++++++++++++++
tests/index_compose.bats |  6 ++++--
2 files changed, 53 insertions(+), 2 deletions(-)
```

## Suite run

`scripts/run-bats.sh tests/commit_memory.bats`:
```
not ok 12 an off-pin compose refusal is reported and does not abort the commit
# (in test file tests/commit_memory.bats, line 182)
#   `[[ "$stderr" == *"tier composition refused"* ]]' failed
not ok 13 a compose write failure aborts the commit
# (in test file tests/commit_memory.bats, line 203)
#   `[ "$status" -ne 0 ]' failed

bats: 11 passed, 2 failed
```

Both new cases fail on their own assertion, confirmed by isolating each with
`bats -f`:

**rc 1 — off-pin refusal.** Fixture: `make_tier_in_memory ddaanet` pins the tier
in memory's index at its initial commit;
`git -C memory/ddaanet commit -q --allow-empty -m "moved outside /gitlore:merge"`
advances the tier's worktree HEAD without ever staging that move into memory's
index (the tier's own worktree stays clean, so `gitlore_sync_tiers_to_live` has
nothing to commit there and the mismatch survives). Root carries a line for the
tier (`seed_root_bullet "ddaanet/shared.md" "fresh hook"`), so memory is dirty
and the tier is active. `-m` supplies a fresh approved summary. Assertions, in
order: exit 0 (passed), `git -C memory rev-parse HEAD` advanced past its pre-run
value (passed — the commit proceeded), `$stderr` contains
`tier composition refused` (**failed — line 182, the reported failure line**),
`$stderr` contains `is checked out at` (not reached). Today's
`gitlore_compose "$mempath" >/dev/null || true` discards
`gitlore_compose_check_pins`' problem lines entirely, so nothing reaches stderr
— the red is exactly the missing report the dispatch predicted, not a fixture or
symbol error.

**rc 2 — write failure.** Fixture: `make_tier_in_memory ddaanet` +
`seed_tier_bullet`/`seed_root_bullet` to disagree (so compose has something to
write), then `chmod a-w memory/ddaanet` before `run`, restored immediately
after. Assertions, in order: `$status -ne 0`
(**failed — line 203, the reported failure line**), `HEAD` unchanged (not
reached), the approved `gitlore_commit_msg_file` still present (not reached).
`|| true` swallows `gitlore_compose`'s rc 2 the same as rc 1, so the commit
proceeds despite the half-written carrier — exit is 0, which is the "commit
having proceeded" red the dispatch named, not an ERROR.

The rc-2 case ran as the non-root sandbox user, so the
`[ "$(id -u)" -eq 0 ] && skip` guard did not fire — the case was genuinely
exercised, not skipped.

## Lint

`shellcheck -s bash tests/commit_memory.bats tests/index_compose.bats` — exit 0,
no findings.

## Scope check

Nothing else touched: no other test file, no `scripts/`, no `docs/`. Slice 1 and
slice 2 cases, and the rc-2 test *body* at `tests/index_compose.bats:921`, are
unmodified — only its comment changed, per the item's explicit direction.
`just precommit` was not run (by design; the suite is red).
