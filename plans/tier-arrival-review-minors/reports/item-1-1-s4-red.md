# Item 1.1 / slice 4 — RED report

**Test:** `a repair whose checkout follow fails walks back and keeps the repair`
(`tests/merge_memory.bats`, added after the slice 2 "commit build fails" test,
before "a take's repair keeps the duplicate its pin lacks").

**Command:**
`scripts/run-bats.sh tests/merge_memory.bats --filter 'checkout follow fails'`

**Verified premises before writing the test:**
- `gitlore_merge_one_store` (`scripts/lib/resolve.sh:1693`) makes the take's own
  `checkout -q --detach live` call; `gitlore_adopt_repair_arrival`'s
  checkout-follow arm (`scripts/lib/resolve.sh:1963`) is the second such call in
  this fixture's path, since `gitlore_adopt_advanced_live` and
  `gitlore_repair_stranded_live` (the only other callers of that pattern) both
  no-op on a fresh fast-forward. The stub counts matches and fails only the 2nd,
  forwarding all others.
- The arm's current wording is
  `"... its repair advanced its local 'live' but its working tree could not follow. git said:\n%s\n"`,
  which contains `could not follow`.

**Failing output (full log):**
```
1..1
not ok 1 a repair whose checkout follow fails walks back and keeps the repair
# (in test file tests/merge_memory.bats, line 662)
#   `[[ "$stderr" == *"keeps the repair."* ]]' failed
```

All premise assertions (exit status 1, stub-hit marker, `could not follow`)
passed; the first failing assertion is the new-behaviour one — today's arm calls
`gitlore_adopt_walk_back_tier` directly with no `live_holds` override, so it
prints `keeps what arrived.` instead of `keeps the repair.` (and would also fail
the next assertion, `Run /gitlore:merge again.`, since the default remedy is
`Fix the store, then run /gitlore:merge again.`).

`shellcheck tests/merge_memory.bats` — clean, no output.

No production code touched. No commit made.
