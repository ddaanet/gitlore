# Item 5.4 — rule 4 on the merged-root gate

## Fixture deviation from the resolved reference

The orchestrator's resolved reference gave the pending index as
`- [P](p.md) — one`, `Stray line`, `- [Q](q.md) — two` with no duplicate.
Verified empirically (debug prints on `memory/MEMORY.md`, then reverted) that
this fixture cannot reach `gitlore_compose_check_index` in the merged-root gate:
`gitlore_compose` runs through `gitlore_merge_indexes`
(`scripts/lib/index-merge.sh`) before the check, which rebuilds each index's
bullet block path-by-path (`_gitlore_index_merge_bullets`) whenever the
entry-wise merge succeeds (`gitlore_index_merge` returns 0 or 1). A line with no
bullet path — like a lone `Stray line` — is invisible to that path-driven walk
and is silently dropped from the rebuilt file, never reaching the check.
Confirmed directly: with the reference fixture, `memory/MEMORY.md` after
`pre-commit` no longer contains `Stray line` at all, and the continuation exits
0 reporting an unrelated dangling-pointer message.

The weld sibling test at `tests/resolve_compose.bats:558` survives this same
path only because a welded line still parses as ONE valid bullet (its first
path), so it is a legitimate entry in the path-driven rebuild.

The only bail-out in `gitlore_index_merge` that leaves git's own raw line-wise
merge result standing (stray line intact) is an internal duplicate path on one
side — `gitlore_index_merge` returns 2 and `gitlore_merge_indexes` skips the
rewrite for that file. The fixture was changed to add a duplicate `p.md` bullet
alongside the interleaved line, which forces that bail and lets `Stray line`
reach `gitlore_compose_check_index` intact. The new test asserts only the
`interleaved non-bullet line` message (not the incidental duplicate message),
and the test carries a comment explaining why the duplicate is load-bearing.
This stayed inside the agreed task (same purpose: prove rule 4 fires at the
merged-root gate) and is a verified, reversible correction to the fixture only —
no assertion shape changed from the sibling pattern.

## Diff (committed)

```
diff --git a/tests/resolve_compose.bats b/tests/resolve_compose.bats
index 6eb5547..b6dc329 100644
--- a/tests/resolve_compose.bats
+++ b/tests/resolve_compose.bats
@@ -573,6 +573,33 @@ EOF
   [ "$(git -C memory rev-parse HEAD)" = "$mem_before" ]
 }
 
+@test "an interleaved line in the merged root index keeps the merge unlanded" {
+  make_parent_with_memory
+  # The duplicate path is load-bearing, not incidental: a clean entry-wise
+  # index merge rebuilds the bullet block path-by-path and drops any line that
+  # carries no path, so a lone stray line never reaches the merged file. A
+  # side with an internal duplicate is unmergeable (gitlore_index_merge bails),
+  # which leaves git's own line-wise merge result standing — stray line intact
+  # — for gitlore_compose_check_index to find.
+  diverge_memory_with_index '# Memory Index
+
+- [P](p.md) — one
+- [P again](p.md) — two
+Stray line
+- [Q](q.md) — three'
+
+  run bash "$PRE_COMMIT"
+  [ "$status" -ne 0 ]
+  mem_before=$(git -C memory rev-parse HEAD)
+  run --separate-stderr run_stub_synth memory
+  [ "$status" -eq 1 ]
+  [[ "$stderr" == *"was not committed"* ]]
+  [[ "$stderr" == *"memory/MEMORY.md: interleaved non-bullet line"* ]]
+  [ -f "$(gitlore_merge_state_file memory)" ]
+  [ -n "$(git -C memory rev-parse -q --verify MERGE_HEAD)" ]
+  [ "$(git -C memory rev-parse HEAD)" = "$mem_before" ]
+}
+
 @test "a memory-root merge with only a leftover root prefix commits uncomposed" {
   make_parent_with_memory
   diverge_memory_with_index '# Memory Index
```

## Mutant

Applied to `scripts/lib/index-compose.sh`, the rule-4 branch of
`gitlore_compose_check_index` (same form Item 5.3 used):

```diff
-    elif [ "$n" -gt "$first" ] && [ "$n" -lt "$last" ] && [ -n "${line//[[:space:]]/}" ]; then
+    elif false && [ "$n" -gt "$first" ] && [ "$n" -lt "$last" ] && [ -n "${line//[[:space:]]/}" ]; then
       printf '%s: interleaved non-bullet line %s inside the pointer block\n' "$file" "$n"
     fi
```

Ran
`GITLORE_GIT_RETRY_SCHEDULE=0 bats --filter "an interleaved line in the merged root index" tests/resolve_compose.bats`:

```
1..1
not ok 1 an interleaved line in the merged root index keeps the merge unlanded
# (in test file tests/resolve_compose.bats, line 597)
#   `[[ "$stderr" == *"memory/MEMORY.md: interleaved non-bullet line"* ]]' failed
```

Reverted; `git diff -- scripts/` empty after revert.

## Green run (full file, foreground)

```
$ GITLORE_GIT_RETRY_SCHEDULE=0 scripts/run-bats.sh tests/resolve_compose.bats
bats: 26 passed, 0 failed — full log: /tmp/claude-1000/gitlore-bats.CNuuHH
```

`shellcheck -x tests/resolve_compose.bats` — clean, exit 0.

## Commit

`8e7bf200bcec0adc8fe92a10004f610e2ee059d0` — "Item 5.4 — an interleaved line in
the merged root index keeps the merge unlanded" (`tests/resolve_compose.bats`
only, 27 insertions).
