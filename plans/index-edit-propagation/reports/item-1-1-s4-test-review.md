# Item 1.1 slice 4 — test review

Verdict: **accepted with two fixes applied.** No UNFIXABLE finding. The two reds
fail on their assertions for the reasons the slice names, the two
characterizations pass for the reason claimed, and the SUT back-out is exactly
the two `touch "$msgfile"` statements.

## The mechanical check, re-run rather than taken from the report

`scripts/run-bats.sh tests/commit_memory.bats tests/git_hook_pre_commit.bats`,
run against the tree as RED left it:

```
not ok 14 an unrecognised compose status aborts and keeps the approval
# (in test file tests/commit_memory.bats, line 251)
#   `[ "$(gitlore_commit_msg_freshness memory)" = "yes" ]' failed
not ok 33 an aborted compose keeps the approved summary usable
# (in test file tests/git_hook_pre_commit.bats, line 371)
#   `[ "$status" -eq 0 ]' failed

bats: 31 passed, 2 failed
```

Both failures carry a `#` assertion line naming the failed expression, which is
what distinguishes a failed assertion from an ERROR — a missing helper or a bad
fixture aborts the body and bats reports the failing *command*, not an
assertion. `ok 15` and `ok 16` in the same log are the two characterizations. 33
total = the 29 pre-existing plus this slice's 4. The RED report's account is
accurate in every particular I checked.

### The reds are achievable, not merely red

RED proves the tests fail; it does not prove they can pass, and a red that no
implementation reaches would strand GREEN. Probed by restoring
`scripts/lib/resolve.sh` to `HEAD` (both `touch` lines back), re-running, and
then re-applying the back-out:

```
bats: 33 passed, 0 failed
```

So the two reds are reds *of the backed-out fix* specifically, and the fix GREEN
restores is sufficient for both. The back-out was re-applied from the diff in
the RED report; `git hash-object scripts/lib/resolve.sh` is
`07cc3c868e92e3ab5e60a8befc248a6f5ce2af1d`, matching the `..07cc3c8` in that
report's own diff header, so the file is byte-identical to the state RED left.
`git stash list` is empty and `git status` shows only the three expected
modified files plus the untracked RED report.

## SUT back-out — in scope, and correct

`git diff scripts/lib/resolve.sh` is two deleted lines and nothing else: the
`touch "$msgfile"` on the rc-2 arm (`scripts/lib/resolve.sh:954` region) and the
one on the `*)` arm. Both explanatory comments above them are intact
(`# … Restamping restores the state this run started from …` and
`# Same approval-freshness reason as rc 2 above.`), and no other byte of the
file differs from `HEAD`. Matches the RED report's stated diff exactly. Left
backed out, as the dispatch requires. Nothing else in the implementation was
read for review, changed, or restored.

## Findings and fixes

### Major 1 — `[[ "$stderr" == *"7"* ]]` was effectively vacuous (fixed)

`tests/commit_memory.bats`, the `*)`-arm test. The runbook asks that "the stub's
status `7` appears in the message"; the test asserted the bare digit. That
channel also carries `$BATS_TEST_TMPDIR` and `$TMP_REPO` paths, whose `mktemp`
`XXXXXX` suffix is drawn from a set that includes `7`, so the assertion could
hold on a run where the `*)` arm never executed. That matters more here than it
would elsewhere: the driver calls `gitlore_sync_memory_to_live` bare under
`set -euo pipefail` (faithfully — it is exactly how
`scripts/commit-memory.sh:66` calls it, whereas
`scripts/git-hooks/pre-commit:68` uses `|| exit $?`), so an unchecked non-zero
command anywhere earlier in the function would abort the driver before the arm
with a non-zero status, satisfying `[ "$status" -ne 0 ]` and leaving only this
assertion to notice. Tightened to the arm's own literal:

```bash
[[ "$stderr" == *"unrecognised status (7)"* ]]
```

That string exists only in the `*)` arm's `$unknown`, so it now establishes that
the arm ran.

### Major 2 — the composition order was asserted only in a comment (fixed)

`tests/git_hook_pre_commit.bats`. The slice states the case is void if the
`chmod a-w` tier is the *first* composed, because then nothing is written and
the summary never goes stale. The test carried that as a prose comment and
nothing more, so a reordering inside `gitlore_compose` would silently convert
this from a real red into a test that passes regardless of the restamp.

I confirmed the order independently of the RED report's run, from source:
`gitlore_active_tiers` (`scripts/lib/util.sh:377`) emits the manifest in file
order, and `gitlore_compose`'s down-projection loop
(`scripts/lib/index-compose.sh:814`) iterates that same stream, so
`set_tier_manifest alpha beta` makes `beta` second. `gitlore_compose_write`
writes its temp file into the store's *gitdir* and then `mv`s into the target
directory (`scripts/lib/index-compose.sh:655,676`), which is why `chmod a-w` on
`memory/beta` fails the write while leaving `memory/alpha`'s `mv` to land first
— and `cmp -s` short-circuits an unchanged write, so alpha's carrier disagreeing
with root (`stale alpha` vs `fresh alpha`) is load-bearing for the mtime bump.

Locked into the test rather than left to the comment:

```bash
[[ "$output" == *"composed memory/alpha/MEMORY.md"* ]]
[[ "$output" == *"could not write memory/beta/MEMORY.md"* ]]
```

The first is the precondition the whole case rests on (a write landed, staling
the tree); the second is that the failure was the *second* tier. Both are on the
first run, which already passed, so neither perturbs the red.

### Minor 1 — `chmod u+w` was not immediately after `run` (fixed)

Same test. Two assertions sat between `run bash "$HOOK"` and
`chmod u+w memory/beta`. Either failing leaves `memory/beta` non-writable, and
`teardown_tmp_repo`'s `rm -rf "$TMP_REPO"` then cannot unlink the files inside
it, leaking a temp tree per failure. Harmless on today's run (both assertions
pass, and the red is downstream of the restore) but it is the contract slice 3's
own case follows at `tests/commit_memory.bats:201`. Moved the `chmod u+w` to
immediately after `run`. `chmod` touches ctime, not mtime, so freshness is
unaffected.

## Wrong-reason hunting — the questions the dispatch asked

**Does each red fail for the slice's reason?** Yes. Test 1's red is the second
hook run's `[ "$status" -eq 0 ]`, after a first run that is asserted non-zero
with the summary file still present — the pre-existing behaviour slice 3 already
pinned. The failure is therefore the refusal of the *retry*, not the fixture and
not the first run. Test 2's red is the freshness assertion specifically, and
every other assertion in that test passes.

**Are the characterizations discriminating?** Partly, and here is the plain
answer the dispatch asked for.

`CLAUDECODE` is genuinely cleared: `unset CLAUDECODE` runs in the test body
before `run`, and since the variable is exported when present, unsetting it
removes it from the child's environment. Both tests are also self-guarding on
this — neither agent arm contains the string its test asserts (the rc-1 agent
arm ends "Fix the problems above by hand — composition runs again at the next
memory commit."), so a leak fails the test rather than passing it vacuously.

Test 3's pair is the same sentence's two endings, as specified, and does
discriminate on the retry/no-retry register that is the point of the fix. Its
weakness is the prefix: everything before `ask it to` is unpinned, so a wrong
user text that preserved that tail — a changed lead-in, a wrong addressee —
would still pass. Its negative is also close to restating its positive: the
mutation most likely to break the register (`store.` → `store, then retry.`)
fails *both*, so the negative adds discrimination only against contrived
rewrites. That is the shape `assert_bullets`' own doc comment
(`tests/helpers/tier-fixtures.bash`) warns about. I left it: the runbook
specifies both assertions by name with its reasoning, and the runbook is out of
scope for this review.

Test 4 is a single positive substring with the same unpinned prefix, and it
additionally does not distinguish the rc-2 arm from the `*)` arm — the two share
that exact ending verbatim. What makes it rc-2 is the induction (a real
`gitlore_compose` returning 2), plus slice 3's neighbouring test pinning the
rc-2 header on the identical fixture. **Consequence for the code review (d):**
the in-place mutation that proves test 4's discrimination must be made to the
**rc-2 user arm specifically**, not to whichever arm carries the string — a
mutation of the `*)` arm would leave test 4 green and prove nothing.

**The `sleep 1`.** Present and correctly placed in both freshness cases: after
the summary is written to `gitlore_commit_msg_file memory` and before the run
meant to stale it, with a comment naming the whole-second `>=` in
`gitlore_commit_msg_freshness` (`scripts/lib/util.sh:275`). The two
characterization tests do not turn on freshness and correctly have none. In test
2 the stub's `touch memory/MEMORY.md` lands ≥1s after the summary, so the
staling is deterministic; the arm's own restamp lands in the same second as that
touch, which `>=` reads as fresh — that is the assertion, and it is on the right
side of the comparison.

**The stub driver.** The ordering claim holds: `scripts/lib/resolve.sh:11`
sources `index-compose.sh`, which defines the real `gitlore_compose` at
`scripts/lib/index-compose.sh:800`, so the redefinition must come after the
three `source` lines, and it does. The `touch memory/MEMORY.md` is not an
unexplained extra: `gitlore_commit_msg_freshness` walks
`find "$mempath" -type f` for the newest mtime, so without a write under the
store nothing would be newer than the summary, the summary would still read
`yes` with the fix backed out, and the assertion would be vacuous. The comment
in the test says so. The heredoc is deliberately unquoted so `$PLUGIN_ROOT`
resolves at write time, and it is the only expansion in the body — the stub's
own text contains no `$`, backtick or `$(…)`. The expanded path sits inside
double quotes in the generated script, so a `$PLUGIN_ROOT` containing spaces is
safe.

**Whitespace and BSD portability.** Every path in the added tests is quoted; no
unquoted expansion, no word-splitting on any of them. The added code uses only
`printf`, `touch`, `chmod`, `sleep`, `id`, `cat` and `git` — none of the
GNU-divergent tools `tests/helpers/bsd-stubs.bash` shadows (`sed`, `mktemp`,
`grep`, `find`, `stat`), so `tests/bsd_portability.bats` has nothing new to lock
in. `[[ … == *"unrecognised status (7)"* ]]` is bash 3.2-safe: the parentheses
are inside a quoted segment and match literally. `run --separate-stderr` is
covered by the file-level `bats_require_minimum_version 1.5.0`.

**Test isolation.** Each of the four is its own `@test` with its own
`setup_tmp_repo` and its own `make_parent_with_memory`; none reads state a
previous case left. The
`[ "$(id -u)" -eq 0 ] && skip "root ignores permission bits"` guard is present
on both cases that induce through permission bits (test 1 and test 4) and
correctly absent from the two that do not (test 2's stub, test 3's off-pin) —
matching the existing uses at `tests/commit_memory.bats:188` and
`tests/index_sync.bats:356`. As the first statement of the body it is
errexit-safe: a failing `[` on the left of `&&` is exempt from `set -e`, and the
list is not the body's last command. `chmod u+w` now follows `run` immediately
in both permission cases.

## Verification after the fixes

`scripts/run-bats.sh tests/commit_memory.bats tests/git_hook_pre_commit.bats`:

```
not ok 14 an unrecognised compose status aborts and keeps the approval
# (in test file tests/commit_memory.bats, line 254)
#   `[ "$(gitlore_commit_msg_freshness memory)" = "yes" ]' failed
not ok 33 an aborted compose keeps the approved summary usable
# (in test file tests/git_hook_pre_commit.bats, line 377)
#   `[ "$status" -eq 0 ]' failed

bats: 31 passed, 2 failed
```

Same two tests, same two assertions, same counts — the line numbers moved only
because the fixes added comment lines above them. No red turned green and no
green turned red.

`scripts/lint-shell.sh`: `lint-shell: 137 files clean`.

## Scope

Changed: `tests/commit_memory.bats`, `tests/git_hook_pre_commit.bats`. Not
staged, not committed. `scripts/lib/resolve.sh` is left backed out exactly as
RED left it. Nothing else touched.
