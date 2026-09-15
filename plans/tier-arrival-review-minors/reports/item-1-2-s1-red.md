# Item 1.2 slice 1 — RED

**Test:** `a repair's scratch directory lives under TMPDIR, not the tier's gitdir`
(`tests/merge_memory.bats`, inserted before "a repair whose checkout follow
fails walks back and keeps the repair").

**Command:**
`scripts/run-bats.sh tests/merge_memory.bats --filter "a repair's scratch directory lives under TMPDIR"`

**Failing output:**

```
not ok 1 a repair's scratch directory lives under TMPDIR, not the tier's gitdir
# (in test file tests/merge_memory.bats, line 656)
#   `[ "$(grep -c -F -- "$gitdir/gitlore-repair." "$seen")" -eq 0 ]' failed

bats: 0 passed, 1 failed
```

Fails on the "no line under the tier gitdir" assertion, as intended — not a
setup error, and ordered ahead of the `$TMPDIR` assertion so it is the one
that trips today.

**What `seen` contained** (captured via a temporary debug `cp`, reverted
before the final run above):

```
/tmp/claude-1000/gitlore-test.S1zSGT/.git/modules/gitlore-memory/modules/ddaanet/gitlore-repair.kqGVlO
```

One line, under the tier's gitdir (`.git/modules/gitlore-memory/modules/ddaanet`),
none under `$TMPDIR` — confirming today's `gitlore_adopt_repair_arrival`
creates the scratch directory inside the tier's gitdir via
`mktemp -d "$gitdir/gitlore-repair.XXXXXX"`.

shellcheck: clean on `tests/merge_memory.bats`. No production code touched;
nothing committed.
