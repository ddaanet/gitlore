# Item 1.1 slice 3 — test review

Verdict: accepted with fixes. Both slice-3 cases are genuinely red on their own
assertions, both inductions reach the mechanism the slice names, and neither
passes against an implementation that gets the two arms backwards. Three
findings fixed in place; `scripts/` untouched
(`git diff --exit-code scripts/lib/resolve.sh` clean).

## Mechanical re-run

`scripts/run-bats.sh tests/commit_memory.bats`, run before any edit:

```
not ok 12 an off-pin compose refusal is reported and does not abort the commit
# (in test file tests/commit_memory.bats, line 182)
#   `[[ "$stderr" == *"tier composition refused"* ]]' failed
not ok 13 a compose write failure aborts the commit
# (in test file tests/commit_memory.bats, line 203)
#   `[ "$status" -ne 0 ]' failed

bats: 11 passed, 2 failed
```

Two FAILs, no PASS, no ERROR. Each stops on an assertion inside the case, not on
a missing symbol or a broken fixture; case 12 gets past its exit-code and
HEAD-advanced assertions first, so the fixture reached and completed a real
commit. The `[ "$(id -u)" -eq 0 ] && skip` guard on case 13 did not fire — the
reported line is the `$status` assertion, four lines past it.

## Induction verification (against the source, not the report)

Both inductions were checked by driving `gitlore_compose` directly on each
case's fixture in a throwaway bats file, since neither case's own assertions
distinguish rc 1 from rc 2 today (`|| true` swallows both).

- **rc 1 fixture** → `gitlore_compose memory` returns **1**, output a single
  problem line:
  `tier 'ddaanet' is checked out at 37b7b665b870 but the memory store records 69bbc2dc1105: it was moved outside /gitlore:merge…`.
  That is `gitlore_compose_check_pins`' pin-mismatch line
  (`scripts/lib/index-compose.sh:341`), not its mid-merge line and not a
  `gitlore_compose_check` refusal — so the case pins the rc-1 arm and not slice
  1's `gitlore_guard_stale_merge_state`, which the tier never trips. The empty
  commit inside `memory/ddaanet` moves the tier's worktree HEAD while memory's
  index keeps the old gitlink, and the compose call sits ahead of
  `gitlore_sync_tiers_to_live`, so nothing restages that gitlink first.
- **rc 2 fixture** → returns **2**, with git's own message:
  `mv: cannot move '…/.git/modules/gitlore-memory/modules/ddaanet/gitlore-compose.tmp.288' to 'memory/ddaanet/MEMORY.md': Permission denied`.
  That both confirms rc 2 is reached (not rc 1) and independently confirms the
  rewritten `tests/index_compose.bats` comment: the temp file is in the tier's
  gitdir and the failing operation is the `mv` into the chmod-ed directory
  (`scripts/lib/index-compose.sh:656` and `:676`).

Arm-crossing check: the rc-1 case asserts exit 0, so an implementation that
aborts on any non-zero rc fails it; the rc-2 case asserts non-zero, so one that
never aborts fails it. The rc-1 case asserts the rc-1 header text specifically,
so an implementation emitting the rc-2 wording on both arms fails it too.

## Findings, all fixed

**1 (major) — the rc-2 case would pass against a silent abort.** As written it
asserted only exit status, an unchanged memory HEAD and the surviving
`gitlore_commit_msg_file`. An implementation whose `case` arm returns non-zero
with nothing on stderr satisfies all three, and that is the worse failure of the
two: a refused commit with no explanation. The item fixes the rc-2 text as much
as the rc-1 text, and nothing on the commit path asserts it anywhere else. Added
two assertions, mirroring the rc-1 case's two-strings-for-two-faults reasoning —
`tier composition could not write an index` (the header, present in both arms of
`gitlore_say_for_agent_or_user` per the item) and
`could not write memory/ddaanet/MEMORY.md` (`gitlore_compose`'s own forwarded
problem line). The `run` became `CLAUDECODE=1 run --separate-stderr`, matching
the rc-1 case and the file's existing convention, and pinning stderr as the
channel the outline requires. The case still fails first on
`[ "$status" -ne 0 ]`, so its red is unchanged.

**2 (minor) — the rc-1 case's comment stated the opposite of the fixture.** It
claimed "the tier stays clean itself, so `gitlore_sync_tiers_to_live` has
nothing to commit there". `seed_tier_bullet` leaves the tier worktree dirty
(` M MEMORY.md` plus an untracked `shared.md`), so that function does commit
there — the mismatch survives the compose for a different reason, namely that
the compose runs before it. Nothing in the assertions depended on the false
claim, but it is the kind of comment a later reader reasons from. Rewritten to
state the real reason, and to say why the carrier/root disagreement is in the
fixture at all (so the refusal withholds real work rather than being a no-op).

**3 (minor) — "the store's own gitdir" in the rewritten
`tests/index_compose.bats` comment.** Accurate but ambiguous in a test where
"the store" reads as the memory store; the gitdir is the tier's. Changed to "the
tier's own gitdir". No other part of that case touched.

## Portability

Nothing GNU-specific: `chmod a-w`/`chmod u+w`, `git commit --allow-empty`,
`[[ … == *…* ]]` and `$(…)` only. No `sed`, `mktemp`, `find` or `stat` in either
case. No fixture value is split on whitespace — every path is a literal, and the
one interpolated path (`$(gitlore_commit_msg_file memory)`) is quoted. The
`[ "$(id -u)" -eq 0 ] && skip` guard follows the four existing uses in
`tests/index_sync.bats`.

## Post-fix state

- `scripts/run-bats.sh tests/commit_memory.bats` — 11 passed, 2 failed; both
  failures still on their own assertions (now lines 183 and 204).
- `scripts/run-bats.sh tests/index_compose.bats` — 63 passed, 0 failed (the
  comment change is inert, as intended).
- `shellcheck -s bash tests/commit_memory.bats tests/index_compose.bats` — exit
  0.
- `git status --porcelain` — only `tests/commit_memory.bats` and
  `tests/index_compose.bats`. Not committed; these ride the GREEN commit.
