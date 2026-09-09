# Item 3.1 slice 5 — GREEN

Two changes to the SUTs, one test deletion. `109 passed, 0 failed` on
`tests/index_sync.bats tests/cc_hook_index_compose.bats`, matching the test
review's 110 minus the retired case. Nothing committed; the tree is dirty and
unstaged.

## What made each case pass

1. **`a failed relay write tells the subagent it was not staged`** —
   `scripts/cc-hooks/index-compose.sh`'s `gitlore_relay_write ... || true` on
   the keyed branch became `if ! gitlore_relay_write ...; then` appending the
   not-staged line to `$GITLORE_COMPOSE_CTX`. The case's last assertion
   (`[[ "$output" == *"could not be staged for the parent session"* ]]` on
   `.hookSpecificOutput.additionalContext`) now passes because the appended text
   is emitted on that channel.
2. **`an unkeyed run leaves a non-marker alone`** — stayed green; unaffected by
   either change, since the fixture takes the unkeyed drain branch, whose
   `-type f` filter still excludes the directory squat and the framing/report
   assertions were already satisfied before this slice.
3. **`the drain survives a gitdir it cannot write`** —
   `scripts/lib/index-sync.sh`'s `gitlore_relay_drain` bare `rm -f "$marker"`
   became `rm -f "$marker" || true`. The synthetic caller's
   `[ "$status" -eq 0 ]` and `[[ "$output" == *"OWN REPORT"* ]]` now both hold:
   the drain no longer propagates the remove's failure under the caller's
   `set -euo pipefail`, so the caller reaches its own `printf` after the drain
   returns.

## Confirmations

- **The not-staged line goes on `additionalContext`, not `systemMessage`.** In
  both hooks it is appended to `$GITLORE_COMPOSE_CTX` / `$ctx`, which feed the
  `hookSpecificOutput.additionalContext` field in each hook's `jq -n` emission;
  `$GITLORE_COMPOSE_SYSMSG` / `$sysmsg` are untouched by the new code.
- **Appended after the write.** Both `if !` blocks sit inside the branch that
  already ran the write; the append happens only once the write's own status is
  known, so the failure line is never part of what that write attempted to
  stage.
- **The deletion removed only the one case.**
  `git diff -- tests/cc_hook_index_compose.bats` shows the retired block
  (`# Item 3.1 slice 4, Group B ...` comment through
  `@test "an unkeyed run survives a non-file squatting on a marker name"`'s
  closing `}`) removed and nothing else in that file touched besides the slice-5
  additions already present from RED. `tests/index_sync.bats` carries no
  deletion — only the slice-5 RED addition, present before this dispatch
  started.

Also updated: `gitlore_relay_drain`'s header comment, which slice 4's review had
corrected to state the `rm -f`-on-unwritable-gitdir residual as the reason
"Always returns 0" did not fully hold. That residual is now closed, so the
comment states the plain fact instead.

## Scope check

`git diff --stat`:

```
scripts/cc-hooks/index-compose.sh   | 18 ++++++++---
scripts/cc-hooks/index-sync-post.sh | 19 +++++++++---
scripts/lib/index-sync.sh           | 14 +++++----
tests/cc_hook_index_compose.bats    | 60 +++++++++++++++++++++++++++++++------
tests/index_sync.bats               | 48 +++++++++++++++++++++++++++++
```

Only the four files named in scope, plus the two frozen `.bats` files (RED's
additions untouched, one case deleted from `cc_hook_index_compose.bats` as
directed). `session-start.sh` and every other file listed out of scope:
untouched.

## Checks that passed, by name

- `./scripts/run-bats.sh tests/index_sync.bats tests/cc_hook_index_compose.bats`
  — **109 passed, 0 failed**.
- `./scripts/run-bats.sh tests/cc_hook_session_start.bats tests/cc_hook_add_tier.bats tests/index_compose.bats tests/cc_hook_post_tool_use.bats tests/lib_util.bats tests/cc_hook_worktree_remove.bats tests/merge_memory.bats tests/tier_discovery.bats tests/tier_divergence.bats`
  — **205 passed, 0 failed**.
- `shellcheck -s bash scripts/lib/index-sync.sh scripts/cc-hooks/index-compose.sh scripts/cc-hooks/index-sync-post.sh`
  — clean.
- `./scripts/lint-shell.sh` — **137 files clean**.
- `git diff -- scripts/` — matches the test review's simulated GREEN (§1)
  verbatim for the two hooks, plus the drain's `|| true` and its corrected doc
  comment.
- `git status --porcelain` — the three SUT files and
  `tests/cc_hook_index_compose.bats` modified, `tests/index_sync.bats` carrying
  only the pre-existing RED addition; nothing staged, nothing committed.
