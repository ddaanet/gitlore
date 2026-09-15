# Item 2.2 — RED report (all six slices)

File: `tests/merge_memory.bats`, plus the suite-local `push_tier_files` helper
(placed after its first user, the weld test, following the `write_sync_driver`
precedent from minor-pass-2 test m2). No file under `scripts/` was touched;
`git diff --quiet HEAD -- scripts` holds.
`shellcheck -s bash tests/merge_memory.bats` exits 0.

Every take ran `bash "$CMD"` where `CMD="$PLUGIN_ROOT/scripts/merge-memory.sh"`
(already defined at the top of the suite). `CLAUDECODE` is not read by
merge-memory.sh or the library functions it calls, so no entry-point run needed
it set explicitly; `setup()` exports `CLAUDE_PLUGIN_ROOT` as the suite already
did. `tests/merge_memory.bats:331` and `:518` still name the setups the runbook
cites (verified by re-reading the file before editing).

## Slice 1 — "a take repairs a duplicate pointer that arrived and adopts the repair"

**Verdict: red**, on the behavioural assertion `[ "$status" -eq 0 ]` (line 570).

Premise asserted and held: the arrival's carrier on the tier's own bare remote
really carries `- [A](a.md) — x` twice (checked before the take, via
`git --git-dir ... show $remote_sha:MEMORY.md | grep -c`).

Verbatim failure output (captured with temporary debug echoes, then reverted):

```
STATUS=1
OUT=gitlore: memory — its local 'live' was stranded behind HEAD; advanced it to ea9f1a8.
gitlore: memory — already holds everything its remote does.
gitlore: tier 'ddaanet' — fast-forwarded to b046125
ERR=gitlore: the root index could not take tier 'ddaanet''s lines:
gitlore:   memory/ddaanet/MEMORY.md: duplicate pointer path a.md
gitlore: nothing was recorded, and tier 'ddaanet' is back on the commit the memory store records; its local 'live' keeps what arrived. Fix the store, then run /gitlore:merge again.
```

Today's code walks the tier back on the first refusal (no repair exists yet);
the test's `status -eq 0` expectation is what fails, not a fixture defect.

## Slice 2 (guard) — weld and interleaved-line repairs

**"a take repairs a welded line that arrived" — red**, on `[ "$status" -eq 0 ]`
(line 599). Reached via the new `push_tier_files` helper (committing the weld
line plus `welded_b.md` so the weld's second path names a real file, as
`gitlore_repair_index`'s guard requires). Premise asserted: the bare remote's
`MEMORY.md` at `$remote_sha` really contains the unsplit weld text. Today's code
hits the same walk-back arm as slice 1 (a `duplicate` rule does not fire here;
the refusal is the weld problem instead), so `status` stays 1.

**"a take repairs an interleaved non-bullet line that arrived" — red**, on
`[ "$status" -eq 0 ]` (line 647). Reached via `push_tier_fact` with a three-line
multi-line argument (`- [A](a.md) — x`, a bare stray line, then
`- [B](b.md) — y`). Premise asserted: the bare remote's carrier contains the
three lines in that order. Today's code walks back on the "interleaved
non-bullet line" refusal.

Both are recorded as red against today's (pre-job) code, per the runbook's guard
convention — no narrower implementation exists yet to test against, so there is
nothing to hold at "already green."

## Slice 3 — "a repair beside a root problem lands in live and waits"

**Verdict: red**, on `[[ "$all" == *"repaired ddaanet's arrival:"* ]]` (line
674; the earlier `status -eq 1` and `gone/x.md` assertions already passed
against today's code, which is a coincidence of both arms returning 1 and
mentioning the leftover-prefix problem — not evidence the repair ran).

Premise asserted: root really carries the committed `gone/x.md` bullet
(`grep -qF` before the take).

Verbatim output:

```
S3-STATUS=1
S3-ALL=gitlore: memory — its local 'live' was stranded behind HEAD; advanced it to e3a2178.
gitlore: memory — already holds everything its remote does.
gitlore: tier 'ddaanet' — fast-forwarded to 17e308cgitlore: the root index could not take tier 'ddaanet''s lines:
gitlore:   memory/ddaanet/MEMORY.md: duplicate pointer path a.md
gitlore:   root index line 'gone/x.md' has a prefix naming no mounted tier — it is a leftover from a removed tier and must be fixed by hand
gitlore: nothing was recorded, and tier 'ddaanet' is back on the commit the memory store records; its local 'live' keeps what arrived. Fix the store, then run /gitlore:merge again.
```

No `repaired ddaanet's arrival:` line exists yet, confirming the assertion fails
on the intended new behaviour rather than on setup.

## Slice 4 — "an arrival the repair cannot fix walks back and names upstream"

**Verdict: red**, on the unrepairable-report sentence assertion (line 710).

Premises asserted and held: `weld_line_n` (computed independently from
`git show $remote_sha:MEMORY.md`) is non-empty and `memory/ddaanet/z.md` does
not exist. Verified `weld_line_n=8`, matching today's check's own report of
"line 8 welds" for the same arrival — confirming the line-number computation in
the test is correct against the target behaviour (the assertion checks
`live:MEMORY.md: line $weld_line_n welds`, the arrival's own numbering per the
runbook).

Verbatim output:

```
S4-STATUS=1
S4-ALL=gitlore: memory — its local 'live' was stranded behind HEAD; advanced it to 89b5cd8.
gitlore: memory — already holds everything its remote does.
gitlore: tier 'ddaanet' — fast-forwarded to 779be2dgitlore: the root index could not take tier 'ddaanet''s lines:
gitlore:   memory/ddaanet/MEMORY.md: duplicate pointer path b.md
gitlore:   memory/ddaanet/MEMORY.md: line 8 welds two pointer bullets onto one line — z.md is invisible to every parse and the next compose will drop it; split them
gitlore: nothing was recorded, and tier 'ddaanet' is back on the commit the memory store records; its local 'live' keeps what arrived. Fix the store, then run /gitlore:merge again.
```

Today's code prints the old walk-back message, never the new unrepairable
sentence (`gitlore: tier 'ddaanet' took an index the take cannot repair...`) or
the `live:MEMORY.md: ` re-prefixed line.

## Slice 5 (guard) — "a local live that ran ahead with a defective carrier is repaired"

**Verdict: red**, on `[ "$status" -eq 0 ]` (line 739).

Reached through `gitlore_adopt_advanced_live` (fetch `live`, detach at it,
compose, `commit_memory_state`, then strand a duplicate-carrying commit ahead of
the pin and checkout back to the pin — mirroring `strand_live_ahead_of_pin` but
with a duplicate line instead of `seed_tier_bullet`). Premise asserted: `HEAD`
sits at `pin` and `live` (`stranded`) differs from it. Today's code reaches the
same "root index could not take tier's lines" walk-back arm as slice 1, via the
advanced-live path instead of the remote-fetch path, so `status` stays 1.

## Slice 6 — "a refused live update after the repair leaves no trace"

**Verdict: red**, on `[[ "$output$stderr" == *"live.lock"* ]]` (line 773).

`GITLORE_GIT_RETRY_SCHEDULE=0` is exported before the `refs/heads/live.lock`
file is created, per the dispatch note. Premise asserted: `stranded != pin`
before the lock is held.

Verbatim output:

```
S6-STATUS=1
S6-ALL=gitlore: memory — its local 'live' was stranded behind HEAD; advanced it to 0c1cc52.
gitlore: memory — already holds everything its remote does.
gitlore: tier 'ddaanet' — its local 'live' held commits the memory store never recorded; adopted them at be62cef.gitlore: the root index could not take tier 'ddaanet''s lines:
gitlore:   memory/ddaanet/MEMORY.md: duplicate pointer path a.md
gitlore: nothing was recorded, and tier 'ddaanet' is back on the commit the memory store records; its local 'live' keeps what arrived. Fix the store, then run /gitlore:merge again.
```

Today's code never attempts a `push . <R>:refs/heads/live` at all (there is no
`R` — no repair exists), so the held `refs/heads/live.lock` is never even
contended; the take walks back on the plain duplicate refusal instead, exactly
as in slice 5. This confirms the red is behavioural (the lock-contention path
this slice targets does not exist yet), not a fixture mistake — the lock file
itself is inert against today's code, which is what a guard against a
not-yet-built code path is expected to show.

## Whole-suite run and lint

`scripts/run-bats.sh tests/merge_memory.bats` (no filter):
**23 passed, 7 failed** — the 7 new tests above; every pre-existing test in the
file is unaffected. `shellcheck -s bash tests/merge_memory.bats` exits 0.

## Notes

- No file under `scripts/` was edited (`git diff --quiet HEAD -- scripts`
  holds); `gitlore_repair_index`, `gitlore_adopt_tier_into_root`,
  `gitlore_compose_problems_in` etc. exist already (Items 1.1, 2.1) and needed
  no stub.
- `push_tier_files` is the only new suite helper, matching the dispatch's shape
  request (mirrors `push_tier_fact`, commits in a plain clone of the tier's bare
  remote, pushes `live`) and is placed immediately after its sole caller (the
  weld test), per the `write_sync_driver`-after-its-users precedent named in the
  dispatch.
