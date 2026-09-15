# Item 1.1 slice 5 — guard

**Test:** `a repair whose live advance fails walks back and keeps the arrival`
(`tests/merge_memory.bats`, after "a repair whose checkout follow fails walks
back and keeps the repair").

Root's own stranded-`live` repair and the tier's take fast-forward each make
one `push -q . …:refs/heads/live` call in this fixture before the repair's own
advance, so the stub fails the *third* such call (verified empirically, not
assumed) rather than the second.

## Guard pass

```
$ scripts/run-bats.sh tests/merge_memory.bats --filter "a repair whose live advance fails walks back and keeps the arrival"
bats: 1 passed, 0 failed — full log: /tmp/gitlore-bats.sFK8c2
```

`shellcheck tests/merge_memory.bats` — clean.

## Mutant

Applied in place, then reverted (`scripts/` diff confirmed clean afterward):
the `live`-advance arm's `gitlore_adopt_report_refusal_and_walk_back "$mempath" "$tier" "$old_gitlink" "$label" "$composed" "Run /gitlore:merge again." || :`
replaced with `gitlore_adopt_walk_back_tier "$mempath" "$tier" "$old_gitlink" "$label" || :`
(`scripts/lib/resolve.sh:1963`).

```
$ scripts/run-bats.sh tests/merge_memory.bats --filter "a repair whose live advance fails walks back and keeps the arrival"
not ok 1 a repair whose live advance fails walks back and keeps the arrival
# (in test file tests/merge_memory.bats, line 714)
#   `[[ "$stderr" == *"gitlore: the root index could not take tier 'ddaanet''s lines:"$'\n'"gitlore:   memory/ddaanet/MEMORY.md: duplicate pointer path a.md"* ]]' failed

bats: 0 passed, 1 failed
```

The mutant drops the refusal header and carrier-line printout (and the
`Run /gitlore:merge again.` remedy, replaced by `gitlore_adopt_walk_back_tier`'s
own default "Fix the store, then run /gitlore:merge again."), which the new
test's assertion catches.
