# Item 2.1 slice 1 — GREEN report

Scope: `scripts/lib/index-sync.sh`, the two helper functions only.

## Implementation

`gitlore_index_preimage_file` and `gitlore_compose_stamp_file`
(`scripts/lib/index-sync.sh:94`, `:102`) each gained a second, optional argument
`$2` (the agent id). Both now build the `rev-parse --git-path` name with bash
parameter expansion, `"gitlore-index-preimage${2:+-$2}"` and
`"gitlore-compose-stamp${2:+-$2}"` respectively, instead of the bare literal.
`${2:+-$2}` expands to nothing when `$2` is unset or empty, so the base name is
unchanged for every existing single-argument call site, and to `-<agent id>`
when it is non-empty. This is the M3 shape the test review's mutation harness
confirmed satisfies both contracts (`item-2-1-s1-test-review.md`,
"Discrimination check").

The `rev-parse --git-path` call itself is untouched — only the string handed to
it changed — so the file still lands inside the memory submodule's gitdir via
the same mechanism as before, just with the id folded into the name rather than
the path. Comments above each function were extended by one line each to state
the new argument and its absent/empty-vs-non-empty contract.

## Order turned green

Single step: both functions edited together in one `Edit` call, since the change
is mechanically identical in each (same expansion, same position). Verified
together:

```
$ bats -f "preimage_file|compose_stamp_file" tests/index_sync.bats
1..4
ok 1 preimage_file is unsuffixed with no agent id
ok 2 preimage_file suffixes the agent id
ok 3 compose_stamp_file is unsuffixed with no agent id
ok 4 compose_stamp_file suffixes the agent id
```

## Full-suite result

```
$ scripts/run-bats.sh tests/index_sync.bats
bats: 66 passed, 0 failed
```

66 = the 64 that passed at RED plus the 2 that were red there. No collateral
damage.

## Gate verdict

Read from the sentinels
(`.git/gitlore/gates/{lint,test-unit,test-integration,check-distribution}`),
each valid for the tree — `lint`, `test-unit` and `test-integration` at hash
`204586540 1076068`, `check-distribution` at its own narrower-input hash
`1493420777 493992`, none postdated by a dirty gated path:

- `lint` — passed.
- `test-unit` — passed.
- `test-integration` — passed.
- `check-distribution` — passed.

Note: the dispatch pointed at `just check-sentinel` as the recipe to read these
from; no such recipe exists — `check-sentinel` is a shell function in the
justfile prolog, not a `just` target. Read the four gate files directly instead.

## Commit

`853de3c` — "Item 2.1/1 — the helpers key on the agent id". 4 files: the two
report files (`item-2-1-s1-red.md`, `item-2-1-s1-test-review.md`) added,
`scripts/lib/index-sync.sh` (+12/-4) and `tests/index_sync.bats` (+47) modified.

A follow-up commit carries this report plus `just format-docs`'s rewrap of the
two report files added above (`plans/` sits outside `precommit_inputs`, so the
rewrap does not invalidate the gate sentinels already recorded for `853de3c`).

## Consumers

**Not touched.** `scripts/cc-hooks/index-sync-pre.sh`, `index-sync-post.sh`,
`index-compose.sh` and `add-tier-batch.sh` all still call both helpers with one
argument; the optional `$2` defaults to empty for every one of them, so their
behavior is bit-for-bit unchanged. Reading `agent_id` and passing it through is
slices 2–4.
