# Item 5.2 — test specificity for the unrepairable arm

Test: `tests/merge_memory.bats`,
`"an arrival the repair cannot fix walks back and names upstream"` —
`tests/merge_memory.bats:963` as Phase 1 leaves it. This is the runbook's target
for the `:744` test and the finding at
`plans/unadoptable-tier-arrival/reports/deliverable-review.md:128-130`
("worktree-carrier attribution... nothing rejects a worktree-carrier-prefixed
problem line, and memory HEAD is not asserted unchanged").

An earlier pass of this item mistakenly edited
`"an arrival the repair cannot fix beside a root duplicate reports both and the two-fix remedy"`
(`:1002`) instead — that test is Item 1.1 slice 1's own and already denies
`memory/ddaanet/MEMORY.md:`. Both additions there are reverted; that test now
reads exactly as `574083f` left it
(`git diff 574083f -- tests/merge_memory.bats` is empty for its span).

## Diff (`tests/merge_memory.bats`)

```diff
@@ -966,6 +966,7 @@ push_tier_files() {
   set_tier_manifest ddaanet
   gitlore_compose memory
   commit_memory_state
+  memory_head_before=$(git -C memory rev-parse HEAD)
   gitlink=$(git -C memory rev-parse HEAD:ddaanet)
   remote_sha=$(push_tier_fact ddaanet "$(printf -- '- [B](b.md) — y\n- [B](b.md) — y\n- [a](a.md) — a- [z](z.md) — z')")
   arrival_text=$(git --git-dir="$TMP_REPO/.bare-ddaanet.git" show "$remote_sha:MEMORY.md")
@@ -983,11 +984,17 @@ push_tier_files() {
   mkdir -p "$tmp_env"
 
   TMPDIR="$tmp_env" run --separate-stderr bash "$CMD"
+  # The unrepairable arm walks the tier back rather than falling through to a
+  # commit: the root's own HEAD never moves for a take it refused.
+  [ "$(git -C memory rev-parse HEAD)" = "$memory_head_before" ]
   [ "$status" -eq 1 ]
   all="$output$stderr"
   [[ "$all" == *"gitlore: tier 'ddaanet' took an index the take cannot repair; it is held in the tier's local 'live' and must be fixed where it was published:"* ]]
   [[ "$all" == *"live:MEMORY.md: line $weld_line_n welds"* ]]
   [[ "$all" != *"line $((weld_line_n - 1)) welds"* ]]
+  # Nothing here names the carrier: every problem in this refusal is the
+  # carrier's own, already listed above in its live:MEMORY.md form.
+  run ! grep -Eq '^gitlore:   .*ddaanet/MEMORY\.md: ' <<<"$stderr"
   # The closing remedy points upstream too, never at this store's clean carrier.
   [[ "$all" == *"its local 'live' keeps what arrived. Once the index is fixed where it was published, run /gitlore:merge again."* ]]
   [[ "$all" != *"Fix the store"* ]]
```

(The `:1002` test's diff is the exact inverse of the above two additions —
omitted here since `git diff 574083f -- tests/merge_memory.bats` confirms it
nets to nothing.)

Both new assertions sit ahead of every existing assertion their mutant also
trips:
- The HEAD check precedes `[ "$status" -eq 1 ]`. Mutant 2 (below) flips the
  overall exit status to 0 as well as leaving `HEAD` in place, and would
  otherwise report that line instead.
- The `grep` check precedes the remedy-text check
  (`*"its local 'live' keeps what arrived. Once the index is fixed..."*`).
  Mutant 1 (below) changes that remedy's wording too, and would otherwise report
  that line instead.

`$stderr` is the right stream: every print in the unrepairable arm (the
`gitlore_adopt_repair_arrival` branch starting at `scripts/lib/resolve.sh:1968`)
goes to `>&2`. The test's own `all="$output$stderr"` combines both for
convenience elsewhere, but the new assertion checks `$stderr` directly, per the
item's "no stderr line" wording. Using plain `run !` (not `--separate-stderr`)
for the grep probe leaves `$stderr` untouched for the later assertions that
still read it.

## Mutant 1 — root-header prints every refusal line, carrier included

Applied to `scripts/lib/resolve.sh` (the `other_lines` filter in
`gitlore_adopt_repair_arrival`):

```diff
-    other_lines=$(
-      while IFS= read -r line || [ -n "$line" ]; do
-        [ -n "$line" ] || continue
-        gitlore_compose_problems_in "$tierpath/MEMORY.md" <<<"$line" >/dev/null && continue
-        printf '%s\n' "$line"
-      done <<<"$composed"
-    )
+    other_lines="$composed"
```

This test has no root problem, so every line in `$composed` names the carrier;
without the filter, `other_lines` becomes non-empty and the "root index could
not take" block fires where it normally would not, printing the carrier's own
lines a second time, unstripped (`memory/ddaanet/MEMORY.md: ...` rather than
`live:MEMORY.md: ...`). It does trip the new assertion.

Run:
`GITLORE_GIT_RETRY_SCHEDULE=0 scripts/run-bats.sh tests/merge_memory.bats --filter "walks back and names upstream"`

```
not ok 1 an arrival the repair cannot fix walks back and names upstream
# (in test file tests/merge_memory.bats, line 997)
#   `run ! grep -Eq '^gitlore:   .*ddaanet/MEMORY\.md: ' <<<"$stderr"' failed, expected nonzero exit code!
```

Failed on the new assertion at line 997, as required. Reverted; `git diff` on
`scripts/lib/resolve.sh` empty afterward.

## Mutant 2 — fall-through to `gitlore_adopt_stage_pair_and_commit`

Applied to the same function's walk-back call:

```diff
     rm -rf -- "$scratch"
-    gitlore_adopt_walk_back_tier "$mempath" "$tier" "$old_gitlink" "$label" "$remedy" || :
-    return 1
+    gitlore_adopt_stage_pair_and_commit "$mempath" "$tier" "$root_dirty_before" "$old_gitlink" "$label"
+    return
   elif ! repair=$(gitlore_adopt_commit_repair "$tierpath" "$tier" "$scratch" "$report"); then
```

Run: same filter.

```
not ok 1 an arrival the repair cannot fix walks back and names upstream
# (in test file tests/merge_memory.bats, line 989)
#   `[ "$(git -C memory rev-parse HEAD)" = "$memory_head_before" ]' failed
```

Failed on the new assertion at line 989, as required. Reverted; `git diff` on
`scripts/lib/resolve.sh` empty afterward.

## Green run

`GITLORE_GIT_RETRY_SCHEDULE=0 scripts/run-bats.sh tests/merge_memory.bats`
(foreground, unpiped, full file, unmutated production code):

```
bats: 41 passed, 0 failed — full log: /tmp/claude-1000/gitlore-bats.bGZaS2
```

`shellcheck -x tests/merge_memory.bats`: clean.

## Commit

`0bd0c98` —
`test: Item 5.2 — the assertions move to the unrepairable-arrival test the finding names`.
Only `tests/merge_memory.bats` staged (7 insertions, 5 deletions: the two
additions net into `:963`, and the two mistaken additions at `:1002` net out).
`scripts/lib/resolve.sh` carries no lasting change (`git diff` empty throughout
except during the two temporary mutant probes, both reverted). Supersedes the
earlier commit `6aedc78`, which is left in history rather than amended.
