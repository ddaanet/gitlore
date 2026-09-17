# Item 4.1 / Slice 1 — RED report

## Scope

Tightened `tests/resolve_compose.bats:394`
(`a refused merge commit leaves no message file behind and keeps the merge for a rerun`)
only. No production code touched.

## Diff

```diff
   run --separate-stderr bash "$RESOLVE" continue-after-merge
-  [ "$status" -ne 0 ]
+  [ "$status" -eq 1 ]
   [[ "$stderr" == *"commit refused by hook"* ]]
+  [[ "$stderr" == *"gitlore: the merge commit was refused, so the merge was not committed; the merge stays prepared."* ]]
+  hook_line=$(printf '%s\n' "$stderr" | grep -n 'commit refused by hook' | head -n 1 | cut -d: -f1)
+  gitlore_line=$(printf '%s\n' "$stderr" | grep -n 'gitlore: the merge commit was refused' | head -n 1 | cut -d: -f1)
+  [ "$hook_line" -lt "$gitlore_line" ]
   [ -z "$(find "$TMPDIR" -name 'gitlore-merge-msg.*' -print -quit)" ]
   [ -f "$(git -C memory/ddaanet rev-parse --git-path gitlore-merge-state)" ]
   git -C memory/ddaanet rev-parse -q --verify MERGE_HEAD >/dev/null
```

## Filtered run (this test only)

`GITLORE_GIT_RETRY_SCHEDULE=0 scripts/run-bats.sh tests/resolve_compose.bats --filter 'a refused merge commit leaves no message file behind'`

```
not ok 1 a refused merge commit leaves no message file behind and keeps the merge for a rerun
# (in test file tests/resolve_compose.bats, line 405)
#   `[[ "$stderr" == *"gitlore: the merge commit was refused, so the merge was not committed; the merge stays prepared."* ]]' failed
# gitlore: memory merge prepared (flavor=head-vs-remote) in store:
# gitlore:   .../memory/ddaanet
# gitlore: dispatch sub-agent gitlore:memory-merger with state file:
# ...
bats: 0 passed, 1 failed
```

Line 405 is the new "gitlore: the merge commit was refused …" assertion — the
line before it (`[ "$status" -eq 1 ]`) and the one after it
(`commit refused by hook`) both passed, so:

- the `-eq 1` tightening holds on current code (status is genuinely 1, not some
  other nonzero value);
- the ordering assertions (`hook_line`, `gitlore_line`, `-lt`) never execute
  because bats stops at the first failing line — they are new but not yet
  exercised as reds themselves; they will be proven once the gitlore line exists
  to compare against.
- the red is exactly the new "gitlore:" line current `scripts/resolve.sh` does
  not print.

## Full-file run

`GITLORE_GIT_RETRY_SCHEDULE=0 scripts/run-bats.sh tests/resolve_compose.bats`

```
bats: 22 passed, 1 failed
```

The single failure is the same test/line as above; every other assertion in the
file, including the rest of this test's own assertions (rerun after
`rm -f "$hook"` succeeds with the fact merged), is unaffected.

## Checks

- `shellcheck -x tests/resolve_compose.bats`: clean.
- `scripts/resolve.sh` not modified (slice 1 is test-only).
