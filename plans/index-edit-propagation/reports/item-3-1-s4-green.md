# Item 3.1 slice 4 — GREEN

Three changes, all in `scripts/lib/index-sync.sh` except the two `|| true`
guards in the PostToolBatch hooks. Tree left dirty, nothing committed.

## Per-test disposition

1. **`a failed relay write leaves the subagent's own report intact`**
   (`tests/cc_hook_index_compose.bats`) — passes now via the empty-id guard's
   sibling fix: `gitlore_relay_write` in `index-compose.sh`'s keyed branch is
   now called with `|| true`. Before this, the write's own failure ("Is a
   directory" on the squatted marker path) propagated under `set -e` and took
   the hook down before its `jq -n` emission ran. Kept green: the four
   born-green Group B cases in this file were unaffected — verified by the
   full-suite run below.

2. **`relay_write refuses an empty agent id`** (`tests/index_sync.bats`) —
   passes via the new guard `[ -n "$agent_id" ] || return 1` at the top of
   `gitlore_relay_write`, before `gitlore_relay_marker_file` is even called.
   Confirmed the guard precedes every filesystem effect: it is the function's
   first statement after the `local` declaration, ahead of the marker-path
   resolution and every read/write below it.

3. **`relay_write refuses a squatted marker path`** — stayed green; untouched
   by any of the three changes. `gitlore_relay_write`'s existing behavior on a
   directory occupying the marker path (the redirect fails, function returns
   non-zero, nothing written) was already correct.

4. **`relay_write joins a channel only when the old body is non-empty`** —
   stayed green; the `if [ -n "$old_ctx" ]` guard was already in place from
   slice 2.5 and this slice made no change near it.

5. **`an unreadable marker costs the relay, not the hook`** (library half,
   `tests/index_sync.bats`) — passes via the tolerant reads in
   `gitlore_relay_drain`: `sysblock=$(_gitlore_relay_sysblock "$marker") ||
   sysblock=""` and the same for `ctxblock`. Before this, `awk`'s open failure
   on the mode-0200 marker propagated under the synthetic caller's
   `set -euo pipefail` and killed it before `printf "OWN REPORT\n"` ran. The
   marker is still `rm -f`'d unconditionally after the fold (unchanged line,
   now reached instead of dying above it) — confirmed by the case's own
   `[ ! -e "$marker" ]` assertion passing.

6. **`an unreadable marker costs the relay, not the hook`** (SessionStart half,
   `tests/cc_hook_session_start.bats`) — passes as a side effect of the same
   drain fix: `session-start.sh`'s existing `gitlore_relay_drain "$mempath" ||
   true` now runs the drain to completion (rather than merely suspending
   errexit around a script that dies partway), so the standing FR11
   `additionalContext` and every notice above the fold survive intact. No
   change was made to `session-start.sh` — its `|| true` guard already covers
   the call.

7. **`an unkeyed run survives a non-file squatting on a marker name`**
   (`tests/cc_hook_index_compose.bats`) — stayed green throughout; `-type f`
   in the drain's `find` (already committed) was untouched.

## Constraints honored

- The empty-id guard is the function's first executable statement — no marker
  path is resolved and no file is touched before it fires.
- `index-sync-post.sh`'s `gitlore_relay_write … || true` fix is **unpinned**:
  no case in `tests/index_sync.bats` or `tests/cc_hook_index_compose.bats` (the
  suites this dispatch touched) squats that hook's own marker path. It was
  applied anyway per instruction, since the defect is identical to the pinned
  one in `index-compose.sh` and leaving it standing would be worse than an
  unpinned fix.
- `session-start.sh` was not touched. Its `|| true` on the drain call was
  already correct; the fix that made case 6 pass lives entirely in the
  library's drain function.

## Checks that passed, by name

- `./scripts/run-bats.sh tests/index_sync.bats tests/cc_hook_index_compose.bats tests/cc_hook_session_start.bats` — 131 passed, 0 failed.
- `./scripts/run-bats.sh tests/cc_hook_add_tier.bats tests/index_compose.bats tests/cc_hook_post_tool_use.bats tests/lib_util.bats tests/cc_hook_worktree_remove.bats tests/merge_memory.bats tests/tier_discovery.bats tests/tier_divergence.bats` — 181 passed, 0 failed.
- `shellcheck -s bash scripts/lib/index-sync.sh scripts/cc-hooks/index-compose.sh scripts/cc-hooks/index-sync-post.sh scripts/cc-hooks/session-start.sh` — clean.
- `./scripts/lint-shell.sh` — 137 files clean.
