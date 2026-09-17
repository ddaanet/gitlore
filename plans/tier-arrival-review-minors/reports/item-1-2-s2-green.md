# Item 1.2 slice 2 — GREEN

## Change

`gitlore_adopt_repair_arrival`'s `mktemp` arm (`scripts/lib/resolve.sh`) now
prints
`gitlore: tier '<t>' — its arrival could not be repaired: no scratch directory could be made.`
to stderr, then calls
`gitlore_adopt_report_refusal_and_walk_back "$mempath" "$tier" "$old_gitlink" "$label" "$composed" "Run /gitlore:merge again."`,
matching the sibling transient arms.

## Result

```
scripts/run-bats.sh tests/merge_memory.bats --filter 'scratch directory cannot be made'
bats: 1 passed, 0 failed
```

Whole file: `scripts/run-bats.sh tests/merge_memory.bats` — 41 passed, 0 failed.

`shellcheck -x scripts/lib/resolve.sh tests/merge_memory.bats` — clean.

## Commit

`tests/merge_memory.bats scripts/lib/resolve.sh plans/tier-arrival-review-minors/reports/item-1-2-s2-red.md plans/tier-arrival-review-minors/reports/item-1-2-s2-green.md`
