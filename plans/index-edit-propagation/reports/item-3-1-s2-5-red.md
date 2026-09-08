# Item 3.1 slice 2.5 — RED

Two cases, each red on its own assertion against the current, truncating
`gitlore_relay_write` (`scripts/lib/index-sync.sh`). Nothing in
`scripts/lib/index-sync.sh`, `scripts/cc-hooks/index-compose.sh`, or
`scripts/cc-hooks/index-sync-post.sh` was touched.

Two other files show as modified in `git status`
(`plans/index-edit-propagation/reports/item-3-1-s2-code-review.md`,
`item-3-1-s2-green.md`) — not this dispatch's work; left untouched.

## Case 1 — `tests/index_sync.bats`: `relay_write merges a second report into an existing marker`

```
not ok 56 relay_write merges a second report into an existing marker
# (in test file tests/index_sync.bats, line 1027)
#   `[ "$GITLORE_RELAY_SYSMSG" = '--- gitlore-relay agent a1 ---' failed
```

Dies on the SYSMSG exact block: `gitlore_relay_write memory a1 "S1" "C1"` then
`gitlore_relay_write memory a1 "S2" "C2"` leaves the marker holding only
`S2`/`C2` (the second `>` truncates the first write), so a drain that folds the
one surviving marker never produces `S1` anywhere in `GITLORE_RELAY_SYSMSG`.

**Non-vacuity.** Each of the case's four assertions is proved discriminating by
a mutation of `gitlore_relay_write` that reds it — the marker bytes after the
single write, the marker count, and the two drained blocks. The full mutation
table, and the two defects the mutation pass found in this case's first draft
(a framing-line count that could not see the second-marker shape, and an
unpinned single-write path), are in
`reports/item-3-1-s2-5-test-review.md`. The draft reviewed there used ordering
substrings, four cross-checks and a per-agent framing count in place of the two
exact blocks; the assertions after the death point never ran under the
un-reordered RED, which is how a `grep -o -F "$frame"` option-parsing bug
survived into it — `grep` consumed the pattern's leading `-`s as flags
(`grep: unrecognized option '--- gitlore-relay agent a1 ---'`). That line is
gone with the block it belonged to.

## Case 2 — `tests/cc_hook_index_compose.bats`: `both PostToolBatch hooks in one keyed batch reach the parent`

```
not ok 94 both PostToolBatch hooks in one keyed batch reach the parent
# (in test file tests/cc_hook_index_compose.bats, line 410)
#   `[[ "$output" == *"reset frontmatter to match MEMORY.md"* ]]' failed
```

Drives `index-sync-post.sh` keyed `a1` (via a new `sync_feed()` helper mirroring
the file's own `pre()`/`feed()`), then `index-compose.sh` keyed `a1` over the
same batch — `hooks.json`'s own order — then an unkeyed (`feed`) parent-side
run. Died on the parent's folded `systemMessage` missing the sync hook's
"reset frontmatter to match MEMORY.md" line: the compose hook's later keyed
write truncated it out of the `a1` marker, so only "recomposed tier pointers"
survived to be drained.

Adapted from the code review's §F1 hand-run transcript: same fixture shape
(pre + a root index edit, then both hooks keyed as `a1` over one batch), with
two differences, both noted in the test's own comment: (1) `index-sync-post.sh`
is driven through a real script invocation (`sync_feed`) rather than the
transcript's manual `bash` call, and (2) the assertion lands on the drained
parent's `systemMessage`, not on the marker's raw bytes — the transcript's own
check ("does the marker still hold the sync report?") is exactly what the
helper-level case (Case 1) already pins; this case exists to prove the loss
reaches the *parent*, which nothing else in the suite drives both hooks
far enough to see.

**Non-vacuity**, same method — a scratch copy of the test with the assertions
after the dying one reordered ahead, run with `bats -f`, removed after:

| assertion | at RED | why |
|---|---|---|
| `systemMessage` carries `gitlore-relay agent a1` (framing present) | passes — already runs before the dying one in the real test, unaffected | the relay fires regardless of which report survived inside it |
| `systemMessage` carries `recomposed tier pointers` (the dying one's neighbour, moved ahead in the probe) | passes — vacuous at RED | compose's own report is exactly what did survive the truncation, so this line is present whether or not the defect is fixed |
| `systemMessage` carries `reset frontmatter to match MEMORY.md` | **fails — this is the assertion that dies in the real test too** | the truncated line |
| marker removed after the unkeyed run | passes — vacuous at RED | the drain always `rm -f`s whatever marker it found, truncated or not |

So of the four assertions in the closing block, one is the genuine, load-bearing
red (matches the real test's own death point exactly when run in its original
position); the other three are correctly vacuous at RED because the compose
hook's own report and the drain's unlink are both unaffected by this defect —
they exist to catch a wiring that drops one hook's report entirely rather than
merely truncating it into the other's, which is a different (already-fixed)
failure mode from F2/F1's predecessor bugs, not this slice's.

Earlier assertions in the same test (the sync hook's own emitted
`systemMessage`, the frontmatter write, the compose hook's own `systemMessage`,
the spliced tier bullet, the marker's existence) all pass today — none is
part of this slice's defect, and each already ran and passed before the test
reaches the dying assertion, so their non-vacuity was established in the
normal (un-reordered) run itself.

## Scope

Touched: `tests/index_sync.bats` (+66 lines), `tests/cc_hook_index_compose.bats`
(+75 lines: `POST`, `sync_feed()`, and the new case), and this report. No
`scripts/lib/index-sync.sh`, no hook script, no `just` recipe run. Tree is
dirty and unstaged; nothing committed. Scratch reorder probes were appended to
each real test file, run with `bats -f`, and removed — never relocated to a
temp directory, per `memory/ddaanet/genuine-red-not-missing-sut.md`'s "mutate
in place, never relocate" rule, since relocating either file would break its
`load helpers/...` paths.

## Checks that passed, by name

- `scripts/run-bats.sh tests/index_sync.bats tests/cc_hook_index_compose.bats`
  — 99 passed, 2 failed (the two new cases, on the assertions shown above; no
  other case regressed). Unchanged in shape after the test review's fixes to
  case 1, which moved its death point to `tests/index_sync.bats:1027`.
- `shellcheck -s bash tests/index_sync.bats tests/cc_hook_index_compose.bats`
  — clean.
- `scripts/lint-shell.sh` — 137 files clean.
- Reorder-probe run (Case 1): `bats -f "SCRATCH reorder probe" tests/index_sync.bats`
  — over the first draft of the case, before the test review replaced its
  closing block; it caught the `grep -o -F` leading-dash bug that would
  otherwise have broken the test at GREEN.
- Reorder-probe run (Case 2): `bats -f "SCRATCH reorder probe" tests/cc_hook_index_compose.bats`
  — confirmed the three reordered assertions are vacuous at RED for the stated
  reason and the sync-line assertion is the one genuine red, matching the real
  test's own death point.
- `git status --porcelain` after removing both scratch probes — only the four
  files listed under Scope/above are modified; no stray scratch file or
  directory left behind.
