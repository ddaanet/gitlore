# Item 2.1 / Slice 1 — RED report

Two tests added to `tests/push_behind_vs_diverged.bats`, in the `:320` section,
plus three fixture helpers (`advance_tier_past_remote`, `push_side_ref_child`,
`install_tier_live_snap_hook`) and a shared setup (`setup_repair_race_on_aa`).
No production code touched.

## Run

`scripts/run-bats.sh tests/push_behind_vs_diverged.bats`:

```
not ok 16 a repair the take makes to another tier mid-loop is published, not left for the next push (behind)
# (in test file tests/push_behind_vs_diverged.bats, line 557)
#   `[ "$status" -eq 0 ]' failed
not ok 17 a repair the take makes to another tier mid-loop is published, not left for the next push (ahead-of-HEAD)
# (in test file tests/push_behind_vs_diverged.bats, line 573)
#   `[ "$status" -eq 0 ]' failed

bats: 15 passed, 2 failed
```

The other 15 tests in the file, including the existing repair-publication
cases at :338, :376 and :404, pass unchanged.

## Which assertion fails, and why that is the defect

Both variants fail on their *last* assertion — the one checking that `aa`'s
own remote holds the commit memory's remote recorded as `aa`'s gitlink:

```bash
R=$(git --git-dir="$MEMORY_REMOTE" rev-parse live:aa)
[ "$R" = "$aa_live" ]                                          # passes
run git --git-dir="$TMP_REPO/.bare-aa.git" cat-file -e "$R^{commit}"
[ "$status" -eq 0 ]                                             # FAILS
```

A verbose rerun (`bats --verbose-run --filter mid-loop`) shows every earlier
assertion holding and the concrete failure:

```
gitlore: tier 'aa' — fast-forwarded to 9e65e6d
gitlore: repaired aa's arrival: dropped a duplicate pointer line: - [A](a.md) — x
gitlore: tier 'aa' — the repair is committed in its local 'live', and this push publishes it.
gitlore: memory — recorded aa's move in a bookkeeping commit; the store is clean.
gitlore: tier 'bb' — fast-forwarded to 1d9633f
gitlore: memory — recorded bb's move in a bookkeeping commit; the store is clean.
fatal: Not a valid object name 13137ea893e64f4dc8df6dfa5e78132ed9eeded0^{commit}
```

So, in order:
- the outer `run --separate-stderr bash "$CMD"` exits 0 — confirmed by every
  line above printing, not by a separate assertion failing first;
- the one-shot hook fired: `aa`'s remote `live` moved to D behind the push's
  back (`[ "$(git --git-dir=.../.bare-aa.git rev-parse live)" = "$d" ]`
  passes);
- the take, running while `bb` is processed (`tier 'bb' — fast-forwarded…` /
  `tier 'bb' — its local 'live' held commits… adopted them…`, depending on
  variant), also fast-forwarded and repaired `aa` — its message says so
  (`tier 'aa' — fast-forwarded…`, `repaired aa's arrival…`), even though
  `aa`'s own loop iteration had already finished;
- memory recorded the repair as `aa`'s gitlink and published that to
  `$MEMORY_REMOTE` (`R = $aa_live` passes);
- `aa`'s own remote (`.bare-aa.git`) never received it — `cat-file -e` on the
  recorded sha fails with `fatal: Not a valid object name`.

This is exactly the race Item 2.1 targets: the mid-loop take pass repairs a
tier whose own loop iteration already ran, but nothing pushes that repair to
*that* tier's remote — the removed-in-this-item retry push only covers the
tier currently being processed (`bb`), never a different tier the same take
pass also touched (`aa`). The message
`gitlore: tier 'aa' — the repair is committed in its local 'live', and this
push publishes it.` is printed and is false: this run does not publish it.

Both variants reproduce; neither is a guard.
