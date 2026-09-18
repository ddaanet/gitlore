# Item 5.3 — report

## Line-reference resolution

- `commit_memory.bats:191`: at dispatch time this number pointed inside the test
  now at `tests/commit_memory.bats:187-203`, "a dirty root index with a welded
  line aborts the memory commit" — the `printf -- '- [A](a.md) …'` append line,
  at line 191 in the current file, is the one the new hook test mirrors.
- `commit_memory.bats:148`: inside "a dirty carrier with a duplicate pointer
  aborts the memory commit" (`tests/commit_memory.bats:140-185`) — the
  `git -C memory/ddaanet branch -f live` setup line, still at line 148.
- `git_hook_pre_commit.bats:401-412` (unqualified `:NNN` numbers, per the
  dispatch, default to this file): the backdate block inside "a dirty carrier
  with a duplicate pointer aborts the commit and restamps the approval" — the
  `touch -t 200001010000 "$msgfile"` through
  `[ "$(gitlore_commit_msg_freshness memory)" = "yes" ]` lines, at 404-412 in
  the pre-edit file (the block shifted to 407-415 after the `branch -f live`
  addition below it in the source order — the addition landed just above the
  fixture, at the same point `commit_memory.bats:148` occupies in its own test).
- `:391`: "a dirty carrier with a duplicate pointer aborts the commit and
  restamps the approval" itself, `tests/git_hook_pre_commit.bats:391-426`
  pre-edit.
- `:421`:
  `[[ "${output}${stderr}" == *"memory/ddaanet/MEMORY.md: duplicate pointer path shared.md"* ]]`
  in the same test, pre-edit — cited by the runbook as where the return-2
  mutant's failure was expected to land if it fell through to a content check;
  the mutant instead failed the tightened status assertion one line above
  (post-edit line 421), reported below.
- `:422-423`: the pre-edit
  `[ -n "$(git -C memory/ddaanet status --porcelain -- MEMORY.md)" ]` and
  `[ "$(git -C memory/ddaanet rev-parse HEAD)" = "$tier_head_before" ]` lines —
  the existing assertions the "publish-before-returning" mutant also trips; the
  new "tier live unmoved" assertion was placed ahead of them (now line 426,
  before the shifted 427-428).
- `:425`: the pre-edit restamp assertion,
  `[ "$(_gitlore_mtime "$msgfile")" -gt "$stamp_epoch" ]` — the new hook test
  ends on the equivalent line.
- `:717`: "a manifest refusal is reported and does not abort the commit",
  `tests/commit_memory.bats:717-741` — unchanged; used only to prove bullet 4's
  mutant.
- `:140` fixture: "a dirty carrier with a duplicate pointer aborts the memory
  commit" (above) — its shape (tier + manifest + two carrier writes + one root
  write) is what the new rule-4 test mirrors, substituting a stray line between
  two distinct bullets for the duplicate.

No reference was ambiguous; all resolved to a single candidate by content match.

## Diff

```diff
--- a/tests/commit_memory.bats
+++ b/tests/commit_memory.bats
@@ -202,6 +202,24 @@ EOF"
   [ "$(git -C memory rev-parse HEAD)" = "$head_before" ]
 }
 
+@test "an interleaved non-bullet line in a dirty carrier aborts the memory commit" {
+  # The :140 fixture, with a stray line between two distinct bullets in place
+  # of the duplicate — rule 4's own abort, over the same tested attribution.
+  make_parent_with_memory
+  make_tier_in_memory ddaanet
+  set_tier_manifest ddaanet
+  seed_tier_bullet ddaanet a.md "hook a"
+  printf 'Stray line\n' >> memory/ddaanet/MEMORY.md
+  seed_tier_bullet ddaanet b.md "hook b"
+  seed_root_bullet "ddaanet/a.md" "hook a"
+  seed_root_bullet "ddaanet/b.md" "hook b"
+
+  CLAUDECODE=1 run --separate-stderr bash "$CMD" -m "memory: record a and b"
+  [ "$status" -eq 1 ]
+  [[ "${output}${stderr}" == *"memory/ddaanet/MEMORY.md: interleaved non-bullet line"* ]]
+  [[ "${output}${stderr}" == *"aborted"* ]]
+}
+
 @test "an abort names every changed index file with a problem and no clean one" {
--- a/tests/git_hook_pre_commit.bats
+++ b/tests/git_hook_pre_commit.bats
@@ -395,6 +395,9 @@ committed_stale_carrier_store() {
   make_parent_with_memory
   make_tier_in_memory ddaanet
   set_tier_manifest ddaanet
+  # A fresh mount has no local `live`; one is created so a commit that lands
+  # the tier would advance it, giving the "unmoved" assertion something to catch.
+  git -C memory/ddaanet branch -f live
   seed_tier_bullet ddaanet shared.md "hook"
   seed_tier_bullet ddaanet shared.md "hook"
   seed_root_bullet "ddaanet/shared.md" "hook"
@@ -413,18 +416,50 @@ committed_stale_carrier_store() {
 
   head_before=$(git -C memory rev-parse HEAD)
   tier_head_before=$(git -C memory/ddaanet rev-parse HEAD)
+  tier_live_before=$(git -C memory/ddaanet rev-parse live)
   CLAUDECODE=1 run --separate-stderr bash "$HOOK"
-  [ "$status" -ne 0 ]
+  [ "$status" -eq 1 ]
   [[ "${output}${stderr}" == *"memory/ddaanet/MEMORY.md: duplicate pointer path shared.md"* ]]
   # The duplicate line prints on the advisory arm too; these two name the arm.
   [[ "${output}${stderr}" == *"aborted"* ]]
   [[ "${output}${stderr}" != *"the commit went ahead"* ]]
+  [ "$(git -C memory/ddaanet rev-parse live)" = "$tier_live_before" ]
   [ -n "$(git -C memory/ddaanet status --porcelain -- MEMORY.md)" ]
   [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$tier_head_before" ]
   [ "$(git -C memory rev-parse HEAD)" = "$head_before" ]
   [ "$(_gitlore_mtime "$msgfile")" -gt "$stamp_epoch" ]
 }
 
+@test "a dirty root index with a welded line aborts the commit and restamps the approval" {
+  # No tier: root's own index is the one carrying the change, so the abort has
+  # to come from the root branch of the rc-1 arm rather than a tier's.
+  make_parent_with_memory
+  printf -- '- [A](a.md) — a- [B](b.md) — b\n' >> memory/MEMORY.md
+  n=$(wc -l < memory/MEMORY.md | tr -d ' ')
+  msgfile=$(gitlore_commit_msg_file memory)
+  printf 'memory: record a and b\n' > "$msgfile"
+
+  # Backdate the summary and every tracked memory file to one stamp, so
+  # gitlore_commit_msg_freshness reads "yes" and the run reaches compose, and
+  # a restamp reads newer even within the second the seeds were written.
+  touch -t 200001010000 "$msgfile"
+  while IFS= read -r -d '' f; do
+    touch -t 200001010000 "$f"
+  done < <(find memory -type f -not -path '*/.git/*' -print0)
+  stamp_epoch=$(_gitlore_mtime "$msgfile")
+  [ "$(gitlore_commit_msg_freshness memory)" = "yes" ]
+
+  head_before=$(git -C memory rev-parse HEAD)
+  CLAUDECODE=1 run --separate-stderr bash "$HOOK"
+  [ "$status" -eq 1 ]
+  [[ "${output}${stderr}" == *"memory/MEMORY.md: line $n welds two pointer bullets"* ]]
+  # The weld line prints on the advisory arm too; these two name the arm.
+  [[ "${output}${stderr}" == *"aborted"* ]]
+  [[ "${output}${stderr}" != *"the commit went ahead"* ]]
+  [ "$(git -C memory rev-parse HEAD)" = "$head_before" ]
+  [ "$(_gitlore_mtime "$msgfile")" -gt "$stamp_epoch" ]
+}
+
 @test "an aborted compose keeps the approved summary usable" {
```

## Mutants

Every mutant was applied to a working copy backed up under
`.git/item-5-3-backup/`, run, observed, then reverted with `cp` + `diff` to
confirm byte-identity to the backup. `git diff -- scripts/` was empty before the
commit below.

### Bullet 1 — new hook test "a dirty root index with a welded line aborts the commit and restamps the approval"

**Mutant: the `1)` arm treats a dirty root index as advisory.** Neutralized
`scripts/lib/resolve.sh`'s root-file `abort_files` assignment (replaced
`[ -z "$index_status" ] || abort_files="$mempath/MEMORY.md"` with a no-op) so a
dirty root index never joins `abort_files`.

```
not ok 1 a dirty root index with a welded line aborts the commit and restamps the approval
# (in test file tests/git_hook_pre_commit.bats, line 454)
#   `[ "$status" -eq 1 ]' failed
```

**Mutant: the abort arm skips `touch "$msgfile"`.** Removed the
`touch "$msgfile"` line ahead of `return 1` in the abort-files block.

```
not ok 1 a dirty root index with a welded line aborts the commit and restamps the approval
# (in test file tests/git_hook_pre_commit.bats, line 460)
#   `[ "$(_gitlore_mtime "$msgfile")" -gt "$stamp_epoch" ]' failed
```

### Bullet 2 — tightened ":391" test

**Mutant: the abort arm returns 2 instead of 1 (exact status).** Changed the
abort-files block's `return 1` to `return 2`.

Confirmed first that this mutant *passes* the test as it stood before tightening
(status check `-ne 0`): stashed the working-tree edit to
`tests/git_hook_pre_commit.bats` (restoring the committed, untightened version),
applied the mutant, and ran:

```
bats: 1 passed, 0 failed — full log: /tmp/claude-1000/gitlore-bats.slfItw
```

Restored the tightened test (`git stash pop`) with the mutant still applied:

```
not ok 1 a dirty carrier with a duplicate pointer aborts the commit and restamps the approval
# (in test file tests/git_hook_pre_commit.bats, line 421)
#   `[ "$status" -eq 1 ]' failed
```

**Mutant: the abort arm calls `gitlore_sync_tiers_to_live "$mempath" "$msgfile"`
before returning.** Inserted that call ahead of the abort-files block's
`return 1`.

```
not ok 1 a dirty carrier with a duplicate pointer aborts the commit and restamps the approval
# (in test file tests/git_hook_pre_commit.bats, line 426)
#   `[ "$(git -C memory/ddaanet rev-parse live)" = "$tier_live_before" ]' failed
```

The failure lands on the new "tier live unmoved" assertion (line 426), placed
ahead of the pre-existing carrier-status/HEAD checks (now 427-428) that the same
mutant would also have tripped.

### Bullet 3 — new `commit_memory.bats` test "an interleaved non-bullet line in a dirty carrier aborts the memory commit"

**Mutant: `gitlore_compose_check_index` skips rule 4.** In
`scripts/lib/index-compose.sh`, prefixed the rule-4 `elif` condition with
`false &&` so the interleaved-line branch never fires.

```
not ok 1 an interleaved non-bullet line in a dirty carrier aborts the memory commit
# (in test file tests/commit_memory.bats, line 218)
#   `[ "$status" -eq 1 ]' failed
```

### Bullet 4 — rule 2 advisory, proved against the existing `:717` test (no test change)

**Mutant: the advisory arm prints only the lines `gitlore_compose_problems_in`
selects for the root index (dropping rule 2's prefixless lines).** In
`scripts/lib/resolve.sh`, replaced the advisory arm's `$refusal` payload with a
locally filtered `$compose_result` passed through
`gitlore_compose_problems_in "$mempath/MEMORY.md"`.

```
not ok 1 a manifest refusal is reported and does not abort the commit
# (in test file tests/commit_memory.bats, line 755)
#   `[[ "$stderr" == *"the tier manifest lists 'phantom'"* ]]' failed
```

As the runbook states, this proves the mutant against tested coverage already in
place; no new assertion was added for this bullet.

## Green runs (post-revert)

```
$ shellcheck -x tests/git_hook_pre_commit.bats tests/commit_memory.bats
(clean)

$ git diff --stat -- scripts/
(empty)

$ GITLORE_GIT_RETRY_SCHEDULE=0 scripts/run-bats.sh tests/git_hook_pre_commit.bats
bats: 21 passed, 0 failed

$ GITLORE_GIT_RETRY_SCHEDULE=0 scripts/run-bats.sh tests/commit_memory.bats
bats: 36 passed, 0 failed
```

## Commit

`ce82d56` —
`test: Item 5.3 — the root weld aborts through the hook, the carrier abort's status and live are pinned, rule 4 aborts`
(only `tests/git_hook_pre_commit.bats` and `tests/commit_memory.bats` staged; no
production change; hooks ran, not bypassed).

## Orchestrator addendum — the `the commit went ahead` denial, proven

The report above shows mutant 1 failing on status, so the new hook test's denial
of `the commit went ahead` had not yet been shown to fail. Re-run by the
orchestrator: with the same mutant (root-index `abort_files` assignment made a
no-op in `scripts/lib/resolve.sh`), and the status and `aborted` assertions
temporarily blanked so the run reaches it, the test fails on the denial itself:

```
not ok 1 a dirty root index with a welded line aborts the commit and restamps the approval
# (in test file tests/git_hook_pre_commit.bats, line 458)
#   `[[ "${output}${stderr}" != *"the commit went ahead"* ]]' failed
```

Both files were restored from copies under `.git/`; `git status` showed no
tracked change afterwards.
