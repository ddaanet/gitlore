# Item 1.2 slice 1 — GREEN report

Mode: GREEN. Not committed, per instruction — the diffs below are the
uncommitted working tree.

## The change

`scripts/lib/resolve.sh`, inside `gitlore_sync_memory_to_live`, between the
per-tier stale-merge guard loop and
`compose_result=$(gitlore_compose "$mempath")`:

```diff
       [ -e "$mempath/$tier/.git" ] || continue
       gitlore_guard_stale_merge_state "$mempath/$tier" || return 1
     done < <(gitlore_tier_paths "$mempath")
+    # A tier off its pin refuses composition itself (D31, D36), but leaving that
+    # refusal to gitlore_compose's own rc-1 arm would let this function's `add -A`
+    # below stage the moved gitlink anyway — adopting the move silently in the
+    # very commit that reported it as a problem. Checked here, ahead of compose,
+    # so an off-pin tier aborts instead. No restamp: this writes nothing, so the
+    # tree is no newer than $msgfile and the approval survives for the retry.
+    local pin_problems
+    if ! pin_problems=$(gitlore_compose_check_pins "$mempath"); then
+      local pin_header="gitlore: a tier was moved off the commit the memory store records for it, so the commit was aborted rather than adopt the move:
+$pin_problems"
+      gitlore_say_for_agent_or_user \
+        "$pin_header
+gitlore: composing would have overwritten what that tier holds, and committing would have adopted the move silently. Return the tier to its pin with the command above, or run /gitlore:merge to take its content properly, then retry the commit — the approved summary is still in place." \
+        "$pin_header
+gitlore: composing would have overwritten what that tier holds. Open this project in Claude Code and ask it to repair the memory store, then retry." >&2
+      return 1
+    fi
     # Compose before the tier commit below: composition writes carrier files
     # inside the tiers, so it must land before gitlore_sync_tiers_to_live moves
```

Six lines of logic (the `local`, the `if`, the `gitlore_say_for_agent_or_user`
call and its `return 1`), as scoped. `gitlore_compose_check_pins` and the 0/1/2
contract of `gitlore_compose` are untouched — `scripts/lib/index-compose.sh` has
no diff (`git diff --exit-code scripts/lib/index-compose.sh` clean).

## Message texts — character-for-character against the runbook

Diffed the three quoted strings in the runbook dispatch against what landed in
`scripts/lib/resolve.sh`: identical, including punctuation and the em dash.
Header:
`gitlore: a tier was moved off the commit the memory store records for it, so the commit was aborted rather than adopt the move:`.
Agent remedy:
`gitlore: composing would have overwritten what that tier holds, and committing would have adopted the move silently. Return the tier to its pin with the command above, or run /gitlore:merge to take its content properly, then retry the commit — the approved summary is still in place.`
User remedy:
`gitlore: composing would have overwritten what that tier holds. Open this project in Claude Code and ask it to repair the memory store, then retry.`
Both arms carry the header via the one `local pin_header` variable, so they
cannot drift apart.

## The two slice-1 tests, before/after

**`a tier moved off its pin aborts the commit`** (`tests/commit_memory.bats`,
was `an off-pin compose refusal is reported and does not abort the commit`) —
before: failed on `[ "$status" -ne 0 ]` (commit landed, rc 0). After: passes all
assertions — unchanged HEAD, unchanged `:ddaanet` pin, unchanged carrier
(`assert_bullets … "- [shared](shared.md) — stale hook"`), `$msgfile` still
present, `gitlore_commit_msg_freshness memory` still `yes`, and all three stderr
fragments (`moved off the commit the memory store records for it`,
`is checked out at`, `Return the tier to its pin with the command above`)
present.

**`the parent pre-commit hook aborts on an off-pin tier`**
(`tests/git_hook_pre_commit.bats`) — before: failed on `[ "$status" -ne 0 ]`
(hook exited 0). After: passes — unchanged HEAD, unchanged `:ddaanet` pin,
unchanged carrier.

## Collateral re-induction

`the rc-1 user arm does not tell a user to retry a commit that succeeded`
(`tests/commit_memory.bats`) reds against the new guard because its old fixture
(off-pin tier, `CLAUDECODE` unset) now aborts instead of reaching
`gitlore_compose`'s own rc-1 manifest-refusal arm. Re-induced exactly as
directed: dropped the
`git -C memory/ddaanet commit -q --allow-empty -m "moved outside /gitlore:merge"`
line (tier stays on its pin) and changed `set_tier_manifest ddaanet` to
`set_tier_manifest ddaanet phantom` with no `make_tier_in_memory phantom`.
Assertions unchanged. This reaches `gitlore_compose_check`'s rule 2
(`the tier manifest lists 'phantom', which is not mounted in …`) because
`gitlore_compose_check_pins` now passes (tier on pin), and `gitlore_compose`'s
own rc-1 arm fires as before. Updated the test's comment to describe the new
induction. Passes.

## Fallout suites — verified from a run, no fixture changes needed

- `tests/tier_divergence.bats` and `tests/tier_lockstep.bats` — no code changes
  needed; every fixture that legitimately advances a tier already stages the
  moved gitlink in memory's index as its last act (D43), so
  `gitlore_compose_check_pins` reads a matching pin and passes.
- `tests/index_compose.bats`, `tests/index_sync.bats` — untouched by this change
  (the call site is in `resolve.sh`, not `index-compose.sh`), included per the
  done criteria.

All four run together:
`scripts/run-bats.sh --jobs 1 tests/tier_divergence.bats tests/tier_lockstep.bats tests/index_compose.bats tests/index_sync.bats`
→ `bats: 180 passed, 0 failed`.

## Suite runs

```
scripts/run-bats.sh --jobs 1 tests/commit_memory.bats tests/git_hook_pre_commit.bats
bats: 34 passed, 0 failed
```

```
scripts/run-bats.sh --jobs 1 tests/tier_divergence.bats tests/tier_lockstep.bats tests/index_compose.bats tests/index_sync.bats
bats: 180 passed, 0 failed
```

## Lint

`shellcheck -s bash scripts/lib/resolve.sh` — exit 0, no findings.
`shellcheck -s bash tests/commit_memory.bats tests/git_hook_pre_commit.bats` —
exit 0, no findings.

## Scope check

Only `scripts/lib/resolve.sh` (the guard) and `tests/commit_memory.bats` (the
collateral re-induction) changed. `scripts/lib/index-compose.sh` untouched.
Slice 2's manifest-refusal-is-reported case and slice 3's two user-arm cases
were not written. Nothing committed; `just precommit` was not run, per
instruction.
