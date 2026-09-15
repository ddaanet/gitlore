# Item 1.1 slice 3 — RED report

Test: `a repair beside a root problem lands in live and waits`
(`tests/merge_memory.bats`)

Command: `scripts/run-bats.sh tests/merge_memory.bats --filter '^a repair beside a root problem lands in live and waits$'`

## Failing output

```
not ok 1 a repair beside a root problem lands in live and waits
# (in test file tests/merge_memory.bats, line 753)
#   `[[ "$all" == *"its local 'live' keeps the repair."* ]]' failed

bats: 0 passed, 1 failed — full log: /tmp/claude-1000/gitlore-bats.8fqMJS
```

Fails on the new positive assertion (`keeps the repair.`), ahead of the
existing `duplicate pointer path` negative check. shellcheck clean on the
edited file.
